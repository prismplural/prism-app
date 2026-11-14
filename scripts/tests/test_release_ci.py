"""Unit tests for the hosted release build helpers.

Fakes only: no real git repository, signing identity, provisioning profile,
keystore, keychain, Flutter, fastlane or Apple toolchain is used. Every
external command goes through ``release_ci.run``, which these tests replace
with a recorder, and every filesystem effect happens under a temporary
directory.

Run: python3 -m unittest discover -s scripts/tests -p 'test_*.py'
"""

from __future__ import annotations

import base64
import datetime
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

# Captured before any test patches shutil.which or clears os.environ.
REAL_PATH = os.environ.get("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
# Resolved at import time: several tests clear PATH before running.
REAL_AGE = shutil.which("age")
REAL_AGE_KEYGEN = shutil.which("age-keygen")

import release_ci  # noqa: E402  (path setup must come first)

SHA = "a" * 40
OTHER_SHA = "b" * 40
CERT_A = "AB" * 32
CERT_B = "CD" * 32

PUBSPEC = """name: prism_plurality
version: 0.16.0+16004

dependencies:
  prism_sync:
    git:
      url: https://github.com/prismplural/prism-sync.git
      path: dart/packages/prism_sync
      ref: {ref}
  prism_sync_drift:
    git:
      url: https://github.com/prismplural/prism-sync.git
      path: dart/packages/prism_sync_drift
      ref: {ref}
  prism_sync_flutter:
    git:
      url: https://github.com/prismplural/prism-sync.git
      path: dart/packages/prism_sync_flutter
      ref: {ref}
"""


FASTLANE_PINNED = "2.239.0"


def FASTLANE_LANE(lane: str):
    """Match the activated lane invocation: fastlane _2.239.0_ <lane>."""
    return lambda argv: argv[:1] == ["fastlane"] and argv[-1:] == [lane]


def fingerprint(value: str) -> str:
    """Format a hex fingerprint the way keytool prints it."""
    pairs = [value[index : index + 2] for index in range(0, len(value), 2)]
    return "SHA256: " + ":".join(pairs)


class FakeCommands:
    """Records argv and answers from registered matchers."""

    def __init__(self):
        self.calls: list[dict] = []
        self.handlers: list[tuple] = []

    def on(self, matcher, respond):
        self.handlers.append((matcher, respond))
        return self

    def on_prefix(self, prefix, respond=None, *, stdout="", code=0, stderr=""):
        prefix = list(prefix)

        def matcher(argv):
            return argv[: len(prefix)] == prefix

        def responder(argv, env):
            if respond is not None:
                result = respond(argv, env)
                if result is not None:
                    return result
            return code, stdout, stderr

        return self.on(matcher, responder)

    def __call__(self, argv, *, cwd=None, env=None, check=True, quiet=False, stream=False, capture_limit=None):
        argv = [str(part) for part in argv]
        self.calls.append(
            {"argv": argv, "cwd": str(cwd) if cwd else None, "env": env, "stream": stream}
        )
        for matcher, responder in self.handlers:
            if matcher(argv):
                code, stdout, stderr = responder(argv, env)
                break
        else:
            code, stdout, stderr = 0, "", ""
        result = release_ci.Result(argv, code, stdout, stderr, streamed=stream)
        if check and code != 0:
            raise release_ci.ToolError(f"command failed ({code}): {' '.join(argv)}\n{stderr}")
        return result

    def calls_with(self, *prefix) -> list[list[str]]:
        return [call["argv"] for call in self.calls if call["argv"][: len(prefix)] == list(prefix)]

    def fastlane_calls(self) -> list[list[str]]:
        return [call["argv"] for call in self.calls if call["argv"][:1] == ["fastlane"]]

    def calls_for_lane(self, lane: str) -> list[list[str]]:
        return [call["argv"] for call in self.calls if FASTLANE_LANE(lane)(call["argv"])]

    def remove(self, probe) -> None:
        """Drop handlers whose matcher answers the probe argv."""
        self.handlers = [handler for handler in self.handlers if not handler[0](list(probe))]

    def flattened(self) -> str:
        return "\n".join(" ".join(call["argv"]) for call in self.calls)


class ReleaseTestCase(unittest.TestCase):
    """Shared fixture: temporary repo, temporary RUNNER_TEMP, fake commands."""

    fastlane_pinned = FASTLANE_PINNED

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo = root / "repo"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "android" / "app").mkdir(parents=True)
        for relative in ("ios/Podfile.lock", "macos/Podfile.lock"):
            lock = self.repo / relative
            lock.parent.mkdir(parents=True, exist_ok=True)
            lock.write_text(
                "PODS:\n  - Flutter (1.0.0)\n\nCOCOAPODS: 1.16.2\n"
            )
        (self.repo / "fastlane").mkdir(parents=True)
        (self.repo / "pubspec.yaml").write_text(PUBSPEC.format(ref=SHA))
        self.runner_temp = root / "runner-temp"
        self.runner_temp.mkdir()
        self.profiles = root / "profiles"
        self.profiles.mkdir()

        self.commands = FakeCommands()
        self.recipient = "age1" + "qz" * 29
        self.env = {
            "GITHUB_ACTIONS": "true",
            "RUNNER_TEMP": str(self.runner_temp),
            "PRISM_EXPECTED_REVISION": SHA,
            "PRISM_RELEASE_SYMBOLS_RECIPIENT": self.recipient,
            "FASTLANE_VERSION": "2.239.0",
        }
        patches = [
            (release_ci, "REPO_ROOT", self.repo),
            (release_ci, "run", self.commands),
            (release_ci, "profile_search_path", lambda: self.profiles),
            (release_ci, "_SECRETS", []),
        ]
        for target, attribute, value in patches:
            original = getattr(target, attribute)
            setattr(target, attribute, value)
            self.addCleanup(setattr, target, attribute, original)

        environ = dict(os.environ)
        os.environ.clear()
        os.environ.update(self.env)
        self.addCleanup(self._restore_environ, environ)

        original_which = release_ci.shutil.which
        release_ci.shutil.which = lambda name: f"/fake/bin/{name}"
        self.addCleanup(setattr, release_ci.shutil, "which", original_which)

        self.stub_git()
        self.stub_toolchain()
        # A matching resolved dependency graph, as pub writes it after
        # `flutter pub get --enforce-lockfile`; tests that need a mismatch
        # overwrite it.
        write_package_config(self.repo, {name: SHA for name in release_ci.SYNC_PACKAGES})

    def _restore_environ(self, environ):
        os.environ.clear()
        os.environ.update(environ)

    # -- stubs ------------------------------------------------------------

    def stub_git(self, *, head=SHA, status="", tracked_status=""):
        self.commands.on_prefix(["git", "rev-parse", "HEAD"], stdout=head + "\n")
        self.commands.on_prefix(["git", "rev-parse", "--short", "HEAD"], stdout="abc1234\n")
        self.commands.on_prefix(["git", "rev-parse", "--abbrev-ref", "HEAD"], stdout="main\n")
        self.commands.on_prefix(["git", "describe", "--always"], stdout="v0.16.0-3-gbad84f30a\n")
        self.commands.on(
            lambda argv: argv[:3] == ["git", "status", "--porcelain"] and "--untracked-files=all" in argv,
            lambda argv, env: (0, status, ""),
        )
        self.commands.on(
            lambda argv: argv[:3] == ["git", "status", "--porcelain"] and "--untracked-files=no" in argv,
            lambda argv, env: (0, tracked_status, ""),
        )

    def stub_toolchain(self):
        self.commands.on_prefix(["flutter", "--version"], stdout="Flutter 3.44.8 • channel stable\n")
        self.commands.on(
            lambda argv: argv[:1] == ["fastlane"] and argv[-1:] == ["--version"],
            lambda argv, env: (0, f"fastlane installation at path: /fake/gems\nfastlane {self.fastlane_pinned}\n", ""),
        )
        self.commands.on_prefix(["xcodebuild", "-version"], stdout="Xcode 26.6\nBuild version 17A1\n")
        self.commands.on_prefix(["swift", "--version"], stdout="Apple Swift version 6.2\n")
        self.commands.on_prefix(["age", "--version"], stdout="1.3.2\n")
        self.commands.on_prefix(["ruby", "--version"], stdout="ruby 3.3.0\n")
        self.commands.on_prefix(["gem", "list"], stdout="*** LOCAL GEMS ***\ncocoapods (1.16.2)\nfastlane (2.241.2)\n")
        self.commands.on_prefix(["pod", "--version"], stdout="1.16.2\n")

        def tar_run(argv, env):
            out = Path(argv[2])
            root = Path(argv[argv.index("-C") + 1])
            with tarfile.open(out, "w:gz") as archive:
                for path in sorted(root.rglob("*")):
                    archive.add(path, arcname="./" + path.relative_to(root).as_posix(), recursive=False)
            return 0, "", ""

        def age_run(argv, env):
            target = Path(argv[argv.index("-o") + 1])
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"age-ciphertext")
            return 0, "", ""

        self.commands.on_prefix(["tar", "-czf"], respond=tar_run)
        self.commands.on_prefix(["age", "-R"], respond=age_run)
        self.commands.on_prefix(["dart", "--version"], stdout="Dart 3.11.1\n")
        self.commands.on_prefix(["rustc", "--version"], stdout="rustc 1.91.0\n")
        self.commands.on_prefix(["java", "-version"], stdout='openjdk version "17.0.13"\n')

    def stub_android_build(self, *, artifact_cert=CERT_A, keystore_cert=CERT_A, abis=None):
        abis = abis if abis is not None else ["arm64-v8a", "armeabi-v7a", "x86_64"]

        def flutter_build(argv, env):
            bundle_dir = self.repo / "build" / "app" / "outputs" / "bundle" / "release"
            bundle_dir.mkdir(parents=True, exist_ok=True)
            (bundle_dir / "app-release.aab").write_bytes(b"signed bundle bytes")
            symbols = release_ci.symbols_dir("android") / "dart"
            symbols.mkdir(parents=True, exist_ok=True)
            (symbols / "app.android-arm64.symbols").write_text("symbols")
            mapping = self.repo / "build" / "app" / "outputs" / "mapping" / "release"
            mapping.mkdir(parents=True, exist_ok=True)
            (mapping / "mapping.txt").write_text("mapping")
            return 0, "", ""

        self.commands.on_prefix(["flutter", "build", "appbundle"], respond=flutter_build)
        self.commands.on_prefix(
            ["keytool", "-list", "-v"], stdout=f"Certificate fingerprint (SHA256): {fingerprint(keystore_cert)}\n"
        )
        self.commands.on_prefix(["jarsigner", "-verify"], stdout="jar verified.\n")
        self.commands.on_prefix(["keytool", "-printcert", "-jarfile"], stdout=fingerprint(artifact_cert) + "\n")
        listing = "".join(f"  1000  01-01-2026 00:00   base/lib/{abi}/libapp.so\n" for abi in abis)
        self.commands.on_prefix(["unzip", "-l"], stdout=listing)


    def stub_apple_credentials(self, platform):
        if platform == "ios-store":
            os.environ["IOS_DISTRIBUTION_P12_BASE64"] = base64.b64encode(b"p12").decode()
            os.environ["IOS_DISTRIBUTION_P12_PASSWORD"] = "p12-pass"
            os.environ["IOS_APP_STORE_PROFILE_BASE64"] = base64.b64encode(b"profile").decode()
        else:
            os.environ["MACOS_DEVELOPER_ID_P12_BASE64"] = base64.b64encode(b"p12").decode()
            os.environ["MACOS_DEVELOPER_ID_P12_PASSWORD"] = "p12-pass"
            os.environ["MACOS_DEVELOPER_ID_PROFILE_BASE64"] = base64.b64encode(b"profile").decode()
            os.environ["ASC_KEY_ID"] = "KEYID123"
            os.environ["ASC_ISSUER_ID"] = "issuer-uuid"
            os.environ["ASC_KEY_P8"] = "-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----"
        if platform == "ios-store":
            os.environ["PRISM_BETA_REGISTRATION_TOKEN"] = "beta-token-value"

        # A real synthetic profile: date and data values included, exactly the
        # types that make a JSON conversion impossible.
        profile = {
            "Name": "Prism App Store",
            "UUID": "11111111-2222-3333-4444-555555555555",
            "TeamIdentifier": ["GF2W9X3Y6L"],
            "Platform": ["iOS"] if platform == "ios-store" else ["OSX"],
            "ExpirationDate": datetime.datetime(2099, 1, 1),
            "ProvisionsAllDevices": platform == "macos",
            "DeveloperCertificates": [b"synthetic-der-certificate"],
        }
        self.commands.on_prefix(
            ["security", "cms", "-D", "-i"],
            stdout=plistlib.dumps(profile, fmt=plistlib.FMT_XML).decode("utf-8"),
        )
        self.commands.on_prefix(["security", "list-keychains", "-d", "user"], stdout='    "/old/login.keychain-db"\n')
        self.commands.on(
            lambda argv: argv[:2] == ["security", "create-keychain"],
            lambda argv, env: (Path(argv[-1]).write_bytes(b"keychain"), (0, "", ""))[1],
        )
        self.commands.on_prefix(["security", "set-keychain-settings"], stdout="")
        self.commands.on_prefix(["security", "unlock-keychain"], stdout="")
        self.commands.on_prefix(["security", "import"], stdout="1 identity imported.\n")
        self.commands.on_prefix(["security", "set-key-partition-list"], stdout="")
        self.commands.on_prefix(["security", "delete-keychain"], stdout="")
        return profile

    def write_dsyms(self, platform):
        """A minimal dSYM bundle where the platform's lane leaves one."""
        if platform == "ios-store":
            root = self.repo / "build" / "ios" / "ci" / "Runner.xcarchive" / "dSYMs"
        else:
            root = self.repo / "build" / "macos" / "Build" / "Products" / "Release"
        dwarf = root / "Prism.app.dSYM" / "Contents" / "Resources" / "DWARF"
        dwarf.mkdir(parents=True, exist_ok=True)
        (dwarf / "Prism").write_bytes(b"dwarf-bytes")

    def stub_fastlane(self, platform, *, facts=None):
        artifact_suffix = "ipa" if platform == "ios-store" else "dmg"

        def fastlane(argv, env):
            self.write_dsyms(platform)
            artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
            artifact_dir.mkdir(parents=True, exist_ok=True)
            (artifact_dir / f"Prism-0.16.0+16004-{platform}.{artifact_suffix}").write_bytes(b"artifact")
            facts_path = Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json"
            facts_path.write_text(json.dumps(facts or {"scheme": "test", "verified": "fake"}))
            return 0, "", ""

        self.commands.on_prefix(["fastlane"], respond=fastlane)


class VersionAndPinTest(ReleaseTestCase):
    def test_parses_version_with_build_number(self):
        self.assertEqual(
            release_ci.parse_version("version: 0.16.0+16004\n"),
            {"pubspec": "0.16.0+16004", "name": "0.16.0", "build": "16004"},
        )

    def test_rejects_version_without_build_number(self):
        with self.assertRaises(release_ci.UsageError):
            release_ci.parse_version("version: 0.16.0\n")

    def test_sync_pins_must_agree(self):
        with self.assertRaises(release_ci.UsageError):
            release_ci.sync_pins(PUBSPEC.format(ref=SHA).replace(f"ref: {SHA}\n  prism_sync_drift", f"ref: {OTHER_SHA}\n  prism_sync_drift"))

    def test_sync_pin_required(self):
        with self.assertRaises(release_ci.UsageError):
            release_ci.sync_pins("name: x\nversion: 1.0.0+1\n")

    def test_pins_read_from_real_pubspec(self):
        pins = release_ci.sync_pins(PUBSPEC.format(ref=SHA))
        self.assertEqual(len(pins), 3)
        self.assertEqual(set(pins.values()), {SHA})


class PreflightTest(ReleaseTestCase):
    def test_expected_revision_must_be_full_sha(self):
        os.environ["PRISM_EXPECTED_REVISION"] = "abc1234"
        with self.assertRaises(release_ci.UsageError):
            release_ci.assert_expected_revision()

    def test_revision_mismatch_fails(self):
        self.commands.handlers.clear()
        self.stub_git(head=OTHER_SHA)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_expected_revision()
        self.assertIn(OTHER_SHA, str(caught.exception))

    def test_dirty_checkout_fails(self):
        self.commands.handlers.clear()
        self.stub_git(status=" M pubspec.yaml\n")
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.assert_clean_checkout()

    def test_local_override_fails(self):
        (self.repo / "packages" / "x").mkdir(parents=True)
        (self.repo / "packages" / "x" / "pubspec_overrides.yaml").write_text("dependency_overrides: {}\n")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_no_local_overrides()
        self.assertIn("pubspec_overrides.yaml", str(caught.exception))

    def test_local_sdk_path_fails(self):
        (self.repo / "android" / "local.properties").write_text("sdk.dir=/Users/someone/Android\n")
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.assert_no_local_overrides()

    def test_preflight_freezes_metadata_without_touching_secrets(self):
        release_ci.preflight("android")
        frozen = json.loads((self.runner_temp / "prism-release" / "frozen-metadata.json").read_text())
        self.assertEqual(frozen["version"]["pubspec"], "0.16.0+16004")
        self.assertEqual(frozen["source"]["revision"], SHA)
        self.assertEqual(set(frozen["source"]["sync_pins"].values()), {SHA})
        self.assertNotIn("beta-token", json.dumps(frozen))


class CredentialTest(ReleaseTestCase):
    def test_missing_credentials_named_before_compilation(self):
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.require_credentials("android")
        message = str(caught.exception)
        self.assertIn("ANDROID_UPLOAD_KEYSTORE_BASE64", message)
        self.assertIn("PRISM_BETA_REGISTRATION_TOKEN", message)
        self.assertIn("No compilation was started", message)

    def test_unsigned_ipa_requires_no_credentials(self):
        self.assertEqual(release_ci.require_credentials("ios-unsigned"), [])
        self.assertIsNone(release_ci.beta_token("ios-unsigned"))

    def test_unsigned_ipa_rejects_a_beta_token(self):
        os.environ["PRISM_BETA_REGISTRATION_TOKEN"] = "leak"
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.require_credentials("ios-unsigned")
        self.assertIn("PRISM_BETA_REGISTRATION_TOKEN", str(caught.exception))

    def test_android_rejects_play_service_account(self):
        for name in release_ci.PLATFORM_SECRETS["android"]:
            os.environ[name] = "value"
        os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"] = "{}"
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.require_credentials("android")
        self.assertIn("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", str(caught.exception))

    def test_credential_errors_are_redacted(self):
        os.environ["ANDROID_UPLOAD_KEYSTORE_BASE64"] = "not base64!!"
        release_ci.register_secret("not base64!!", mask=True)
        with self.assertRaises(release_ci.UsageError):
            release_ci.decode_base64_secret(
                "ANDROID_UPLOAD_KEYSTORE_BASE64", self.runner_temp / "k.jks", release_ci.Owned()
            )
        self.assertIn("***", release_ci.redact("value not base64!! here"))

    def test_build_refuses_to_run_outside_github_actions(self):
        os.environ["GITHUB_ACTIONS"] = "false"
        with self.assertRaises(release_ci.UsageError):
            release_ci.build("android")
        self.assertFalse((self.runner_temp / "prism-release").exists())
        self.assertEqual(self.commands.calls_with("flutter", "build"), [])

    def test_main_reports_usage_exit_code(self):
        os.environ["GITHUB_ACTIONS"] = "false"
        self.assertEqual(release_ci.main(["build", "--platform", "android"]), 2)


class DartDefineTest(ReleaseTestCase):
    def test_defines_file_is_private_and_omits_token_when_absent(self):
        owned = release_ci.Owned()
        metadata = {
            "version": {"pubspec": "0.16.0+16004", "name": "0.16.0", "build": "16004"},
            "source": {"revision": SHA, "describe": "v0.16.0", "branch": "main"},
        }
        path = release_ci.write_dart_defines(owned, metadata, None)
        payload = json.loads(path.read_text())
        self.assertNotIn("PRISM_BETA_REGISTRATION_TOKEN", payload)
        self.assertEqual(payload["APP_VERSION"], "0.16.0+16004")
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")

    def test_token_is_never_on_a_command_line(self):
        owned = release_ci.Owned()
        metadata = {
            "version": {"pubspec": "0.16.0+16004", "name": "0.16.0", "build": "16004"},
            "source": {"revision": SHA, "describe": "v0.16.0", "branch": "main"},
        }
        release_ci.write_dart_defines(owned, metadata, "super-secret-token")
        self.assertEqual(self.commands.calls, [])
        self.assertIn("super-secret-token", (self.runner_temp / "prism-release" / "dart-defines.json").read_text())


class JavaPropertyTest(ReleaseTestCase):
    def test_escapes_properties_metacharacters(self):
        escaped = release_ci.escape_java_property(r"pa\ss:wo=rd#1")
        self.assertEqual(escaped, r"pa\\ss\:wo\=rd\#1")

    def test_escapes_newlines_and_leading_space(self):
        self.assertEqual(release_ci.escape_java_property("a\nb"), "a\\nb")
        self.assertEqual(release_ci.escape_java_property(" x"), "\\ x")

    def test_key_properties_shape(self):
        text = release_ci.key_properties_text(Path("/tmp/k.jks"), "store:pass", "key=pass", "upload")
        self.assertEqual(
            text.splitlines(),
            [
                "storePassword=store\\:pass",
                "keyPassword=key\\=pass",
                "keyAlias=upload",
                "storeFile=/tmp/k.jks",
            ],
        )


class AndroidSigningTest(ReleaseTestCase):
    def setUp(self):
        super().setUp()
        self.aab = self.repo / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
        self.aab.parent.mkdir(parents=True)
        self.aab.write_bytes(b"bundle")
        self.keystore = self.runner_temp / "upload-keystore.jks"
        self.keystore.write_bytes(b"keystore")

    def test_fingerprint_parsing(self):
        text = f"Owner: CN=Prism\nCertificate fingerprint (SHA256): {fingerprint(CERT_A)}\n"
        self.assertEqual(release_ci.certificate_sha256(text, "test"), CERT_A)

    def test_missing_fingerprint_fails(self):
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.certificate_sha256("no fingerprint here", "test")

    def test_signer_must_match_upload_certificate(self):
        self.stub_android_build(artifact_cert=CERT_B, keystore_cert=CERT_A)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_aab_signer(self.aab, self.keystore, "upload", "store-pass")
        self.assertIn("debug-key fallback", str(caught.exception))

    def test_signer_match_is_accepted(self):
        self.stub_android_build(artifact_cert=CERT_A, keystore_cert=CERT_A)
        self.assertEqual(
            release_ci.assert_aab_signer(self.aab, self.keystore, "upload", "store-pass"), CERT_A
        )

    def test_keystore_password_never_appears_in_argv(self):
        self.stub_android_build()
        release_ci.assert_aab_signer(self.aab, self.keystore, "upload", "store-pass")
        listing = self.commands.calls_with("keytool", "-list")
        self.assertTrue(listing)
        self.assertEqual(listing[0][-2:], ["-storepass:env", "PRISM_CI_KEYSTORE_STORE_PASSWORD"])
        self.assertNotIn("store-pass", json.dumps(listing))

    def test_missing_abi_fails(self):
        self.stub_android_build(abis=["arm64-v8a", "x86_64"])
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.aab_abis(self.aab)
        self.assertIn("armeabi-v7a", str(caught.exception))


class AndroidBuildTest(ReleaseTestCase):
    def setUp(self):
        super().setUp()
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore-bytes").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()

    def test_build_writes_only_dist_android_outputs(self):
        self.assertEqual(release_ci.build("android"), 0)
        dist = self.repo / "dist" / "android"
        self.assertEqual(
            sorted(path.name for path in dist.iterdir()),
            [
                "Prism-0.16.0+16004-android-symbols.tar.gz.age",
                "Prism-0.16.0+16004-android-symbols.tar.gz.age.sha256",
                "Prism-0.16.0+16004-android.aab",
                "Prism-0.16.0+16004-android.aab.sha256",
                "release-receipt.json",
            ],
        )
        checksum = (dist / "Prism-0.16.0+16004-android.aab.sha256").read_text()
        self.assertIn("Prism-0.16.0+16004-android.aab", checksum)
        self.assertEqual((dist / "Prism-0.16.0+16004-android.aab").read_bytes(), b"signed bundle bytes")

    def test_receipt_is_public_safe_and_complete(self):
        release_ci.build("android")
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        text = json.dumps(receipt)
        for secret in ("beta-token-value", "store-pass", "key-pass", "keystore-bytes"):
            self.assertNotIn(secret, text)
        self.assertEqual(receipt["schema"], "prism.release-receipt/v1")
        self.assertEqual(receipt["version"]["pubspec"], "0.16.0+16004")
        self.assertEqual(receipt["source"]["revision"], SHA)
        self.assertEqual(receipt["signing"]["signer_sha256"], CERT_A)
        self.assertEqual(receipt["signing"]["abis"], ["arm64-v8a", "armeabi-v7a", "x86_64"])
        self.assertEqual(receipt["publication"]["store_upload"], False)
        self.assertEqual(receipt["publication"]["github_asset_attach"], False)
        self.assertEqual(len(receipt["artifacts"]), 2)
        self.assertEqual(receipt["artifacts"][0]["sha256"], release_ci.sha256_file(
            self.repo / "dist" / "android" / "Prism-0.16.0+16004-android.aab"
        ))

    def test_symbols_stay_out_of_public_dist(self):
        release_ci.build("android")
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        self.assertTrue(receipt["symbols"])
        self.assertFalse(any(path.suffix == ".symbols" for path in (self.repo / "dist").rglob("*")))
        self.assertFalse(any(path.name == "mapping.txt" for path in (self.repo / "dist").rglob("*")))

    def test_symbols_are_staged_under_one_root_with_kinds(self):
        release_ci.build("android")
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        kinds = {entry["kind"] for entry in receipt["symbols"]}
        self.assertEqual(kinds, {"dart-symbols", "r8-mapping"})
        for entry in receipt["symbols"]:
            self.assertNotIn("/", entry["path"][:1])
            self.assertFalse(Path(entry["path"]).is_absolute())

    def test_symbol_durability_is_marked_pending_not_claimed(self):
        release_ci.build("android")
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        archive = receipt["symbols_archive"]
        self.assertTrue(archive["encrypted"])
        self.assertFalse(archive["durable"])
        self.assertFalse(archive["plaintext_in_dist"])
        self.assertTrue(archive["plaintext_removed"])
        self.assertEqual(archive["recipient"], self.recipient)

    def test_missing_r8_mapping_is_warned_not_silently_ignored(self):
        self.commands.remove(["flutter", "build", "appbundle"])

        def build_without_mapping(argv, env):
            bundle_dir = self.repo / "build" / "app" / "outputs" / "bundle" / "release"
            bundle_dir.mkdir(parents=True, exist_ok=True)
            (bundle_dir / "app-release.aab").write_bytes(b"bundle")
            symbols = release_ci.symbols_dir("android") / "dart"
            symbols.mkdir(parents=True, exist_ok=True)
            (symbols / "app.android-arm64.symbols").write_text("symbols")
            return 0, "", ""

        self.commands.on_prefix(["flutter", "build", "appbundle"], respond=build_without_mapping)
        release_ci.build("android")
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        self.assertEqual({entry["kind"] for entry in receipt["symbols"]}, {"dart-symbols"})

    def test_build_cleans_key_properties_and_secret_state(self):
        release_ci.build("android")
        self.assertFalse((self.repo / "android" / "app" / "key.properties").exists())
        self.assertFalse((self.runner_temp / "prism-release").exists())

    def test_key_properties_exist_only_during_the_build(self):
        seen = {}

        def observe(argv, env):
            path = self.repo / "android" / "app" / "key.properties"
            seen["during"] = path.read_text() if path.exists() else None
            bundle_dir = self.repo / "build" / "app" / "outputs" / "bundle" / "release"
            bundle_dir.mkdir(parents=True, exist_ok=True)
            (bundle_dir / "app-release.aab").write_bytes(b"bundle")
            symbols = release_ci.symbols_dir("android") / "dart"
            symbols.mkdir(parents=True, exist_ok=True)
            (symbols / "app.android-arm64.symbols").write_text("symbols")
            return 0, "", ""

        self.commands.remove(["flutter", "build", "appbundle"])
        self.commands.on_prefix(["flutter", "build", "appbundle"], respond=observe)
        self.commands.on_prefix(["keytool", "-printcert", "-jarfile"], stdout=fingerprint(CERT_A) + "\n")
        release_ci.build("android")
        self.assertIn("storeFile=", seen["during"])
        self.assertIn("keyAlias=upload", seen["during"])
        self.assertFalse((self.repo / "android" / "app" / "key.properties").exists())

    def test_debug_signed_bundle_fails_the_build_and_writes_no_artifact(self):
        self.commands.remove(["keytool", "-printcert", "-jarfile"])
        self.commands.on_prefix(["keytool", "-printcert", "-jarfile"], stdout=fingerprint(CERT_B) + "\n")
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.build("android")
        self.assertFalse((self.repo / "dist" / "android" / "Prism-0.16.0+16004-android.aab").exists())
        self.assertFalse((self.repo / "android" / "app" / "key.properties").exists())
        self.assertFalse((self.runner_temp / "prism-release").exists())

    def test_dart_defines_reach_flutter_as_a_file_not_a_literal(self):
        release_ci.build("android")
        build_calls = self.commands.calls_with("flutter", "build", "appbundle")
        self.assertEqual(len(build_calls), 1)
        command = build_calls[0]
        self.assertTrue(any(part.startswith("--dart-define-from-file=") for part in command))
        self.assertFalse(any("beta-token-value" in part for part in command))
        self.assertFalse(any(part.startswith("--dart-define=") for part in command))


class IosUnsignedBuildTest(ReleaseTestCase):
    def setUp(self):
        super().setUp()

        def flutter_build(argv, env):
            app = self.repo / "build" / "ios" / "iphoneos" / "Runner.app"
            app.mkdir(parents=True, exist_ok=True)
            (app / "Info.plist").write_text("plist")
            return 0, "", ""

        def package(argv, env):
            artifact = Path(argv[1])
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_bytes(b"unsigned ipa")
            return 0, "", ""

        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.commands.on_prefix(["flutter", "build", "ios"], respond=flutter_build)
        self.commands.on(
            lambda argv: argv[:1] == ["scripts/package_unsigned_ipa.sh"], respond=package
        )
        self.commands.on_prefix(
            ["unzip", "-l"], stdout="   100  Payload/Runner.app/Info.plist\n"
        )

    def test_unsigned_build_has_no_signing_or_token(self):
        observed = {}
        self.commands.remove(["flutter", "build", "ios"])

        def observe(argv, env):
            app = self.repo / "build" / "ios" / "iphoneos" / "Runner.app"
            app.mkdir(parents=True, exist_ok=True)
            (app / "Info.plist").write_text("plist")
            defines_flag = next(part for part in argv if part.startswith("--dart-define-from-file="))
            observed["defines"] = json.loads(Path(defines_flag.split("=", 1)[1]).read_text())
            return 0, "", ""

        self.commands.on_prefix(["flutter", "build", "ios"], respond=observe)
        self.assertEqual(release_ci.build("ios-unsigned"), 0)
        dist = self.repo / "dist" / "ios-unsigned"
        self.assertEqual(
            sorted(path.name for path in dist.iterdir()),
            ["Prism-0.16.0+16004-abc1234-ios-unsigned.ipa", "Prism-0.16.0+16004-abc1234-ios-unsigned.ipa.sha256", "release-receipt.json"],
        )
        receipt = json.loads((dist / "release-receipt.json").read_text())
        self.assertEqual(receipt["signing"]["scheme"], "none")
        self.assertIsNone(receipt["signing"]["identity"])
        self.assertEqual(self.commands.calls_with("security"), [])
        self.assertEqual(self.commands.fastlane_calls(), [])
        command = self.commands.calls_with("flutter", "build", "ios")[0]
        self.assertIn("--no-codesign", command)
        self.assertNotIn("PRISM_BETA_REGISTRATION_TOKEN", observed["defines"])
        self.assertFalse((self.runner_temp / "prism-release").exists())

    def test_ipa_containing_signing_material_fails(self):
        self.commands.handlers = [
            handler
            for handler in self.commands.handlers
            if not (handler[0](["unzip", "-l"]))
        ]
        self.commands.on_prefix(
            ["unzip", "-l"],
            stdout="   100  Payload/Runner.app/embedded.mobileprovision\n",
        )
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("ios-unsigned")
        self.assertIn("signing material", str(caught.exception))


class AppleBuildTest(ReleaseTestCase):
    def test_macos_build_uses_ephemeral_keychain_and_never_logs_secrets(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane_macos)
        self.assertEqual(release_ci.build("macos"), 0)

        receipt = json.loads((self.repo / "dist" / "macos" / "release-receipt.json").read_text())
        self.assertEqual(receipt["signing"]["scheme"], "developer-id")
        self.assertEqual(receipt["signing"]["profile"]["name"], "Prism App Store")
        self.assertEqual(receipt["signing"]["team_id"], "GF2W9X3Y6L")

        imports = self.commands.calls_with("security", "import")
        self.assertEqual(len(imports), 1)
        self.assertNotIn("-A", imports[0])
        self.assertIn("-T", imports[0])

        call = [entry for entry in self.commands.calls if entry["argv"][:1] == ["fastlane"] and entry["argv"][-1:] == ["ci_macos_dmg"]][0]
        env = call["env"]
        self.assertEqual(env["GITHUB_ACTIONS"], "true")
        self.assertTrue(env["PRISM_CI_DART_DEFINES_FILE"].endswith("dart-defines.json"))
        self.assertTrue(env["ASC_KEY_FILEPATH"].endswith("AuthKey.p8"))
        self.assertEqual(env["PRISM_CI_PROFILE_NAME"], "Prism App Store")
        self.assertNotIn("p12-pass", json.dumps(env))
        self.assertEqual(env["PRISM_APPLE_TEAM_ID"], "GF2W9X3Y6L")

    def test_macos_build_removes_keychain_and_profile(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane_macos)
        release_ci.build("macos")
        keychain = self.runner_temp / "prism-release" / "prism-release.keychain-db"
        self.assertFalse(keychain.exists())
        self.assertEqual(list(self.profiles.iterdir()), [])
        deletes = self.commands.calls_with("security", "delete-keychain")
        self.assertEqual(len(deletes), 1)
        restores = [
            call for call in self.commands.calls_with("security", "list-keychains", "-d", "user", "-s")
        ]
        self.assertEqual(restores[0][-1], "/old/login.keychain-db")

    def test_ios_store_build_requires_distribution_credentials(self):
        os.environ["PRISM_BETA_REGISTRATION_TOKEN"] = "beta-token-value"
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.require_credentials("ios-store")
        self.assertIn("IOS_DISTRIBUTION_P12_BASE64", str(caught.exception))
        self.assertIn("IOS_APP_STORE_PROFILE_BASE64", str(caught.exception))

    def test_ios_store_build_writes_receipt_from_signing_facts(self):
        self.stub_apple_credentials("ios-store")
        self.commands.on(
            FASTLANE_LANE("ci_ios_store"), respond=lambda argv, env: self._fastlane_ios(argv, env)
        )
        self.assertEqual(release_ci.build("ios-store"), 0)
        receipt = json.loads((self.repo / "dist" / "ios-store" / "release-receipt.json").read_text())
        self.assertEqual(receipt["signing"]["identity"], "Apple Distribution: Prism Plural")
        self.assertFalse(receipt["signing"]["get_task_allow"])
        self.assertEqual(receipt["publication"]["store_upload"], False)

    def _fastlane_macos(self, argv, env):
        self.write_dsyms("macos")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(
            json.dumps({"scheme": "developer-id", "identity": "Developer ID Application", "notarized": True})
        )
        return 0, "", ""

    def _fastlane_ios(self, argv, env):
        self.write_dsyms("ios-store")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-ios-store.ipa").write_bytes(b"ipa")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(
            json.dumps(
                {
                    "scheme": "app-store-distribution",
                    "identity": "Apple Distribution: Prism Plural",
                    "get_task_allow": False,
                    "verified": "fake",
                }
            )
        )
        return 0, "", ""


class CleanupTest(ReleaseTestCase):
    def test_cleanup_removes_only_owned_paths(self):
        owned = release_ci.Owned()
        secret = self.runner_temp / "prism-release" / "creds" / "upload.jks"
        release_ci.write_secret_file(owned, secret, b"keystore")
        bystander = self.runner_temp / "someone-elses-file"
        bystander.write_text("keep me")
        self.assertEqual(release_ci.cleanup(), 0)
        self.assertFalse(secret.exists())
        self.assertTrue(bystander.exists())
        self.assertFalse((self.runner_temp / "prism-release").exists())

    def test_cleanup_is_idempotent(self):
        release_ci.Owned()
        self.assertEqual(release_ci.cleanup(), 0)
        self.assertEqual(release_ci.cleanup(), 0)

    def test_cleanup_refuses_keychain_outside_github_actions(self):
        owned = release_ci.Owned()
        keychain = self.runner_temp / "prism-release" / "prism-release.keychain-db"
        keychain.write_bytes(b"keychain")
        owned.record_keychain(keychain, ["/old/login.keychain-db"])
        os.environ["GITHUB_ACTIONS"] = "false"
        release_ci.cleanup()
        deletes = self.commands.calls_with("security", "delete-keychain")
        self.assertEqual(deletes, [])

    def test_cleanup_refuses_paths_outside_runner_temp(self):
        owned = release_ci.Owned()
        outside = Path(self.tmp.name) / "outside.txt"
        outside.write_text("keep")
        owned.state["paths"].append(str(outside))
        owned.flush()
        release_ci.cleanup()
        self.assertTrue(outside.exists())

    def test_cleanup_refuses_profiles_outside_the_runner_profile_directory(self):
        owned = release_ci.Owned()
        stray = Path(self.tmp.name) / "stray.mobileprovision"
        stray.write_text("keep")
        owned.state["profiles"].append(str(stray))
        owned.flush()
        release_ci.cleanup()
        self.assertTrue(stray.exists())

    def test_cleanup_removes_installed_profile(self):
        owned = release_ci.Owned()
        profile = self.profiles / "abc.mobileprovision"
        profile.write_text("profile")
        owned.add_profile(profile)
        release_ci.cleanup()
        self.assertFalse(profile.exists())


class ProfileInstallTest(ReleaseTestCase):
    def test_install_profile_records_uuid_path(self):
        self.stub_apple_credentials("macos")
        owned = release_ci.Owned()
        source = self.runner_temp / "prism-release" / "creds" / "developer-id.provisionprofile"
        release_ci.write_secret_file(owned, source, b"profile")
        installed = release_ci.install_profile(owned, source)
        self.assertEqual(installed.name, "11111111-2222-3333-4444-555555555555.mobileprovision")
        self.assertIn(str(installed), owned.state["profiles"])

    def test_install_profile_refuses_to_overwrite_existing_uuid(self):
        self.stub_apple_credentials("macos")
        owned = release_ci.Owned()
        existing = self.profiles / "11111111-2222-3333-4444-555555555555.mobileprovision"
        existing.write_text("someone else's profile")
        source = self.runner_temp / "prism-release" / "creds" / "developer-id.provisionprofile"
        release_ci.write_secret_file(owned, source, b"profile")
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.install_profile(owned, source)

    def test_install_profile_refuses_outside_github_actions(self):
        self.stub_apple_credentials("macos")
        owned = release_ci.Owned()
        source = self.runner_temp / "prism-release" / "creds" / "developer-id.provisionprofile"
        release_ci.write_secret_file(owned, source, b"profile")
        os.environ["GITHUB_ACTIONS"] = "false"
        with self.assertRaises(release_ci.UsageError):
            release_ci.install_profile(owned, source)
        self.assertEqual(list(self.profiles.iterdir()), [])


class EnvironmentTest(ReleaseTestCase):
    def test_child_env_drops_bundler_vars(self):
        os.environ["BUNDLE_GEMFILE"] = "/x/Gemfile"
        os.environ["RUBYOPT"] = "-rbundler"
        env = release_ci.child_env("ios-store", system_first_path=True)
        self.assertNotIn("BUNDLE_GEMFILE", env)
        self.assertNotIn("RUBYOPT", env)
        self.assertTrue(env["PATH"].startswith("/usr/bin:/opt/homebrew/bin:"))

    def test_child_env_drops_every_platform_secret(self):
        secrets = {
            "ANDROID_UPLOAD_KEYSTORE_BASE64": "k",
            "ANDROID_UPLOAD_STORE_PASSWORD": "p",
            "ANDROID_UPLOAD_KEY_PASSWORD": "p",
            "ANDROID_UPLOAD_KEY_ALIAS": "upload",
            "PRISM_BETA_REGISTRATION_TOKEN": "token",
            "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON": "{}",
            "MACOS_DEVELOPER_ID_P12_BASE64": "p12",
            "IOS_DISTRIBUTION_P12_PASSWORD": "pw",
            "ASC_KEY_P8": "p8",
        }
        os.environ.update(secrets)
        for platform in release_ci.PLATFORMS:
            env = release_ci.child_env(platform)
            for name in (*release_ci.PLATFORM_SECRETS[platform], *release_ci.FORBIDDEN_ENV[platform]):
                self.assertNotIn(name, env, f"{platform} child env kept {name}")
        # The nonsecret recipient still reaches none of the children either.
        self.assertNotIn("PRISM_RELEASE_SYMBOLS_RECIPIENT", release_ci.child_env("android"))

    def test_receipt_notes_are_public_safe(self):
        for notes in release_ci.RECEIPT_NOTES.values():
            self.assertTrue(notes)

    def test_sha256_matches_hashlib(self):
        path = self.runner_temp / "artifact.bin"
        path.write_bytes(b"payload")
        self.assertEqual(
            release_ci.sha256_file(path),
            "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5",
        )


if __name__ == "__main__":
    unittest.main()


class MaskingTest(ReleaseTestCase):
    def test_beta_token_and_derived_forms_are_masked(self):
        owned = release_ci.Owned()
        metadata = {
            "version": {"pubspec": "0.16.0+16004", "name": "0.16.0", "build": "16004"},
            "source": {"revision": SHA, "describe": "v0.16.0", "branch": "main"},
        }
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            release_ci.write_dart_defines(owned, metadata, "beta-token-value")
        printed = buffer.getvalue()
        self.assertIn("::add-mask::beta-token-value", printed)
        derived = base64.b64encode(b"PRISM_BETA_REGISTRATION_TOKEN=beta-token-value").decode()
        self.assertIn(f"::add-mask::{derived}", printed)

    def test_no_masks_outside_github_actions(self):
        os.environ["GITHUB_ACTIONS"] = "false"
        owned = release_ci.Owned()
        metadata = {
            "version": {"pubspec": "0.16.0+16004", "name": "0.16.0", "build": "16004"},
            "source": {"revision": SHA, "describe": "v0.16.0", "branch": "main"},
        }
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            release_ci.write_dart_defines(owned, metadata, "beta-token-value")
        self.assertNotIn("::add-mask::", buffer.getvalue())

    def test_redaction_covers_registered_values(self):
        release_ci.register_secret("hunter2")
        self.assertEqual(release_ci.redact("token=hunter2"), "token=***")


class LeftoverMaterialTest(ReleaseTestCase):
    def test_key_properties_leftover_is_detected(self):
        (self.repo / "android" / "app" / "key.properties").write_text("storePassword=x\n")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_no_signing_material_in_tree()
        self.assertIn("key.properties", str(caught.exception))

    def test_credential_file_leftover_is_detected(self):
        (self.repo / "upload.p12").write_bytes(b"p12")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_no_signing_material_in_tree()
        self.assertIn("upload.p12", str(caught.exception))

    def test_clean_tree_passes(self):
        self.assertIsNone(release_ci.assert_no_signing_material_in_tree())


class FailureContainmentTest(ReleaseTestCase):
    def test_failed_build_removes_partial_dist(self):
        self.stub_apple_credentials("macos")

        def failing_fastlane(argv, env):
            self.write_dsyms("macos")
            artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
            (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"partial")
            return 1, "", "notarization failed"

        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=failing_fastlane)
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.build("macos")
        self.assertFalse((self.repo / "dist" / "macos").exists())
        self.assertFalse((self.runner_temp / "prism-release").exists())

    def test_missing_signing_facts_fails_the_build(self):
        self.stub_apple_credentials("macos")

        def no_facts(argv, env):
            self.write_dsyms("macos")
            artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
            (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
            return 0, "", ""

        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=no_facts)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("macos")
        self.assertIn("signing facts", str(caught.exception))
        self.assertFalse((self.repo / "dist" / "macos").exists())

    def test_two_artifacts_fail_the_build(self):
        self.stub_apple_credentials("macos")

        def two_artifacts(argv, env):
            self.write_dsyms("macos")
            artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
            (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"a")
            (artifact_dir / "Prism-0.16.0+16004-macos-copy.dmg").write_bytes(b"b")
            (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text("{}")
            return 0, "", ""

        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=two_artifacts)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("macos")
        self.assertIn("exactly one", str(caught.exception))

    def test_dirty_tracked_source_after_build_fails_and_discards_artifacts(self):
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()
        self.commands.remove(["git", "status", "--porcelain", "--untracked-files=all"])
        self.commands.remove(["git", "status", "--porcelain", "--untracked-files=no"])
        self.stub_git(tracked_status=" M pubspec.yaml\n")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("android")
        self.assertIn("tracked source", str(caught.exception))
        self.assertFalse((self.repo / "dist" / "android").exists())


FASTFILE = Path(__file__).resolve().parents[2] / "fastlane" / "Fastfile"
CI_SIGNING = Path(__file__).resolve().parents[2] / "fastlane" / "ci_signing.rb"


def lane_body(lane_name: str) -> str:
    source = FASTFILE.read_text()
    start = source.index(f"lane :{lane_name} do")
    end = source.index("\n  end\n", start)
    return source[start:end]


class FastfileContractTest(unittest.TestCase):
    """The hosted lanes must stay build-only and must not fork the audited helpers."""

    def test_hosted_lanes_exist(self):
        self.assertIn("lane :ci_ios_store do", FASTFILE.read_text())
        self.assertIn("lane :ci_macos_dmg do", FASTFILE.read_text())

    def test_hosted_lanes_never_upload(self):
        forbidden = [
            "upload_to_testflight",
            "upload_to_play_store",
            "github_release_upload",
            "gh release",
            "deliver(",
            "supply(",
        ]
        for name in ("ci_ios_store", "ci_macos_dmg"):
            body = lane_body(name)
            for call in forbidden:
                self.assertNotIn(call, body, f"{name} must stay build-only (found {call})")

    def test_existing_lanes_are_untouched(self):
        source = FASTFILE.read_text()
        self.assertEqual(source.count("lane :beta do"), 3)
        self.assertEqual(source.count("lane :sideload do"), 2)

    def test_ci_lanes_require_github_actions(self):
        for name in ("ci_ios_store", "ci_macos_dmg"):
            self.assertIn('CISigning.require_ci!("', lane_body(name))

    def test_no_automatic_signing_or_provisioning_updates(self):
        for name in ("ci_ios_store", "ci_macos_dmg"):
            body = lane_body(name)
            self.assertNotIn("-allowProvisioningUpdates", body)
            self.assertNotIn("CODE_SIGN_STYLE=Automatic", body)

    def test_audited_helpers_are_reused(self):
        body = lane_body("ci_macos_dmg")
        for helper in ("developer_id_sign_macos_app", "verify_macos_release_app",
                       "developer_id_sign_macos_dmg", "notarize_and_staple",
                       "verify_macos_release_dmg", "create_macos_dmg"):
            self.assertIn(helper, body)
        # No replacement of the audited signing with a generic re-sign.
        self.assertNotIn("codesign --deep", body)

    def test_macos_compiles_without_a_development_identity(self):
        body = lane_body("ci_macos_dmg")
        self.assertIn("XCODE_XCCONFIG_FILE=", body)
        self.assertIn("CODE_SIGNING_ALLOWED = NO", body)
        self.assertIn("CISigning.assert_no_identity_signature!(app_path)", body)
        self.assertIn("compiled_signature = CISigning.assert_no_identity_signature!(app_path)", body)
        self.assertIn('"compiled_signature" => compiled_signature', body)
        self.assertNotIn("compiled_unsigned", body)
        # The xcconfig lives outside the repo so tracked source stays clean.
        self.assertIn("CISigning.state_dir", body)
        self.assertNotIn("build_mac_app", body)

    def test_signing_style_is_manual_and_narrow(self):
        body = lane_body("ci_ios_store")
        self.assertIn("CODE_SIGN_STYLE=Manual", body)
        self.assertIn("PROVISIONING_PROFILE_SPECIFIER", body)
        self.assertIn("single_application!", body)

    def test_every_ci_signing_call_is_defined(self):
        helpers = set(re.findall(r"def (\w+[?!]?)", CI_SIGNING.read_text()))
        used = set(re.findall(r"CISigning\.(\w+[?!]?)", FASTFILE.read_text() + CI_SIGNING.read_text()))
        self.assertEqual(used - helpers, set())


class NdkTest(ReleaseTestCase):
    def setUp(self):
        super().setUp()
        self.flutter_root = Path(self.tmp.name) / "flutter"
        (self.flutter_root / "packages" / "flutter_tools" / "gradle" / "src" / "main" / "kotlin").mkdir(parents=True)
        (self.flutter_root / "packages" / "flutter_tools" / "gradle" / "src" / "main" / "kotlin"
         / "FlutterExtension.kt").write_text(
            'class FlutterExtension {\n  val ndkVersion: String = "28.2.13676358"\n}\n'
        )
        self.commands.remove(["flutter", "--version"])
        self.commands.on_prefix(
            ["flutter", "--version", "--machine"],
            stdout=json.dumps({"flutterRoot": str(self.flutter_root), "frameworkVersion": "3.44.8"}),
        )
        self.commands.on_prefix(["flutter", "--version"], stdout="Flutter 3.44.8\n")
        self.sdk = Path(self.tmp.name) / "android-sdk"
        (self.sdk / "ndk" / "28.2.13676358").mkdir(parents=True)
        (self.sdk / "ndk" / "27.3.13750724").mkdir(parents=True)
        os.environ["ANDROID_HOME"] = str(self.sdk)
        os.environ["ANDROID_NDK_HOME"] = str(self.sdk / "ndk" / "27.3.13750724")

    def test_declares_the_ndk_flutter_pins(self):
        self.assertEqual(release_ci.flutter_ndk_version(), "28.2.13676358")

    def test_receipt_reports_effective_ndk_not_the_env_var(self):
        facts = release_ci.toolchain("android")
        self.assertEqual(facts["ndk"], "28.2.13676358")
        self.assertEqual(facts["ndk_env"], "27.3.13750724")
        self.assertIn("28.2.13676358", facts["ndk_installed"])

    def test_missing_pinned_ndk_is_reported_with_installed_versions(self):
        shutil.rmtree(self.sdk / "ndk" / "28.2.13676358")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_ndk_available("28.2.13676358")
        self.assertIn("27.3.13750724", str(caught.exception))

    def test_build_fails_before_compiling_when_the_ndk_is_missing(self):
        shutil.rmtree(self.sdk / "ndk" / "28.2.13676358")
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.build("android")
        self.assertEqual(self.commands.calls_with("flutter", "build", "appbundle"), [])
        self.assertFalse((self.repo / "dist" / "android").exists())


# Fastlane actions and Ruby builtins a lane may call without a receiver.
ALLOWED_BARE_CALLS = {"sh", "raise", "puts", "loop", "tap", "with_env", "puts"}


def bare_calls(body: str) -> set:
    calls = set()
    for line in body.splitlines():
        match = re.match(r"\s{4}([a-z_][A-Za-z0-9_]*[?!]?)(.*)$", line)
        if not match:
            continue
        name, rest = match.group(1), match.group(2)
        if rest.startswith("("):
            calls.add(name)
    return calls


class HelperResolutionTest(unittest.TestCase):
    def test_hosted_lanes_only_call_defined_helpers(self):
        defined = set(re.findall(r"^def (\w+[?!]?)", FASTFILE.read_text(), re.MULTILINE))
        defined |= set(re.findall(r"  def (\w+[?!]?)", CI_SIGNING.read_text()))
        for name in ("ci_ios_store", "ci_macos_dmg"):
            unknown = bare_calls(lane_body(name)) - defined - ALLOWED_BARE_CALLS
            self.assertEqual(unknown, set(), f"{name} calls undefined helpers: {sorted(unknown)}")

    def test_the_check_would_catch_a_typo(self):
        body = lane_body("ci_macos_dmg").replace("notarize_and_staple(", "notarize_and_stapl(")
        defined = set(re.findall(r"^def (\w+[?!]?)", FASTFILE.read_text(), re.MULTILINE))
        self.assertIn("notarize_and_stapl", bare_calls(body) - defined)


class ToolRequirementTest(ReleaseTestCase):
    def test_missing_tool_fails_before_compilation(self):
        release_ci.shutil.which = lambda name: None if name == "fastlane" else f"/fake/bin/{name}"
        os.environ.update(
            {
                "MACOS_DEVELOPER_ID_P12_BASE64": base64.b64encode(b"p12").decode(),
                "MACOS_DEVELOPER_ID_P12_PASSWORD": "p12-pass",
                "MACOS_DEVELOPER_ID_PROFILE_BASE64": base64.b64encode(b"profile").decode(),
                "ASC_KEY_ID": "k",
                "ASC_ISSUER_ID": "i",
                "ASC_KEY_P8": "p8",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.build("macos")
        self.assertIn("fastlane", str(caught.exception))
        self.assertIn("No compilation was started", str(caught.exception))
        self.assertEqual(self.commands.calls_for_lane("ci_macos_dmg"), [])
        self.assertFalse((self.repo / "dist" / "macos").exists())

    def test_every_platform_declares_its_tools(self):
        for platform in release_ci.PLATFORMS:
            self.assertTrue(release_ci.PLATFORM_TOOLS[platform])
            self.assertIn("flutter", release_ci.PLATFORM_TOOLS[platform])


class BetaTokenScopeTest(ReleaseTestCase):
    """The macOS DMG keeps the existing sideload behaviour: no beta token."""

    def test_macos_does_not_require_the_beta_token(self):
        for name in ("MACOS_DEVELOPER_ID_P12_BASE64", "MACOS_DEVELOPER_ID_P12_PASSWORD",
                     "MACOS_DEVELOPER_ID_PROFILE_BASE64", "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"):
            os.environ[name] = "value"
        self.assertEqual(
            release_ci.require_credentials("macos"), list(release_ci.PLATFORM_SECRETS["macos"])
        )
        self.assertNotIn("PRISM_BETA_REGISTRATION_TOKEN", release_ci.PLATFORM_SECRETS["macos"])

    def test_macos_rejects_the_beta_token(self):
        os.environ["PRISM_BETA_REGISTRATION_TOKEN"] = "leak"
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.require_credentials("macos")
        self.assertIn("PRISM_BETA_REGISTRATION_TOKEN", str(caught.exception))

    def test_beta_token_is_only_requested_where_it_is_embedded(self):
        self.assertEqual(release_ci.BETA_DEFINE_PLATFORMS, ("android", "ios-store"))
        self.assertIsNone(release_ci.beta_token("macos"))
        self.assertIsNone(release_ci.beta_token("ios-unsigned"))
        os.environ["PRISM_BETA_REGISTRATION_TOKEN"] = "beta-token-value"
        self.assertEqual(release_ci.beta_token("android"), "beta-token-value")
        self.assertEqual(release_ci.beta_token("ios-store"), "beta-token-value")

    def test_macos_defines_carry_build_metadata_only(self):
        owned = release_ci.Owned()
        metadata = {
            "version": {"pubspec": "0.16.0+16004", "name": "0.16.0", "build": "16004"},
            "source": {"revision": SHA, "describe": "v0.16.0", "branch": "main"},
        }
        defines = release_ci.write_dart_defines(owned, metadata, release_ci.beta_token("macos"))
        payload = json.loads(defines.read_text())
        self.assertEqual(
            sorted(payload), ["APP_VERSION", "BUILT_AT", "GIT_BRANCH", "GIT_DESCRIBE", "GIT_REV"]
        )

    def test_macos_build_runs_without_a_token_in_the_lane_environment(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane_macos)
        self.assertEqual(release_ci.build("macos"), 0)
        call = [entry for entry in self.commands.calls if entry["argv"][:1] == ["fastlane"] and entry["argv"][-1:] == ["ci_macos_dmg"]][0]
        self.assertNotIn("PRISM_BETA_REGISTRATION_TOKEN", call["env"])
        defines = json.loads(Path(call["env"]["PRISM_CI_DART_DEFINES_FILE"]).read_text()) if Path(
            call["env"]["PRISM_CI_DART_DEFINES_FILE"]
        ).exists() else None
        self.assertIsNone(defines)  # removed by cleanup after the build

    def _fastlane_macos(self, argv, env):
        self.write_dsyms("macos")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(
            json.dumps({"scheme": "developer-id", "identity": "Developer ID Application"})
        )
        return 0, "", ""


def write_package_config(repo: Path, shas: dict) -> None:
    packages = [
        {"name": "prism_plurality", "rootUri": "../", "packageUri": "lib/"},
    ]
    for name, sha in shas.items():
        packages.append(
            {
                "name": name,
                "rootUri": f"file:///home/runner/.pub-cache/git/{name}-{sha}/dart/packages/{name}",
                "packageUri": "lib/",
            }
        )
    target = repo / ".dart_tool"
    target.mkdir(parents=True, exist_ok=True)
    (target / "package_config.json").write_text(json.dumps({"configVersion": 2, "packages": packages}))


class ResolvedPinTest(ReleaseTestCase):
    def test_resolved_checkouts_match_the_pins(self):
        write_package_config(self.repo, {name: SHA for name in release_ci.SYNC_PACKAGES})
        resolved = release_ci.assert_resolved_sync_pins(release_ci.sync_pins(PUBSPEC.format(ref=SHA)))
        self.assertEqual(resolved, {name: SHA for name in release_ci.SYNC_PACKAGES})

    def test_resolved_checkout_mismatch_fails(self):
        pins = {name: SHA for name in release_ci.SYNC_PACKAGES}
        pins["prism_sync"] = OTHER_SHA
        write_package_config(self.repo, pins)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_resolved_sync_pins(release_ci.sync_pins(PUBSPEC.format(ref=SHA)))
        message = str(caught.exception)
        self.assertIn("prism_sync", message)
        self.assertIn(SHA[:12], message)
        self.assertIn(OTHER_SHA[:12], message)

    def test_missing_pinned_checkout_fails(self):
        write_package_config(self.repo, {"prism_sync": SHA})
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_resolved_sync_pins(release_ci.sync_pins(PUBSPEC.format(ref=SHA)))
        self.assertIn("prism_sync_drift", str(caught.exception))

    def test_local_path_checkout_is_refused(self):
        target = self.repo / ".dart_tool"
        target.mkdir(parents=True, exist_ok=True)
        (target / "package_config.json").write_text(
            json.dumps(
                {
                    "configVersion": 2,
                    "packages": [
                        {"name": "prism_sync", "rootUri": "file:///Users/someone/prism-sync/dart/packages/prism_sync"}
                    ],
                }
            )
        )
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.resolved_sync_pins()
        self.assertIn("no commit SHA", str(caught.exception))

    def test_missing_package_config_fails(self):
        (self.repo / ".dart_tool" / "package_config.json").unlink()
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.resolved_sync_pins()

    def test_build_records_resolved_pins_and_fails_on_mismatch(self):
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()

        def pub_get(argv, env):
            write_package_config(self.repo, {name: OTHER_SHA for name in release_ci.SYNC_PACKAGES})
            return 0, "", ""

        self.commands.remove(["flutter", "pub", "get"])
        self.commands.on_prefix(["flutter", "pub", "get"], respond=pub_get)
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.build("android")
        self.assertEqual(self.commands.calls_with("flutter", "build", "appbundle"), [])
        self.assertFalse((self.repo / "dist" / "android").exists())

    def test_receipt_records_resolved_pins(self):
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()
        write_package_config(self.repo, {name: SHA for name in release_ci.SYNC_PACKAGES})
        self.assertEqual(release_ci.build("android"), 0)
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        self.assertEqual(
            receipt["source"]["resolved_sync_pins"],
            {name: SHA for name in release_ci.SYNC_PACKAGES},
        )
        frozen = json.loads((self.runner_temp / "prism-release" / "frozen-metadata.json").read_text()) if (
            self.runner_temp / "prism-release" / "frozen-metadata.json"
        ).exists() else None
        self.assertIsNone(frozen)  # the state directory is cleaned up with the run


class StreamingTest(ReleaseTestCase):
    def test_builds_stream_instead_of_buffering(self):
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()
        write_package_config(self.repo, {name: SHA for name in release_ci.SYNC_PACKAGES})
        release_ci.build("android")
        streams = {
            " ".join(entry["argv"][:3]): entry["stream"] for entry in self.commands.calls
        }
        self.assertTrue(streams["flutter pub get"])
        self.assertTrue(streams["flutter build appbundle"])

    def test_short_tooling_reads_are_not_streamed(self):
        self.commands.on_prefix(["git", "status"], stdout="")
        release_ci.git("status", "--porcelain")
        self.assertFalse(self.commands.calls[-1]["stream"])

    def test_capture_is_bounded(self):
        text = "x" * (release_ci.CAPTURE_LIMIT + 10)
        bounded = release_ci._bounded(text)
        self.assertLess(len(bounded), len(text) + 100)
        self.assertIn("output truncated", bounded)
        self.assertTrue(bounded.startswith("x" * 100))

    def test_streamed_result_keeps_only_a_tail(self):
        result = release_ci.Result(["cmd"], 1, "tail line", "", streamed=True)
        self.assertTrue(result.streamed)
        self.assertEqual(result.text, "tail line")


class ReceiptDefineEvidenceTest(ReleaseTestCase):
    def test_beta_define_evidence_per_platform(self):
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()
        release_ci.build("android")
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        self.assertTrue(receipt["dart_defines"]["includes_beta_registration_token"])
        self.assertNotIn("beta-token-value", json.dumps(receipt))

    def test_macos_receipt_states_no_beta_token(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        release_ci.build("macos")
        receipt = json.loads((self.repo / "dist" / "macos" / "release-receipt.json").read_text())
        self.assertFalse(receipt["dart_defines"]["includes_beta_registration_token"])
        self.assertEqual(
            sorted(receipt["dart_defines"]["keys"]),
            ["APP_VERSION", "BUILT_AT", "GIT_BRANCH", "GIT_DESCRIBE", "GIT_REV"],
        )

    def _fastlane(self, argv, env):
        self.write_dsyms("macos")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(
            json.dumps({"scheme": "developer-id"})
        )
        return 0, "", ""


class StreamingRunnerTest(unittest.TestCase):
    """The real command runner (no fakes): redaction, bounded capture, tails."""

    def setUp(self):
        self.secrets = list(release_ci._SECRETS)
        release_ci._SECRETS.clear()
        self.addCleanup(self._restore)

    def _restore(self):
        release_ci._SECRETS.clear()
        release_ci._SECRETS.extend(self.secrets)

    def test_streamed_output_is_redacted_and_tailed(self):
        release_ci.register_secret("s3cr3t-value")
        result = release_ci.run(
            [sys.executable, "-u", "-c", "print('a s3cr3t-value'); print('b')"],
            stream=True,
            quiet=True,
        )
        self.assertTrue(result.streamed)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("s3cr3t-value", result.text)
        self.assertIn("***", result.text)

    def test_streamed_failure_reports_a_redacted_tail(self):
        release_ci.register_secret("s3cr3t-value")
        with self.assertRaises(release_ci.ToolError) as caught:
            release_ci.run(
                [sys.executable, "-u", "-c", "import sys; print('s3cr3t-value'); sys.exit(4)"],
                stream=True,
                quiet=True,
            )
        self.assertIn("command failed (4)", str(caught.exception))
        self.assertNotIn("s3cr3t-value", str(caught.exception))

    def test_captured_output_is_redacted_and_bounded(self):
        release_ci.register_secret("s3cr3t-value")
        result = release_ci.run(
            [sys.executable, "-c", "print('s3cr3t-value'); print('z' * 50)"],
            capture_limit=20,
            quiet=True,
        )
        self.assertNotIn("s3cr3t-value", result.text)
        self.assertIn("output truncated", result.text)

    def test_missing_program_is_reported_as_a_tool_error(self):
        with self.assertRaises(release_ci.ToolError):
            release_ci.run(["/definitely/not/a/program"], stream=True, quiet=True)


PEM = (
    "-----BEGIN PRIVATE KEY-----\n"
    "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7BODYLINE1\n"
    "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7BODYLINE2\n"
    "-----END PRIVATE KEY-----\n"
)


class MultilineSecretTest(ReleaseTestCase):
    """B1: a multi-line secret must never be emitted as ordinary log output."""

    def test_no_raw_pem_line_is_printed(self):
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            release_ci.register_secret(PEM, mask=True)
        printed = buffer.getvalue().splitlines()
        self.assertTrue(printed)
        for line in printed:
            self.assertTrue(line.startswith("::add-mask::"), f"raw output line: {line!r}")
        for body_line in ("MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7BODYLINE1",
                          "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7BODYLINE2"):
            self.assertTrue(
                any(f"::add-mask::{body_line}" == line for line in printed),
                "every PEM body line must carry its own mask command",
            )
            self.assertFalse(
                any(body_line in line and not line.startswith("::add-mask::") for line in printed)
            )

    def test_workflow_command_values_are_escaped(self):
        self.assertEqual(release_ci.workflow_escape("a%b\r\nc"), "a%25b%0D%0Ac")
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            release_ci.register_secret("secret%value", mask=True)
        self.assertEqual(buffer.getvalue().strip(), "::add-mask::secret%25value")

    def test_redaction_removes_a_standalone_body_line(self):
        release_ci.register_secret(PEM, mask=False)
        body_line = "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7BODYLINE1"
        self.assertEqual(release_ci.redact(f"x {body_line} y"), "x *** y")
        self.assertNotIn("BODYLINE2", release_ci.redact("prefix " + PEM))

    def test_multiline_secret_is_not_printed_when_masking_is_off(self):
        import contextlib
        import io

        os.environ["GITHUB_ACTIONS"] = "false"
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            release_ci.register_secret(PEM, mask=True)
        self.assertEqual(buffer.getvalue(), "")


class LocalCleanupGuardTest(ReleaseTestCase):
    """B2: cleanup must not delete a person's profiles outside GitHub Actions."""

    def test_profiles_survive_cleanup_outside_github_actions(self):
        owned = release_ci.Owned()
        profile = self.profiles / "abc.mobileprovision"
        profile.write_text("someone's profile")
        owned.add_profile(profile)
        os.environ["GITHUB_ACTIONS"] = "false"
        release_ci.cleanup()
        self.assertTrue(profile.exists())

    def test_profiles_are_removed_inside_github_actions(self):
        owned = release_ci.Owned()
        profile = self.profiles / "abc.mobileprovision"
        profile.write_text("run-owned profile")
        owned.add_profile(profile)
        release_ci.cleanup()
        self.assertFalse(profile.exists())

    def test_no_force_local_escape_hatch_exists(self):
        self.assertNotIn("force", release_ci.main.__code__.co_varnames)
        source = open(release_ci.__file__).read()
        self.assertNotIn("--force-local", source)


class SymbolsEncryptionTest(ReleaseTestCase):
    """The final contract: age-encrypted archive per symbol platform."""

    def setUp(self):
        super().setUp()
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()

    def test_recipient_is_required_before_compiling(self):
        del os.environ["PRISM_RELEASE_SYMBOLS_RECIPIENT"]
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.build("android")
        self.assertIn("PRISM_RELEASE_SYMBOLS_RECIPIENT", str(caught.exception))
        self.assertIn("No compilation was started", str(caught.exception))
        self.assertEqual(self.commands.calls_with("flutter", "build", "appbundle"), [])

    def test_empty_recipient_fails_closed(self):
        os.environ["PRISM_RELEASE_SYMBOLS_RECIPIENT"] = ""
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.build("android")
        self.assertIn("PRISM_RELEASE_SYMBOLS_RECIPIENT", str(caught.exception))

    def test_missing_age_fails_before_compiling(self):
        release_ci.shutil.which = lambda name: None if name == "age" else f"/fake/bin/{name}"
        with self.assertRaises(release_ci.UsageError) as caught:
            release_ci.build("android")
        self.assertIn("age", str(caught.exception))
        self.assertEqual(self.commands.calls_with("flutter", "build", "appbundle"), [])

    def test_plugin_and_postquantum_recipients_are_refused(self):
        plugin = "age1" + "y" * 11 + "1" + "qz" * 10
        pq = "age1pq1" + "qz" * 20
        for value in (plugin, pq, "not-a-recipient", "age1" + "qz" * 10):
            with self.assertRaises(release_ci.UsageError) as caught:
                release_ci.validate_age_recipient(value)
            self.assertIn("plain X25519", str(caught.exception))
        self.assertEqual(release_ci.validate_age_recipient(self.recipient), self.recipient)

    def test_encryption_failure_fails_the_build_and_leaves_no_archive(self):
        self.commands.remove(["age", "-R"])
        self.commands.on_prefix(["age", "-R"], code=1, stderr="age: no such recipient")
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.build("android")
        self.assertFalse((self.repo / "dist" / "android").exists())

    def test_dist_allowlist_contains_no_plaintext_symbols(self):
        release_ci.build("android")
        dist = self.repo / "dist" / "android"
        names = {path.name for path in dist.iterdir()}
        self.assertEqual(
            names,
            {
                "Prism-0.16.0+16004-android.aab",
                "Prism-0.16.0+16004-android.aab.sha256",
                "Prism-0.16.0+16004-android-symbols.tar.gz.age",
                "Prism-0.16.0+16004-android-symbols.tar.gz.age.sha256",
                "release-receipt.json",
            },
        )
        for path in (self.repo / "dist").rglob("*"):
            if path.is_file():
                self.assertNotIn(
                    path.suffix,
                    {".symbols", ".dSYM", ".tar", ".gz", ".txt", ".json"} - {".json"},
                    f"plaintext symbol material in dist: {path}",
                )

    def test_plaintext_tarball_and_symbol_tree_are_removed(self):
        release_ci.build("android")
        self.assertEqual(list((self.runner_temp / "prism-release-symbols").glob("**/*.tar.gz")), [])
        self.assertFalse((self.runner_temp / "prism-release-symbols" / "android").exists())
        self.assertFalse((self.runner_temp / "prism-release").exists())

    def test_manifest_inside_the_archive_lists_digests(self):
        release_ci.build("android")
        manifest_path = self.runner_temp / "prism-release-symbols" / "android" / "manifest.json"
        self.assertFalse(manifest_path.exists())  # staging tree is cleaned up
        receipt = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())
        self.assertTrue(receipt["symbols"])
        for entry in receipt["symbols"]:
            self.assertEqual(len(entry["sha256"]), 64)

    def test_receipt_marks_archive_not_durable_and_publication_required(self):
        release_ci.build("android")
        archive = json.loads((self.repo / "dist" / "android" / "release-receipt.json").read_text())[
            "symbols_archive"
        ]
        self.assertFalse(archive["durable"])
        self.assertTrue(archive["publication_required"])
        self.assertEqual(archive["format"], "tar.gz.age")
        self.assertTrue(archive["path"].startswith("dist/android/"))

    def test_unsigned_ipa_is_deferred_and_needs_no_recipient(self):
        del os.environ["PRISM_RELEASE_SYMBOLS_RECIPIENT"]
        del os.environ["PRISM_BETA_REGISTRATION_TOKEN"]
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")

        def build(argv, env):
            app = self.repo / "build" / "ios" / "iphoneos" / "Runner.app"
            app.mkdir(parents=True, exist_ok=True)
            (app / "Info.plist").write_text("plist")
            return 0, "", ""

        def package(argv, env):
            artifact = Path(argv[1])
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_bytes(b"ipa")
            return 0, "", ""

        self.commands.remove(["flutter", "build", "ios"])
        self.commands.on_prefix(["flutter", "build", "ios"], respond=build)
        self.commands.remove(["scripts/package_unsigned_ipa.sh"])
        self.commands.on(
            lambda argv: argv[:1] == ["scripts/package_unsigned_ipa.sh"], respond=package
        )
        self.commands.remove(["unzip", "-l"])
        self.commands.on_prefix(["unzip", "-l"], stdout="Payload/Runner.app/Info.plist\n")
        release_ci.build("ios-unsigned")
        receipt = json.loads((self.repo / "dist" / "ios-unsigned" / "release-receipt.json").read_text())
        self.assertIsNone(receipt["symbols_archive"])
        self.assertEqual(self.commands.calls_with("age"), [])


class AppleSymbolsArchiveTest(ReleaseTestCase):
    def test_macos_build_ships_an_encrypted_dsym_archive(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        self.assertEqual(release_ci.build("macos"), 0)
        dist = self.repo / "dist" / "macos"
        self.assertIn("Prism-0.16.0+16004-macos-symbols.tar.gz.age", {path.name for path in dist.iterdir()})
        receipt = json.loads((dist / "release-receipt.json").read_text())
        self.assertEqual({entry["kind"] for entry in receipt["symbols"]}, {"dSYM"})
        self.assertTrue(receipt["symbols_archive"]["publication_required"])
        self.assertEqual(len(receipt["artifacts"]), 2)

    def test_missing_dsyms_fail_the_build(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._no_dsyms)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("macos")
        self.assertIn("cannot be symbolicated", str(caught.exception))
        self.assertFalse((self.repo / "dist" / "macos").exists())

    def test_ios_store_build_ships_an_encrypted_dsym_archive(self):
        self.stub_apple_credentials("ios-store")
        self.commands.on(FASTLANE_LANE("ci_ios_store"), respond=self._fastlane_ios)
        self.assertEqual(release_ci.build("ios-store"), 0)
        receipt = json.loads((self.repo / "dist" / "ios-store" / "release-receipt.json").read_text())
        self.assertIn("symbols_archive", receipt)
        self.assertEqual(receipt["symbols_archive"]["members"], len(receipt["symbols"]))

    def _fastlane(self, argv, env):
        self.write_dsyms("macos")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(json.dumps({"scheme": "developer-id"}))
        return 0, "", ""

    def _no_dsyms(self, argv, env):
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(json.dumps({"scheme": "developer-id"}))
        return 0, "", ""

    def _fastlane_ios(self, argv, env):
        self.write_dsyms("ios-store")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-ios-store.ipa").write_bytes(b"ipa")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(
            json.dumps({"scheme": "app-store-distribution"})
        )
        return 0, "", ""


class ToolchainProvenanceTest(ReleaseTestCase):
    def test_gem_versions_are_recorded_without_a_lockfile(self):
        facts = release_ci.toolchain("macos")
        self.assertIn("fastlane (2.241.2)", facts["gems"])
        self.assertIn("cocoapods (1.16.2)", facts["gems"])
        self.assertIn("ruby 3.3.0", facts["ruby"])
        self.assertIn("1.16.2", facts["cocoapods"])

    def test_android_records_the_age_version_it_actually_saw(self):
        facts = release_ci.toolchain("android")
        self.assertEqual(facts["age"], "1.3.2")  # the pinned upstream installer on every symbol platform


class BundleIdentifierSourceTest(unittest.TestCase):
    """P4: the Runner bundle id comes from build settings, not pbxproj order."""

    def test_lane_reads_the_release_build_setting(self):
        body = lane_body("ci_ios_store")
        self.assertIn("CISigning.bundle_identifier(", body)
        self.assertIn('scheme: "Runner"', body)
        self.assertNotIn("ios_bundle_identifier", FASTFILE.read_text())
        self.assertIn("def bundle_identifier(", CI_SIGNING.read_text())
        self.assertIn('"PRODUCT_BUNDLE_IDENTIFIER"', CI_SIGNING.read_text())


class ReceiptPrivacyTest(ReleaseTestCase):
    def test_keystore_alias_is_not_in_the_public_receipt(self):
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload-alias-value",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()
        release_ci.build("android")
        receipt = (self.repo / "dist" / "android" / "release-receipt.json").read_text()
        self.assertNotIn("upload-alias-value", receipt)
        self.assertNotIn("keystore_alias", receipt)


class SymbolSourceGuardTest(ReleaseTestCase):
    """B3: nothing that is not a plain file may reach the archive."""

    def setUp(self):
        super().setUp()
        self.symbols = self.runner_temp / "stage"
        self.symbols.mkdir(parents=True)
        (self.symbols / "real.symbols").write_text("symbols")

    def test_symlink_in_the_tree_is_refused(self):
        (self.symbols / "evil-link").symlink_to("/etc/hosts")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_safe_input(self.symbols, label="staged symbols")
        self.assertIn("symlink", str(caught.exception))

    def test_symlinked_root_is_refused(self):
        link = self.runner_temp / "linked-stage"
        link.symlink_to(self.symbols)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_safe_input(link, label="staged symbols")
        self.assertIn("symlinked input", str(caught.exception))

    def test_hardlink_is_refused(self):
        outside = self.runner_temp / "outside-secret.txt"
        outside.write_text("not for publication")
        os.link(outside, self.symbols / "hardlinked.symbols")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_safe_input(self.symbols, label="staged symbols")
        self.assertIn("hardlinked", str(caught.exception))

    def test_special_file_is_refused(self):
        os.mkfifo(self.symbols / "pipe")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.assert_safe_input(self.symbols, label="staged symbols")
        self.assertIn("non-regular", str(caught.exception))

    def test_regular_tree_is_accepted(self):
        (self.symbols / "nested").mkdir()
        (self.symbols / "nested" / "dwarf").write_bytes(b"data")
        self.assertIsNone(release_ci.assert_safe_input(self.symbols, label="staged symbols"))


class SymbolsTarInspectionTest(ReleaseTestCase):
    def setUp(self):
        super().setUp()
        self.root = self.runner_temp / "tar-stage"
        self.root.mkdir(parents=True)
        (self.root / "a.symbols").write_text("aaa")
        (self.root / "b.txt").write_text("bbb")
        self.entries = [
            {"kind": "dart-symbols", "path": "a.symbols", "sha256": release_ci.sha256_file(self.root / "a.symbols"), "bytes": 3},
            {"kind": "r8-mapping", "path": "b.txt", "sha256": release_ci.sha256_file(self.root / "b.txt"), "bytes": 3},
        ]
        (self.root / "manifest.json").write_text(
            json.dumps({"schema": "prism.symbols-manifest/v1", "entries": self.entries})
        )

    def honest_tar(self) -> Path:
        path = self.runner_temp / "honest.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for entry in sorted(self.root.rglob("*")):
                archive.add(entry, arcname="./" + entry.relative_to(self.root).as_posix(), recursive=False)
        return path

    def test_honest_archive_passes(self):
        self.assertIsNone(release_ci.inspect_symbols_tar(self.honest_tar(), self.entries))

    def test_link_member_is_refused(self):
        path = self.runner_temp / "link.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for entry in sorted(self.root.rglob("*")):
                archive.add(entry, arcname="./" + entry.relative_to(self.root).as_posix(), recursive=False)
            link = tarfile.TarInfo("./evil-link")
            link.type = tarfile.SYMTYPE
            link.linkname = "/etc/hosts"
            archive.addfile(link)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.inspect_symbols_tar(path, self.entries)
        self.assertIn("link member", str(caught.exception))

    def test_absolute_member_is_refused(self):
        path = self.runner_temp / "absolute.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for entry in sorted(self.root.rglob("*")):
                archive.add(entry, arcname="./" + entry.relative_to(self.root).as_posix(), recursive=False)
            payload = b"x"
            member = tarfile.TarInfo("/etc/passwd")
            member.size = len(payload)
            import io

            archive.addfile(member, io.BytesIO(payload))
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.inspect_symbols_tar(path, self.entries)
        self.assertIn("escapes the archive root", str(caught.exception))

    def test_dotdot_member_is_refused(self):
        path = self.runner_temp / "dotdot.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            payload = b"x"
            member = tarfile.TarInfo("../escape")
            member.size = len(payload)
            import io

            archive.addfile(member, io.BytesIO(payload))
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.inspect_symbols_tar(path, self.entries)
        self.assertIn("escapes the archive root", str(caught.exception))

    def test_unexpected_member_is_refused(self):
        (self.root / "smuggled.bin").write_bytes(b"extra")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.inspect_symbols_tar(self.honest_tar(), self.entries)
        self.assertIn("unexpected member", str(caught.exception))

    def test_missing_member_is_refused(self):
        path = self.runner_temp / "incomplete.tar.gz"
        with tarfile.open(path, "w:gz") as archive:
            for entry in ("manifest.json", "a.symbols"):
                source = self.root / entry
                archive.add(source, arcname="./" + entry, recursive=False)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.inspect_symbols_tar(path, self.entries)
        self.assertIn("missing staged files", str(caught.exception))

    def test_digest_disagreement_is_refused(self):
        tampered = [dict(entry) for entry in self.entries]
        tampered[0]["sha256"] = "1" * 64
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.inspect_symbols_tar(self.honest_tar(), tampered)
        self.assertIn("staged digest", str(caught.exception))

    def test_manifest_disagreement_is_refused(self):
        (self.root / "manifest.json").write_text(
            json.dumps({"schema": "prism.symbols-manifest/v1", "entries": self.entries[:1]})
        )
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.inspect_symbols_tar(self.honest_tar(), self.entries)
        self.assertIn("manifest inventory disagrees", str(caught.exception))


class RealAgeRoundtripTest(ReleaseTestCase):
    """A real tar+age roundtrip with a throwaway key created in the temp dir.

    The builder module is loaded a second time so this test runs the real
    command runner (real tar, real age) instead of the recorder.
    """

    def setUp(self):
        super().setUp()
        os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + REAL_PATH
        if not (REAL_AGE and REAL_AGE_KEYGEN):
            self.skipTest("age/age-keygen are not available on this machine")
        import importlib.util

        spec = importlib.util.spec_from_file_location("release_ci_real", release_ci.__file__)
        self.real = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.real)
        self.real.REPO_ROOT = Path(self.repo)

        self.identity = self.runner_temp / "scratch-identity.txt"
        result = subprocess.run(
            ["age-keygen", "-o", str(self.identity)], capture_output=True, text=True, check=True
        )
        match = re.search(r"(age1[0-9a-z]+)", result.stderr)
        self.assertTrue(match, "age-keygen did not print a public key")
        self.recipient = match.group(1)
        os.environ["PRISM_RELEASE_SYMBOLS_RECIPIENT"] = self.recipient
        self.metadata = {
            "version": {"pubspec": "0.16.0+16004", "name": "0.16.0", "build": "16004"},
            "source": {"revision": SHA},
        }

    def write_stage(self):
        root = self.real.symbols_dir("android")
        (root / "dart").mkdir(parents=True, exist_ok=True)
        (root / "dart" / "app.android-arm64.symbols").write_text("symbols-bytes")
        (root / "r8").mkdir(parents=True, exist_ok=True)
        (root / "r8" / "mapping.txt").write_text("mapping-bytes")
        entries = []
        for path in sorted(root.rglob("*")):
            if path.is_file():
                entries.append(
                    {
                        "kind": "dart-symbols" if path.suffix == ".symbols" else "r8-mapping",
                        "path": path.relative_to(root).as_posix(),
                        "sha256": release_ci.sha256_file(path),
                        "bytes": path.stat().st_size,
                    }
                )
        return root, entries

    def test_archive_encrypts_and_contains_only_regular_members(self):
        root, entries = self.write_stage()
        outcome = self.real.encrypt_symbols_archive(
            self.real.Owned(), "android", self.metadata, {"root": root, "entries": entries}
        )
        archive = Path(self.repo) / "dist" / "android" / "Prism-0.16.0+16004-android-symbols.tar.gz.age"
        self.assertTrue(archive.is_file(), "archive was not written")
        self.assertEqual(outcome["recipient"], self.recipient)
        self.assertTrue(outcome["plaintext_removed"])
        self.assertFalse((self.runner_temp / "prism-release" / "android-symbols.tar.gz").exists())
        self.assertNotIn(b"symbols-bytes", archive.read_bytes())

        plaintext = self.runner_temp / "decrypted.tar.gz"
        subprocess.run(
            ["age", "-d", "-i", str(self.identity), "-o", str(plaintext), str(archive)],
            capture_output=True,
            check=True,
        )
        with tarfile.open(plaintext, "r:gz") as tar:
            members = tar.getmembers()
            self.assertFalse([member for member in members if member.issym() or member.islnk()])
            names = {member.name for member in members}
            self.assertIn("./manifest.json", names)
            self.assertIn("./dart/app.android-arm64.symbols", names)
            manifest = json.loads(tar.extractfile("./manifest.json").read().decode())
            self.assertEqual({entry["path"] for entry in manifest["entries"]}, {e["path"] for e in entries})
            self.assertEqual(
                {member.name for member in members if member.isfile()},
                {"./manifest.json"} | {"./" + entry["path"] for entry in entries},
            )

    def test_real_encryption_refuses_a_symlinked_tree(self):
        root, entries = self.write_stage()
        (root / "dart" / "evil-link").symlink_to("/etc/hosts")
        with self.assertRaises(self.real.ReleaseError) as caught:
            self.real.encrypt_symbols_archive(
                self.real.Owned(), "android", self.metadata, {"root": root, "entries": entries}
            )
        self.assertIn("symlink", str(caught.exception))
        self.assertFalse((Path(self.repo) / "dist" / "android").exists())


class PlaintextRemovalTest(ReleaseTestCase):
    def test_unlink_failure_is_fatal(self):
        directory = self.runner_temp / "readonly"
        directory.mkdir()
        target = directory / "plaintext.tar.gz"
        target.write_bytes(b"x")
        os.chmod(directory, 0o500)
        try:
            with self.assertRaises(release_ci.ReleaseError) as caught:
                release_ci.unlink_or_fail(target)
            self.assertIn("plaintext", str(caught.exception))
        finally:
            os.chmod(directory, 0o700)

    def test_missing_file_is_not_an_error(self):
        self.assertIsNone(release_ci.unlink_or_fail(self.runner_temp / "absent.tar.gz"))


class FlutterProvenanceTest(ReleaseTestCase):
    def test_machine_provenance_is_recorded(self):
        payload = {
            "frameworkVersion": "3.44.8",
            "frameworkRevision": "f" * 40,
            "engineRevision": "e" * 40,
            "dartSdkVersion": "3.11.1",
            "channel": "stable",
            "repositoryUrl": "https://github.com/flutter/flutter.git",
            "repositoryBranch": "user/local-release",
        }
        self.commands.remove(["flutter", "--version", "--machine"])
        self.commands.on_prefix(["flutter", "--version", "--machine"], stdout=json.dumps(payload))
        provenance = release_ci.flutter_provenance()
        self.assertEqual(provenance["frameworkRevision"], "f" * 40)
        self.assertEqual(provenance["engineRevision"], "e" * 40)
        self.assertEqual(provenance["dartSdkVersion"], "3.11.1")
        self.assertEqual(provenance["repositoryBranch"], "user/local-release")
        facts = release_ci.toolchain("android")
        self.assertEqual(facts["flutter_provenance"]["frameworkRevision"], "f" * 40)

    def test_age_is_recorded_for_every_symbol_platform(self):
        for platform in ("android", "ios-store", "macos"):
            self.assertEqual(release_ci.toolchain(platform).get("age"), "1.3.2", platform)
        self.assertIsNone(release_ci.toolchain("ios-unsigned").get("age"))


class UnsignedIpaConsumerNameTest(ReleaseTestCase):
    """The published unsigned IPA name is a consumer contract (prism-site)."""

    def setUp(self):
        super().setUp()
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")

        def build(argv, env):
            app = self.repo / "build" / "ios" / "iphoneos" / "Runner.app"
            app.mkdir(parents=True, exist_ok=True)
            (app / "Info.plist").write_text("plist")
            return 0, "", ""

        def package(argv, env):
            artifact = Path(argv[1])
            artifact.parent.mkdir(parents=True, exist_ok=True)
            artifact.write_bytes(b"ipa")
            return 0, "", ""

        self.commands.on_prefix(["flutter", "build", "ios"], respond=build)
        self.commands.on(
            lambda argv: argv[:1] == ["scripts/package_unsigned_ipa.sh"], respond=package
        )
        self.commands.on_prefix(["unzip", "-l"], stdout="Payload/Runner.app/Info.plist\n")

    def test_name_matches_the_site_consumer_pattern(self):
        release_ci.build("ios-unsigned")
        names = {path.name for path in (self.repo / "dist" / "ios-unsigned").iterdir()}
        self.assertIn("Prism-0.16.0+16004-abc1234-ios-unsigned.ipa", names)
        # prism-site: Prism-${VERSION}-${IOS_BUILD_HASH}-ios-unsigned.ipa
        receipt = json.loads((self.repo / "dist" / "ios-unsigned" / "release-receipt.json").read_text())
        expected = f"Prism-{receipt['version']['pubspec']}-{receipt['source']['short_revision']}-ios-unsigned.ipa"
        self.assertIn(expected, names)
        self.assertEqual(receipt["source"]["short_revision"], "abc1234")
        self.assertEqual(receipt["artifacts"][0]["name"], expected)

    def test_short_revision_comes_from_git_not_a_fixed_slice(self):
        # A 9-character short revision must survive verbatim.
        self.commands.remove(["git", "rev-parse", "--short", "HEAD"])
        self.commands.on_prefix(["git", "rev-parse", "--short", "HEAD"], stdout="420c760f5\n")
        release_ci.build("ios-unsigned")
        names = {path.name for path in (self.repo / "dist" / "ios-unsigned").iterdir()}
        self.assertIn("Prism-0.16.0+16004-420c760f5-ios-unsigned.ipa", names)

    def test_unexpected_short_revision_is_refused(self):
        self.commands.remove(["git", "rev-parse", "--short", "HEAD"])
        self.commands.on_prefix(["git", "rev-parse", "--short", "HEAD"], stdout="not-a-sha\n")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("ios-unsigned")
        self.assertIn("unexpected short revision", str(caught.exception))
        self.assertFalse((self.repo / "dist" / "ios-unsigned").exists())

    def test_other_artifacts_keep_their_names(self):
        # Only the unsigned sideload IPA carries the hash; nothing else moved.
        source = open(release_ci.__file__).read()
        # Python names only the Android AAB and the unsigned IPA; the Apple
        # artifact names are produced by the frozen Fastfile lanes.
        self.assertIn('-android.aab"', source)
        self.assertIn("-symbols.tar.gz.age", source)


class FastlaneActivationTest(ReleaseTestCase):
    """A plain `fastlane` picks the newest installed gem; the pin must be explicit."""

    def test_command_uses_the_rubygems_underscore_selector(self):
        # macOS names its platform; a bare lane resolves in the iOS namespace.
        self.assertEqual(
            release_ci.fastlane_lane_command("macos"),
            ["fastlane", "_2.239.0_", "mac", "ci_macos_dmg"],
        )
        # iOS is the default platform, so its lane stays bare.
        self.assertEqual(
            release_ci.fastlane_lane_command("ios-store"),
            ["fastlane", "_2.239.0_", "ci_ios_store"],
        )
        self.assertEqual(
            release_ci.fastlane_command("--version"),
            ["fastlane", "_2.239.0_", "--version"],
        )

    def test_version_must_come_from_controlled_configuration(self):
        for platform in ("ios-store", "macos"):
            del os.environ["FASTLANE_VERSION"]
            with self.assertRaises(release_ci.UsageError) as caught:
                release_ci.require_config(platform)
            self.assertIn("FASTLANE_VERSION", str(caught.exception))
            self.assertIn("No compilation was started", str(caught.exception))
            os.environ["FASTLANE_VERSION"] = FASTLANE_PINNED

    def test_empty_version_fails_closed(self):
        os.environ["FASTLANE_VERSION"] = ""
        for platform in ("ios-store", "macos"):
            with self.assertRaises(release_ci.UsageError) as caught:
                release_ci.require_config(platform)
            self.assertIn("FASTLANE_VERSION", str(caught.exception))
        os.environ["FASTLANE_VERSION"] = FASTLANE_PINNED

    def test_version_must_be_a_gem_semver(self):
        for value in ("true", "latest", "2.239", "2", "", "v2.239.0", "2.239.0 latest"):
            os.environ["FASTLANE_VERSION"] = value
            with self.assertRaises(release_ci.UsageError, msg=f"{value!r} should be refused"):
                release_ci.fastlane_version()
        for value in ("2.239.0", "2.239.0.pre.1", "2.239.0+meta"):
            os.environ["FASTLANE_VERSION"] = value
            self.assertEqual(release_ci.fastlane_version(), value)
        # Surrounding whitespace is stripped from the environment value.
        os.environ["FASTLANE_VERSION"] = " 2.239.0 "
        self.assertEqual(release_ci.fastlane_version(), "2.239.0")
        os.environ["FASTLANE_VERSION"] = FASTLANE_PINNED

    def test_android_does_not_require_a_fastlane_version(self):
        del os.environ["FASTLANE_VERSION"]
        release_ci.require_config("android")  # no fastlane on this path
        os.environ["FASTLANE_VERSION"] = FASTLANE_PINNED

    def test_provenance_proves_the_pinned_version_actually_ran(self):
        provenance = release_ci.fastlane_provenance()
        self.assertEqual(provenance["pinned"], FASTLANE_PINNED)
        self.assertEqual(provenance["activation"], f"_{FASTLANE_PINNED}_")
        self.assertIn(FASTLANE_PINNED, provenance["reported"])
        self.assertEqual(
            self.commands.calls_with("fastlane", f"_{FASTLANE_PINNED}_", "--version"),
            [["fastlane", f"_{FASTLANE_PINNED}_", "--version"]],
        )

    def test_a_newer_preinstalled_gem_is_detected(self):
        self.commands.remove(["fastlane", "--version"])
        self.commands.on(
            lambda argv: argv[:1] == ["fastlane"] and argv[-1:] == ["--version"],
            lambda argv, env: (0, "fastlane installation at path: /fake/gems\nfastlane 2.241.2\n", ""),
        )
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.fastlane_provenance()
        message = str(caught.exception)
        self.assertIn(FASTLANE_PINNED, message)
        self.assertIn("2.241.2", message)
        self.assertIn("preinstalled gem", message)

    def test_macos_build_invokes_the_pinned_lane(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        self.assertEqual(release_ci.build("macos"), 0)
        calls = self.commands.calls_for_lane("ci_macos_dmg")
        self.assertEqual(
            calls, [["fastlane", f"_{FASTLANE_PINNED}_", "mac", "ci_macos_dmg"]]
        )

    def test_receipt_records_activation_and_reported_version(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        release_ci.build("macos")
        receipt = json.loads((self.repo / "dist" / "macos" / "release-receipt.json").read_text())
        provenance = receipt["toolchain"]["fastlane_provenance"]
        self.assertEqual(provenance["pinned"], FASTLANE_PINNED)
        self.assertEqual(provenance["activation"], f"_{FASTLANE_PINNED}_")
        self.assertIn(FASTLANE_PINNED, receipt["toolchain"]["fastlane"])

    def test_build_fails_before_compiling_without_the_pin(self):
        self.stub_apple_credentials("ios-store")
        del os.environ["FASTLANE_VERSION"]
        with self.assertRaises(release_ci.UsageError):
            release_ci.build("ios-store")
        self.assertEqual(self.commands.fastlane_calls(), [])
        self.assertEqual(self.commands.calls_with("flutter", "pub", "get"), [])
        self.assertFalse((self.repo / "dist" / "ios-store").exists())
        os.environ["FASTLANE_VERSION"] = FASTLANE_PINNED

    def _fastlane(self, argv, env):
        self.write_dsyms("macos")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(json.dumps({"scheme": "developer-id"}))
        return 0, "", ""


class FastlaneVersionLineTest(ReleaseTestCase):
    """Only an exact "fastlane X.Y.Z" line proves the activated gem version."""

    def respond_with(self, text: str) -> None:
        self.commands.remove(["fastlane", "--version"])
        self.commands.on(
            lambda argv: argv[:1] == ["fastlane"] and argv[-1:] == ["--version"],
            lambda argv, env: (0, text, ""),
        )

    def test_banner_and_path_alone_are_not_a_version(self):
        # The parent's exact concern: the banner path contains the pinned
        # version, but that is not a version report.
        self.respond_with(
            "fastlane installation at path:\n"
            "/home/runner/.gem/ruby/3.3.0/gems/fastlane-2.239.0/bin/fastlane\n"
            "-----------------------------\n"
        )
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.fastlane_provenance()
        self.assertIn("printed no exact 'fastlane <version>' line", str(caught.exception))
        self.assertIn("never observed", str(caught.exception))

    def test_exact_line_is_parsed_out_of_the_banner_noise(self):
        self.respond_with(
            "fastlane installation at path:\n"
            "/home/runner/.gem/ruby/3.3.0/gems/fastlane-2.239.0/bin/fastlane\n"
            "-----------------------------\n"
            "[12:00:00]: WARNING: locale is not UTF-8\n"
            "fastlane 2.239.0\n"
            "[12:00:00]: WARNING: locale is not UTF-8\n"
        )
        provenance = release_ci.fastlane_provenance()
        self.assertEqual(provenance["reported"], "2.239.0")
        self.assertEqual(provenance["pinned"], "2.239.0")
        self.assertEqual(provenance["activation"], "_2.239.0_")

    def test_a_different_activated_version_is_refused_even_if_the_path_matches(self):
        # Path says the pinned gem, the running gem says otherwise: refuse.
        self.respond_with(
            "fastlane installation at path:\n"
            "/home/runner/.gem/ruby/3.3.0/gems/fastlane-2.239.0/bin/fastlane\n"
            "fastlane 2.241.2\n"
        )
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.fastlane_provenance()
        message = str(caught.exception)
        self.assertIn("2.241.2", message)
        self.assertIn("2.239.0", message)
        self.assertIn("preinstalled gem", message)

    def test_the_receipt_never_invents_a_version(self):
        self.respond_with("fastlane installation at path:\n/opt/gems/fastlane-2.239.0/bin/fastlane\n")
        with self.assertRaises(release_ci.ReleaseError):
            release_ci.fastlane_provenance()
        # No provenance is recorded because the build stops before the receipt.
        self.assertFalse((self.repo / "dist" / "macos").exists())

    def test_receipt_reports_the_observed_version(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        release_ci.build("macos")
        receipt = json.loads((self.repo / "dist" / "macos" / "release-receipt.json").read_text())
        provenance = receipt["toolchain"]["fastlane_provenance"]
        self.assertEqual(provenance["reported"], "2.239.0")
        self.assertEqual(receipt["toolchain"]["fastlane"], "fastlane 2.239.0")
        self.assertIn("underscore-selected gem", provenance["verified"])

    def _fastlane(self, argv, env):
        self.write_dsyms("macos")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(json.dumps({"scheme": "developer-id"}))
        return 0, "", ""


class FastlaneProbeOrderingTest(ReleaseTestCase):
    """P2: the pin must be proven before any signed work, and only once."""

    def probe_positions(self) -> list[int]:
        return [
            index
            for index, call in enumerate(self.commands.calls)
            if call["argv"][:1] == ["fastlane"] and call["argv"][-1:] == ["--version"]
        ]

    def first_position(self, predicate) -> int | None:
        for index, call in enumerate(self.commands.calls):
            if predicate(call["argv"]):
                return index
        return None

    def test_probe_runs_before_lane_keychain_and_compile(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        self.assertEqual(release_ci.build("macos"), 0)

        probes = self.probe_positions()
        self.assertEqual(len(probes), 1, "the pin must be probed exactly once")
        probe = probes[0]
        lane = self.first_position(lambda argv: FASTLANE_LANE("ci_macos_dmg")(argv))
        keychain = self.first_position(lambda argv: argv[:2] == ["security", "create-keychain"])
        keychain_import = self.first_position(lambda argv: argv[:2] == ["security", "import"])
        compile_step = self.first_position(lambda argv: argv[:3] == ["flutter", "pub", "get"])
        self.assertIsNotNone(lane)
        for label, position in (("lane", lane), ("keychain", keychain),
                                ("identity import", keychain_import), ("pub get", compile_step)):
            self.assertIsNotNone(position, label)
            self.assertLess(probe, position, f"fastlane probe must precede the {label}")

    def test_receipt_reuses_the_pre_build_observation(self):
        self.stub_apple_credentials("macos")
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        release_ci.build("macos")
        self.assertEqual(len(self.probe_positions()), 1)
        receipt = json.loads((self.repo / "dist" / "macos" / "release-receipt.json").read_text())
        self.assertEqual(receipt["toolchain"]["fastlane_provenance"]["reported"], FASTLANE_PINNED)

    def test_a_wrong_selected_version_fails_before_any_signed_work(self):
        self.stub_apple_credentials("macos")
        self.commands.remove(["fastlane", "--version"])
        self.commands.on(
            lambda argv: argv[:1] == ["fastlane"] and argv[-1:] == ["--version"],
            lambda argv, env: (0, "fastlane installation at path:\n/x/gems/fastlane-2.241.2/bin/fastlane\nfastlane 2.241.2\n", ""),
        )
        self.commands.on(FASTLANE_LANE("ci_macos_dmg"), respond=self._fastlane)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("macos")
        self.assertIn("2.241.2", str(caught.exception))
        # Nothing signed, nothing compiled, nothing left behind.
        self.assertEqual(self.first_position(lambda a: a[:2] == ["security", "create-keychain"]), None)
        self.assertEqual(self.first_position(lambda a: a[:2] == ["security", "import"]), None)
        self.assertEqual(self.commands.calls_for_lane("ci_macos_dmg"), [])
        self.assertEqual(self.commands.calls_with("flutter", "pub", "get"), [])
        self.assertFalse((self.repo / "dist" / "macos").exists())

    def test_android_never_probes_fastlane(self):
        os.environ.update(
            {
                "ANDROID_UPLOAD_KEYSTORE_BASE64": base64.b64encode(b"keystore").decode(),
                "ANDROID_UPLOAD_STORE_PASSWORD": "store-pass",
                "ANDROID_UPLOAD_KEY_PASSWORD": "key-pass",
                "ANDROID_UPLOAD_KEY_ALIAS": "upload",
                "PRISM_BETA_REGISTRATION_TOKEN": "beta-token-value",
            }
        )
        self.commands.on_prefix(["flutter", "pub", "get"], stdout="")
        self.stub_android_build()
        release_ci.build("android")
        self.assertEqual(self.probe_positions(), [])
        self.assertEqual(self.commands.fastlane_calls(), [])

    def _fastlane(self, argv, env):
        self.write_dsyms("macos")
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        (artifact_dir / "Prism-0.16.0+16004-macos.dmg").write_bytes(b"dmg")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(json.dumps({"scheme": "developer-id"}))
        return 0, "", ""


class PodVersionGuardTest(ReleaseTestCase):
    """A CocoaPods version that differs from the lock stamp must fail before compiling."""

    def apple_build(self, platform):
        self.stub_apple_credentials(platform)
        self.commands.on(
            FASTLANE_LANE("ci_macos_dmg" if platform == "macos" else "ci_ios_store"),
            respond=self._fastlane,
        )
        return release_ci.build(platform)

    def _fastlane(self, argv, env):
        platform = "macos" if argv[-1] == "ci_macos_dmg" else "ios-store"
        self.write_dsyms(platform)
        artifact_dir = Path(env["PRISM_CI_ARTIFACT_DIR"])
        suffix = "dmg" if platform == "macos" else "ipa"
        (artifact_dir / f"Prism-0.16.0+16004-{platform}.{suffix}").write_bytes(b"artifact")
        (Path(env["PRISM_CI_STATE_DIR"]) / "signing-facts.json").write_text(json.dumps({"scheme": "test"}))
        return 0, "", ""

    def test_matching_stamp_is_accepted_and_recorded(self):
        self.assertEqual(self.apple_build("macos"), 0)
        receipt = json.loads((self.repo / "dist" / "macos" / "release-receipt.json").read_text())
        self.assertEqual(
            receipt["pods"], {"lock": "macos/Podfile.lock", "stamped": "1.16.2", "installed": "1.16.2"}
        )

    def test_ios_modes_compare_the_ios_lock(self):
        self.assertEqual(self.apple_build("ios-store"), 0)
        receipt = json.loads((self.repo / "dist" / "ios-store" / "release-receipt.json").read_text())
        self.assertEqual(receipt["pods"]["lock"], "ios/Podfile.lock")

    def test_mismatch_fails_before_any_build_work(self):
        self.commands.remove(["pod", "--version"])
        self.commands.on_prefix(["pod", "--version"], stdout="1.17.0\n")
        for platform in ("ios-store", "macos"):
            with self.assertRaises(release_ci.ReleaseError) as caught:
                self.apple_build(platform)
            message = str(caught.exception)
            self.assertIn("1.17.0", message)
            self.assertIn("1.16.2", message)
            self.assertIn("COCOAPODS:", message)
            self.assertIn("No compilation was started", message)
            self.assertIn("tracked-source guard", message)
        self.assertEqual(self.commands.calls_with("flutter", "pub", "get"), [])
        self.assertEqual(self.commands.calls_for_lane("ci_macos_dmg"), [])
        self.assertEqual(self.commands.fastlane_calls(), [])
        self.assertEqual(self.commands.calls_with("security", "create-keychain"), [])
        self.assertFalse((self.repo / "dist").exists())

    def test_ios_unsigned_is_guarded_too(self):
        self.commands.remove(["pod", "--version"])
        self.commands.on_prefix(["pod", "--version"], stdout="1.17.0\n")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("ios-unsigned")
        self.assertIn("ios/Podfile.lock", str(caught.exception))
        self.assertEqual(self.commands.calls_with("flutter", "build"), [])

    def test_missing_lock_is_refused(self):
        (self.repo / "macos" / "Podfile.lock").unlink()
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("macos")
        self.assertIn("macos/Podfile.lock is missing", str(caught.exception))

    def test_lock_without_a_stamp_is_refused(self):
        (self.repo / "macos" / "Podfile.lock").write_text("PODS:\n  - Flutter (1.0.0)\n")
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.build("macos")
        self.assertIn("no COCOAPODS: version stamp", str(caught.exception))

    def test_version_is_parsed_out_of_the_cocoapods_warning_noise(self):
        # CocoaPods prints a UTF-8 warning on stderr before the version.
        self.commands.remove(["pod", "--version"])
        self.commands.on(
            lambda argv: argv[:2] == ["pod", "--version"],
            lambda argv, env: (
                0,
                "1.16.2\n",
                "WARNING: CocoaPods requires your terminal to be using UTF-8 encoding.\n"
                "    Consider adding the following to ~/.profile:\n\n    export LANG=en_US.UTF-8\n",
            ),
        )
        self.assertEqual(release_ci.installed_cocoapods_version(), "1.16.2")
        self.assertEqual(self.apple_build("macos"), 0)

    def test_guard_runs_before_compilation_and_lane(self):
        self.assertEqual(self.apple_build("macos"), 0)
        pods_probe = [
            index for index, call in enumerate(self.commands.calls)
            if call["argv"][:2] == ["pod", "--version"]
        ]
        fastlane_probe = [
            index for index, call in enumerate(self.commands.calls)
            if call["argv"][:1] == ["fastlane"] and call["argv"][-1:] == ["--version"]
        ]
        self.assertEqual(len(pods_probe), 1)
        self.assertEqual(len(fastlane_probe), 1)
        for label, predicate in (
            ("pub get", lambda argv: argv[:3] == ["flutter", "pub", "get"]),
            ("keychain", lambda argv: argv[:2] == ["security", "create-keychain"]),
            ("lane", FASTLANE_LANE("ci_macos_dmg")),
        ):
            position = next(
                (index for index, call in enumerate(self.commands.calls) if predicate(call["argv"])),
                None,
            )
            self.assertIsNotNone(position, label)
            self.assertLess(pods_probe[0], position, f"pod guard must precede {label}")

    def test_the_final_tracked_source_guard_is_unchanged(self):
        source = open(release_ci.__file__).read()
        self.assertIn("def assert_tracked_source_unchanged()", source)
        self.assertIn("assert_tracked_source_unchanged()", source.split("def build(", 1)[1])
        # The guard still refuses any tracked change; nothing was waived.
        self.assertIn('git("status", "--porcelain", "--untracked-files=no")', source)


class ProfilePlistParsingTest(ReleaseTestCase):
    """The profile plist carries date and data values; JSON cannot hold them."""

    def synthetic_profile(self) -> dict:
        return {
            "Name": "Prism Developer ID",
            "UUID": "11111111-2222-3333-4444-555555555555",
            "TeamIdentifier": ["GF2W9X3Y6L"],
            "Platform": ["OSX"],
            "ProvisionsAllDevices": True,
            "ExpirationDate": datetime.datetime(2044, 5, 25, 12, 30),
            "DeveloperCertificates": [b"\x30\x82\x01\x0a-synthetic-der-", b"\x30\x82\x02-second-cert"],
            "Entitlements": {
                "com.apple.application-identifier": "GF2W9X3Y6L.com.prismplural.prism",
                "keychain-access-groups": ["GF2W9X3Y6L.*"],
                "get-task-allow": False,
            },
        }

    def assert_native_types(self, fields: dict) -> None:
        self.assertEqual(fields["Name"], "Prism Developer ID")
        self.assertIsInstance(fields["ExpirationDate"], datetime.datetime)
        self.assertEqual(fields["ExpirationDate"].year, 2044)
        self.assertIsInstance(fields["DeveloperCertificates"], list)
        for certificate in fields["DeveloperCertificates"]:
            self.assertIsInstance(certificate, bytes)
        self.assertEqual(fields["DeveloperCertificates"][0][:2], b"\x30\x82")
        self.assertIs(fields["ProvisionsAllDevices"], True)
        self.assertEqual(fields["Entitlements"]["keychain-access-groups"], ["GF2W9X3Y6L.*"])

    def test_xml_plist_roundtrips_with_native_types(self):
        payload = plistlib.dumps(self.synthetic_profile(), fmt=plistlib.FMT_XML)
        self.assert_native_types(release_ci.parse_profile_plist(payload))

    def test_binary_plist_roundtrips_with_native_types(self):
        payload = plistlib.dumps(self.synthetic_profile(), fmt=plistlib.FMT_BINARY)
        self.assertTrue(payload.startswith(b"bplist"))
        self.assert_native_types(release_ci.parse_profile_plist(payload))

    def test_profile_fields_reads_a_decoded_xml_profile(self):
        payload = plistlib.dumps(self.synthetic_profile(), fmt=plistlib.FMT_XML)
        self.commands.remove(["security", "cms", "-D", "-i"])
        self.commands.on_prefix(
            ["security", "cms", "-D", "-i"], stdout=payload.decode("utf-8")
        )
        path = self.runner_temp / "synthetic.provisionprofile"
        path.write_bytes(b"synthetic-cms-payload")
        fields = release_ci.profile_fields(path)
        self.assert_native_types(fields)
        # The receipt summarises it without leaking bytes or the certificate data.
        summary = release_ci.profile_summary(fields)
        self.assertEqual(summary["expires"], "2044-05-25T12:30:00Z")
        self.assertNotIn("synthetic-der", json.dumps(summary))

    def test_malformed_profile_fails_closed_without_echoing_content(self):
        marker = "TOP-SECRET-PROFILE-BODY"
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.parse_profile_plist(f"<plist><dict>{marker}".encode())
        message = str(caught.exception)
        self.assertIn("could not parse", message)
        self.assertIn("not echoed", message)
        self.assertNotIn(marker, message)

    def test_non_dictionary_root_fails_closed(self):
        payload = plistlib.dumps(["not", "a", "dict"], fmt=plistlib.FMT_XML)
        with self.assertRaises(release_ci.ReleaseError) as caught:
            release_ci.parse_profile_plist(payload)
        self.assertIn("not a dictionary", str(caught.exception))

    def test_plutil_json_can_not_represent_a_profile(self):
        # Documents why the old path failed: the same plist is not JSON-safe.
        payload = plistlib.dumps(self.synthetic_profile(), fmt=plistlib.FMT_XML)
        with self.assertRaises(TypeError):
            json.dumps(plistlib.loads(payload))


FASTLANE_BIN = shutil.which("fastlane")
SCRATCH_FASTFILE = """default_platform(:ios)

platform :ios do
  lane :ci_ios_store do
    puts "ios-lane-marker"
  end
end

platform :mac do
  lane :ci_macos_dmg do
    puts "mac-lane-marker"
  end
end
"""


@unittest.skipUnless(FASTLANE_BIN, "fastlane is not installed on this machine")
class FastlaneLaneNamespaceTest(unittest.TestCase):
    """A bare lane name cannot reach a lane in a non-default platform."""

    @classmethod
    def setUpClass(cls):
        completed = subprocess.run(
            [FASTLANE_BIN, "--version"], capture_output=True, text=True, timeout=120,
            env={**os.environ, "FASTLANE_SKIP_UPDATE_CHECK": "1"},
        )
        match = re.search(r"^fastlane (\d+\.\d+\.\d+)$", completed.stdout, re.MULTILINE)
        if match is None:
            raise unittest.SkipTest("could not determine the installed fastlane version")
        cls.version = match.group(1)
        cls.directory = tempfile.mkdtemp(prefix="prism-fastlane-namespace-")
        fastlane_dir = Path(cls.directory) / "fastlane"
        fastlane_dir.mkdir()
        (fastlane_dir / "Fastfile").write_text(SCRATCH_FASTFILE)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(getattr(cls, "directory", ""), ignore_errors=True)

    def run_fastlane(self, *arguments):
        env = {
            **os.environ,
            "FASTLANE_SKIP_UPDATE_CHECK": "1",
            "FASTLANE_HIDE_CHANGELOG": "1",
            "FASTLANE_DISABLE_ANALYTICS": "1",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
        }
        return subprocess.run(
            [FASTLANE_BIN, f"_{self.version}_", *arguments],
            cwd=self.directory, capture_output=True, text=True, env=env, timeout=180,
        )

    def test_the_scratch_fastfile_is_not_the_repository_one(self):
        self.assertNotEqual(Path(self.directory).resolve(), FASTFILE.parent.parent.resolve())
        self.assertIn("mac-lane-marker", (Path(self.directory) / "fastlane" / "Fastfile").read_text())

    def test_bare_lane_name_fails_for_the_non_default_platform(self):
        result = self.run_fastlane("ci_macos_dmg")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not find lane", result.stderr + result.stdout)
        self.assertIn("ios ci_macos_dmg", result.stderr + result.stdout)

    def test_naming_the_platform_reaches_the_lane(self):
        result = self.run_fastlane("mac", "ci_macos_dmg")
        self.assertEqual(result.returncode, 0, result.stderr[-800:])
        self.assertIn("mac-lane-marker", result.stdout)

    def test_the_default_platform_lane_stays_bare(self):
        result = self.run_fastlane("ci_ios_store")
        self.assertEqual(result.returncode, 0, result.stderr[-800:])
        self.assertIn("ios-lane-marker", result.stdout)
