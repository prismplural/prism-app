#!/usr/bin/env python3
"""Hosted release build helpers for the public prism-app repository.

Build-only by design. This module produces artifacts under ``dist/<platform>/``
and never uploads to a store, attaches a GitHub release asset, publishes store
notes, or bumps a version. Everything it writes outside ``dist/`` is ephemeral,
recorded as owned state, and removed again by ``cleanup``.

    python3 scripts/release_ci.py preflight --platform <platform>
    python3 scripts/release_ci.py build     --platform <platform>
    python3 scripts/release_ci.py cleanup

Platforms: android, ios-unsigned, ios-store, macos.

Environment contract (the workflow passes secrets on this step only):

    PRISM_EXPECTED_REVISION   full 40-hex commit the workflow checked out
    GITHUB_ACTIONS            must be "true" for ``build`` (signing operations)
    PRISM_APPLE_TEAM_ID       nonsecret repository variable
    RUNNER_TEMP               runner scratch directory (default: a temp dir)

    android   ANDROID_UPLOAD_KEYSTORE_BASE64, ANDROID_UPLOAD_STORE_PASSWORD,
              ANDROID_UPLOAD_KEY_PASSWORD, ANDROID_UPLOAD_KEY_ALIAS,
              PRISM_BETA_REGISTRATION_TOKEN
    ios-store IOS_DISTRIBUTION_P12_BASE64, IOS_DISTRIBUTION_P12_PASSWORD,
              IOS_APP_STORE_PROFILE_BASE64, PRISM_BETA_REGISTRATION_TOKEN
    macos     MACOS_DEVELOPER_ID_P12_BASE64, MACOS_DEVELOPER_ID_P12_PASSWORD,
              MACOS_DEVELOPER_ID_PROFILE_BASE64, ASC_KEY_ID, ASC_ISSUER_ID,
              ASC_KEY_P8   (no beta token: the DMG keeps build metadata only)
    ios-unsigned   no environment and no credentials at all

Safety invariants enforced here:

* ``cleanup`` (and every ``build`` run, in ``finally``) removes only paths this
  run recorded as owned, restores the runner's original keychain search list,
  and deletes only the keychain and provisioning profiles it created.
* Keychain/profile import and deletion refuse to run outside GITHUB_ACTIONS.
* Credential values are never written to ``dist/``, to argv we log, or to the
  receipt; derived values (the base64 dart-define form) are masked as well.
* The beta registration token reaches Flutter only through a private
  ``--dart-define-from-file`` file, never as a CLI literal.

Exit codes: 0 success, 1 build or verification failure, 2 usage/preflight or
missing-credential failure.
"""

from __future__ import annotations

import argparse
import base64
import collections
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import tarfile
import sys
import tempfile
import time
from pathlib import Path, PurePosixPath

EXIT_OK = 0
EXIT_FAILURE = 1
EXIT_USAGE = 2

PLATFORMS = ("android", "ios-unsigned", "ios-store", "macos")
APPLE_PLATFORMS = ("ios-store", "macos")

# Secret names each platform is allowed and required to receive. Order is only
# used for the deterministic error message.
PLATFORM_SECRETS = {
    "android": (
        "ANDROID_UPLOAD_KEYSTORE_BASE64",
        "ANDROID_UPLOAD_STORE_PASSWORD",
        "ANDROID_UPLOAD_KEY_PASSWORD",
        "ANDROID_UPLOAD_KEY_ALIAS",
        "PRISM_BETA_REGISTRATION_TOKEN",
    ),
    "ios-unsigned": (),
    "ios-store": (
        "IOS_DISTRIBUTION_P12_BASE64",
        "IOS_DISTRIBUTION_P12_PASSWORD",
        "IOS_APP_STORE_PROFILE_BASE64",
        "PRISM_BETA_REGISTRATION_TOKEN",
    ),
    "macos": (
        "MACOS_DEVELOPER_ID_P12_BASE64",
        "MACOS_DEVELOPER_ID_P12_PASSWORD",
        "MACOS_DEVELOPER_ID_PROFILE_BASE64",
        "ASC_KEY_ID",
        "ASC_ISSUER_ID",
        "ASC_KEY_P8",
    ),
}

# Platforms whose binary carries the beta registration token. The macOS DMG
# keeps the existing sideload behaviour (build metadata defines only), and the
# unsigned sideload IPA has always been credential-free.
BETA_DEFINE_PLATFORMS = ("android", "ios-store")

# Secrets that must NOT reach a platform's build step. The Play service account
# is a store-upload credential (no uploads here) and the unsigned sideload IPA
# must keep its current credential-free shape.
FORBIDDEN_ENV = {
    "android": ("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON",),
    "ios-unsigned": ("PRISM_BETA_REGISTRATION_TOKEN",),
    "ios-store": (),
    "macos": ("PRISM_BETA_REGISTRATION_TOKEN",),
}

ANDROID_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")

SYNC_PIN_RE = re.compile(
    r"^  (?P<name>prism_sync\w*):\n(?:    .*\n)*?      ref: (?P<ref>[0-9a-f]{40})$",
    re.MULTILINE,
)
VERSION_RE = re.compile(r"^version:\s*(?P<name>\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-+]+)*)\+(?P<build>\d+)\s*$", re.MULTILINE)
SECRET_SUFFIXES = (".jks", ".keystore", ".p12", ".p8", ".mobileprovision", ".provisionprofile")

REPO_ROOT = Path(__file__).resolve().parents[1]


# --------------------------------------------------------------------------
# errors and logging


class ReleaseError(Exception):
    """A build, verification or preflight failure (exit 1)."""

    exit_code = EXIT_FAILURE


class UsageError(ReleaseError):
    """A usage or configuration failure (exit 2)."""

    exit_code = EXIT_USAGE


class ToolError(ReleaseError):
    """An external command failed (exit 1)."""


_SECRETS: list[str] = []

# Shortest component line worth masking/redacting; PEM body lines are 64 chars.
MIN_MASKED_LINE = 8


def workflow_escape(value: str) -> str:
    """Escape a value for a one-line GitHub Actions workflow command."""
    return value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def register_secret(value: str | None, *, mask: bool = False) -> None:
    """Remember a value (and its lines) so no log line or error can carry it.

    A multi-line secret such as the raw P8 key must be masked line by line: a
    workflow command stops at the first newline, so emitting the whole value
    would print the key body as ordinary, public log output. The whole value is
    useless to ``redact`` for the same reason, so every component line is
    registered as well.
    """
    if not value:
        return
    if value not in _SECRETS:
        _SECRETS.append(value)
    components = [
        line.strip() for line in value.splitlines() if len(line.strip()) >= MIN_MASKED_LINE
    ]
    for line in components:
        if line not in _SECRETS:
            _SECRETS.append(line)
    if not (mask and github_actions()):
        return
    if len(components) > 1:
        masked = components
    elif "\n" in value or "\r" in value:
        warn("a multi-line secret had no maskable component lines; its value was not emitted")
        return
    else:
        masked = [value]
    for item in masked:
        # Escaped so the command stays one line; Actions masks the secret
        # itself, not values we derive from it.
        print(f"::add-mask::{workflow_escape(item)}", flush=True)


def redact(text: str) -> str:
    for secret in _SECRETS:
        text = text.replace(secret, "***")
    return text


def log(message: str) -> None:
    print(redact(str(message)), flush=True)


def warn(message: str) -> None:
    print(redact(f"warning: {message}"), file=sys.stderr, flush=True)


def github_actions() -> bool:
    return os.environ.get("GITHUB_ACTIONS", "").strip().lower() == "true"



# --------------------------------------------------------------------------
# commands


CAPTURE_LIMIT = 4 * 1024 * 1024
TAIL_LINES = 200


class Result:
    def __init__(self, argv: list[str], returncode: int, stdout: str, stderr: str, *, streamed: bool = False):
        self.argv = argv
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr
        self.streamed = streamed

    @property
    def text(self) -> str:
        return f"{self.stdout}{self.stderr}"


def _bounded(text: str, limit: int = CAPTURE_LIMIT) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n… output truncated after {limit} characters\n"


def run(
    argv: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    check: bool = True,
    quiet: bool = False,
    stream: bool = False,
    capture_limit: int = CAPTURE_LIMIT,
) -> Result:
    """Run one program without a shell, logging the redacted argv.

    ``stream=True`` is for long builds: stdout and stderr are merged, every line
    is printed redacted as it arrives, and only a bounded tail is retained, so an
    hour-long build neither buffers megabytes nor loses its failure diagnostics.
    Short tooling reads use the bounded capture path instead.
    """
    printable = [str(part) for part in argv]
    if not quiet:
        log("$ " + " ".join(printable))
    if not stream:
        process = subprocess.run(
            printable,
            cwd=str(cwd) if cwd else None,
            env=env,
            capture_output=True,
            text=True,
        )
        result = Result(
            printable,
            process.returncode,
            _bounded(redact(process.stdout or ""), capture_limit),
            _bounded(redact(process.stderr or ""), capture_limit),
        )
    else:
        try:
            process = subprocess.Popen(
                printable,
                cwd=str(cwd) if cwd else None,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except FileNotFoundError as error:
            raise ToolError(f"command not found: {printable[0]} ({error})") from error
        tail: deque[str] = collections.deque(maxlen=TAIL_LINES)
        assert process.stdout is not None
        try:
            for line in process.stdout:
                line = redact(line.rstrip("\n"))
                tail.append(line)
                if not quiet:
                    print(line, flush=True)
        finally:
            process.stdout.close()
        returncode = process.wait()
        result = Result(printable, returncode, "\n".join(tail), "", streamed=True)
    if check and result.returncode != 0:
        tail = (result.text or "").strip().splitlines()[-40:]
        raise ToolError(
            redact(f"command failed ({result.returncode}): {' '.join(result.argv)}") + "\n"
            + "\n".join(tail)
        )
    return result


def capture(argv: list[str], **kwargs) -> str:
    return run(argv, **kwargs).text


def env_value(name: str) -> str:
    return os.environ.get(name, "").strip()


def require_env(name: str, *, purpose: str = "") -> str:
    value = env_value(name)
    if not value:
        detail = f" ({purpose})" if purpose else ""
        raise UsageError(f"missing required environment variable {name}{detail}")
    return value


def runner_temp() -> Path:
    base = env_value("RUNNER_TEMP")
    return Path(base) if base else Path(tempfile.gettempdir())


def state_dir() -> Path:
    return runner_temp() / "prism-release"


def dist_dir(platform: str) -> Path:
    return REPO_ROOT / "dist" / platform


def symbols_dir(platform: str) -> Path:
    override = env_value("PRISM_RELEASE_SYMBOLS_DIR")
    if override:
        return Path(override)
    return runner_temp() / "prism-release-symbols" / platform


BUNDLER_ENV = ("BUNDLE_GEMFILE", "BUNDLE_PATH", "BUNDLE_BIN_PATH", "RUBYOPT", "GEM_HOME", "GEM_PATH")


def child_env(platform: str, *, system_first_path: bool = False) -> dict[str, str]:
    """Environment for a build child process: no platform secret ever survives.

    Gradle reads ``android/app/key.properties`` and the beta token arrives in a
    private dart-define file, so the Flutter build, the Gradle daemon, cargokit,
    the native-assets hook and cargo need none of these values; inheriting them
    would put the upload keystore password and the token in every child process.

    Bundler vars break CocoaPods when Flutter shells out to ``pod install``; a
    system-first PATH keeps ``xcodebuild -exportArchive`` on /usr/bin/rsync
    (Homebrew rsync 3.4+ rejects the arguments Xcode passes).
    """
    env = {key: value for key, value in os.environ.items()}
    for name in (
        *BUNDLER_ENV,
        *PLATFORM_SECRETS[platform],
        *FORBIDDEN_ENV[platform],
        *PLATFORM_CONFIG.get(platform, ()),
    ):
        env.pop(name, None)
    if system_first_path:
        env["PATH"] = "/usr/bin:/opt/homebrew/bin:" + env.get("PATH", "")
    return env


# --------------------------------------------------------------------------
# owned ephemeral state


class Owned:
    """Paths and runner state this run created, flushed as it is recorded.

    The record lives in ``$RUNNER_TEMP/prism-release/owned.json`` so a separate
    ``cleanup`` process (an always-run workflow step after a failed build) can
    remove exactly what this run created and nothing else.
    """

    def __init__(self, path: Path | None = None):
        self.path = path or (state_dir() / "owned.json")
        self.state = {
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "paths": [],
            "files": [],
            "keychain": None,
            "keychain_search_list": None,
            "profiles": [],
        }
        self.flush()

    def flush(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.state, indent=2, sort_keys=True) + "\n")
        tmp.replace(self.path)

    def add_path(self, path: Path) -> Path:
        entry = str(path)
        if entry not in self.state["paths"]:
            self.state["paths"].append(entry)
            self.flush()
        return path

    def add_file(self, path: Path) -> Path:
        entry = str(path)
        if entry not in self.state["files"]:
            self.state["files"].append(entry)
            self.flush()
        return path

    def add_profile(self, path: Path) -> Path:
        entry = str(path)
        if entry not in self.state["profiles"]:
            self.state["profiles"].append(entry)
            self.flush()
        return path

    def record_keychain(self, path: Path, original_search_list: list[str]) -> None:
        self.state["keychain"] = str(path)
        self.state["keychain_search_list"] = original_search_list
        self.flush()


def load_owned() -> Owned | None:
    """Read the owned-state record left by this run (never re-create it)."""
    path = state_dir() / "owned.json"
    if not path.is_file():
        return None
    owned = Owned.__new__(Owned)
    owned.path = path
    owned.state = json.loads(path.read_text())
    return owned


# --------------------------------------------------------------------------
# ephemeral keychain and provisioning profiles


def assert_signing_enabled(action: str) -> None:
    if not github_actions():
        raise UsageError(
            f"refusing to {action}: signing operations only run inside GitHub Actions "
            "(GITHUB_ACTIONS=true). Nothing was changed."
        )


def security_list_keychains() -> list[str]:
    raw = capture(["security", "list-keychains", "-d", "user"])
    return [line.strip().strip('"') for line in raw.splitlines() if line.strip()]


def create_ephemeral_keychain(owned: Owned) -> tuple[Path, str]:
    """Create and unlock a fresh keychain and put it on the user search list."""
    assert_signing_enabled("create a signing keychain")
    keychain = state_dir() / "prism-release.keychain-db"
    password = base64.b32encode(os.urandom(30)).decode("ascii").rstrip("=")
    register_secret(password, mask=True)

    original = security_list_keychains()
    owned.record_keychain(keychain, original)

    run(["security", "create-keychain", "-p", password, str(keychain)])
    run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)])
    run(["security", "unlock-keychain", "-p", password, str(keychain)])
    # Keep our keychain first, then the runner's own list: cleanup restores it.
    run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original])
    return keychain, password


def import_p12(keychain: Path, password: str, p12_path: Path, p12_password: str) -> None:
    """Import one identity. Never ``-A``: only codesign/security may use it."""
    assert_signing_enabled("import a signing identity")
    run(
        [
            "security", "import", str(p12_path),
            "-k", str(keychain),
            "-P", p12_password,
            "-T", "/usr/bin/codesign",
            "-T", "/usr/bin/security",
            "-t", "cert",
            "-f", "pkcs12",
        ]
    )
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:,codesign:", "-k", password, str(keychain)])


def profile_search_path() -> Path:
    return Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"


def profile_fields(profile_path: Path) -> dict:
    """Read a provisioning profile's public fields through security + plutil."""
    xml = capture(["security", "cms", "-D", "-i", str(profile_path)])
    with tempfile.NamedTemporaryFile("w", suffix=".plist", delete=False) as handle:
        handle.write(xml)
        xml_path = Path(handle.name)
    try:
        converted = run(["plutil", "-convert", "json", "-o", "-", str(xml_path)]).stdout
    finally:
        xml_path.unlink(missing_ok=True)
    return json.loads(converted)


def install_profile(owned: Owned, profile_path: Path) -> Path:
    """Copy a profile where xcodebuild looks, recording it for cleanup."""
    assert_signing_enabled("install a provisioning profile")
    fields = profile_fields(profile_path)
    uuid = str(fields.get("UUID", "")).strip()
    if not uuid:
        raise ReleaseError(f"provisioning profile {profile_path.name} has no UUID")
    target = profile_search_path() / f"{uuid}.mobileprovision"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        raise ReleaseError(
            f"a provisioning profile with UUID {uuid} already exists in the runner's profile "
            "directory; refusing to overwrite a profile this run does not own"
        )
    shutil.copyfile(profile_path, target)
    os.chmod(target, 0o600)
    owned.add_profile(target)
    return target


def profile_summary(profile: dict) -> dict:
    """Public-safe facts about a profile for the receipt."""
    expiry = str(profile.get("ExpirationDate", ""))
    return {
        "name": str(profile.get("Name", "")),
        "uuid": str(profile.get("UUID", "")),
        "expires": expiry,
        "team_identifiers": sorted(str(team) for team in profile.get("TeamIdentifier", []) or []),
        "all_devices": profile.get("ProvisionsAllDevices") is True,
        "device_bound": "ProvisionedDevices" in profile,
        "platforms": sorted(str(item) for item in profile.get("Platform", []) or []),
    }

# --------------------------------------------------------------------------
# source provenance


def git(*args: str) -> str:
    """Read git state from the checkout being built, wherever the caller stands."""
    return capture(["git", *args], cwd=REPO_ROOT).strip()


def pubspec_text() -> str:
    return (REPO_ROOT / "pubspec.yaml").read_text(encoding="utf-8")


def parse_version(text: str) -> dict:
    match = VERSION_RE.search(text)
    if not match:
        raise UsageError(
            "pubspec.yaml version is not '<semver>+<build number>': hosted builds need an "
            "explicit, immutable build number"
        )
    name, build = match.group("name"), match.group("build")
    return {"pubspec": f"{name}+{build}", "name": name, "build": build}


def sync_pins(text: str) -> dict:
    pins = {match.group("name"): match.group("ref") for match in SYNC_PIN_RE.finditer(text)}
    if "prism_sync" not in pins:
        raise UsageError("pubspec.yaml has no git-pinned prism_sync dependency")
    if len(set(pins.values())) != 1:
        raise UsageError(f"prism_sync packages are pinned to different refs: {sorted(set(pins.values()))}")
    return pins


SYNC_PACKAGES = ("prism_sync", "prism_sync_drift", "prism_sync_flutter")


def resolved_sync_pins() -> dict[str, str]:
    """Commit SHAs the dependency graph actually resolved, from pub's own record.

    ``--enforce-lockfile`` pins the lockfile, but the authoritative evidence that
    the build used those commits is the checkout pub recorded in
    ``.dart_tool/package_config.json`` (``.../git/<name>-<sha>/...``).
    """
    config = REPO_ROOT / ".dart_tool" / "package_config.json"
    if not config.is_file():
        raise ReleaseError(".dart_tool/package_config.json is missing; flutter pub get did not run")
    try:
        packages = json.loads(config.read_text(encoding="utf-8")).get("packages") or []
    except json.JSONDecodeError as error:
        raise ReleaseError(f"could not read .dart_tool/package_config.json: {error}") from error
    resolved = {}
    for package in packages:
        name = str(package.get("name", ""))
        if name not in SYNC_PACKAGES:
            continue
        root = str(package.get("rootUri", ""))
        match = re.search(r"[0-9a-f]{40}", root)
        if match is None:
            raise ReleaseError(
                f"resolved {name} checkout carries no commit SHA ({root}); a local path override "
                "cannot be released"
            )
        resolved[name] = match.group(0)
    return resolved


def assert_resolved_sync_pins(declared: dict[str, str]) -> dict[str, str]:
    """Fail unless every resolved prism_sync checkout is the pinned commit."""
    resolved = resolved_sync_pins()
    missing = sorted(set(declared) - set(resolved))
    if missing:
        raise ReleaseError(
            "the resolved dependency graph has no pinned checkout for " + ", ".join(missing)
        )
    mismatched = sorted(name for name in declared if resolved[name] != declared[name])
    if mismatched:
        detail = "; ".join(
            f"{name}: pubspec {declared[name][:12]}, resolved {resolved[name][:12]}" for name in mismatched
        )
        raise ReleaseError(f"resolved prism_sync checkouts do not match the pubspec pins: {detail}")
    return resolved


def checked_out_revision() -> str:
    return git("rev-parse", "HEAD")


def short_revision() -> str:
    """The short revision git reports for the built commit.

    The published unsigned IPA name embeds it and prism-site's release.js builds
    Prism-${VERSION}-${IOS_BUILD_HASH}-ios-unsigned.ipa from it, so it must come
    from git itself rather than a fixed-width slice of the full SHA.
    """
    value = git("rev-parse", "--short", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{4,40}", value):
        raise ReleaseError(f"git reported an unexpected short revision {value!r}")
    return value


def assert_expected_revision() -> str:
    expected = require_env("PRISM_EXPECTED_REVISION", purpose="full github.sha for this run")
    if not re.fullmatch(r"[0-9a-f]{40}", expected):
        raise UsageError(f"PRISM_EXPECTED_REVISION must be a full 40-character SHA, got {expected!r}")
    actual = checked_out_revision()
    if actual != expected:
        raise ReleaseError(f"checked-out revision {actual} is not the expected {expected}")
    return actual


def assert_clean_checkout() -> None:
    status = git("status", "--porcelain", "--untracked-files=all")
    if status:
        raise ReleaseError(
            "the checkout is not clean before building; a release build must start from "
            "exactly the dispatched commit:\n" + status
        )


def assert_tracked_source_unchanged() -> None:
    """After a build: no tracked file may have changed (generated output is fine)."""
    status = git("status", "--porcelain", "--untracked-files=no")
    if status:
        raise ReleaseError("the build changed tracked source files:\n" + status)


def assert_no_local_overrides() -> None:
    overrides = sorted(str(path.relative_to(REPO_ROOT)) for path in REPO_ROOT.glob("**/pubspec_overrides.yaml"))
    if overrides:
        raise ReleaseError(
            "local dependency overrides are present and would silently replace the pinned "
            "dependencies: " + ", ".join(overrides)
        )
    local_properties = REPO_ROOT / "android" / "local.properties"
    if local_properties.exists():
        raise ReleaseError("android/local.properties is present: a local SDK path override is not allowed")


def assert_no_signing_material_in_tree() -> None:
    """No credential file may survive in the checkout (one walk, pruned)."""
    leftovers = []
    for directory, subdirectories, filenames in os.walk(REPO_ROOT):
        subdirectories[:] = [name for name in subdirectories if name not in (".git",)]
        for filename in filenames:
            if filename.endswith(SECRET_SUFFIXES):
                leftovers.append(os.path.relpath(os.path.join(directory, filename), REPO_ROOT))
    key_properties = REPO_ROOT / "android" / "app" / "key.properties"
    if key_properties.exists():
        leftovers.append(str(key_properties.relative_to(REPO_ROOT)))
    if leftovers:
        raise ReleaseError("signing material was left in the source tree: " + ", ".join(sorted(leftovers)))


def freeze_metadata(platform: str) -> dict:
    """Capture clean-source build metadata before any generated/signing change."""
    version = parse_version(pubspec_text())
    revision = assert_expected_revision()
    assert_clean_checkout()
    assert_no_local_overrides()
    metadata = {
        "platform": platform,
        "version": version,
        "source": {
            "revision": revision,
            "short_revision": short_revision(),
            # A tag dispatch checks out a detached HEAD, where --abbrev-ref
            # says "HEAD"; the workflow's ref name is the honest answer.
            "branch": env_value("GITHUB_REF_NAME") or git("rev-parse", "--abbrev-ref", "HEAD"),
            "describe": git("describe", "--always"),
            "sync_pins": sync_pins(pubspec_text()),
            "clean": True,
        },
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "run": {
            "runner_os": env_value("RUNNER_OS"),
            "runner_arch": env_value("RUNNER_ARCH"),
            "workflow": env_value("GITHUB_WORKFLOW"),
            "job": env_value("GITHUB_JOB"),
            "run_id": env_value("GITHUB_RUN_ID"),
            "attempt": env_value("GITHUB_RUN_ATTEMPT"),
        },
    }
    save_frozen(metadata)
    log(f"froze build metadata for {version['pubspec']} at {revision[:12]}")
    return metadata


def save_frozen(metadata: dict) -> Path:
    path = state_dir() / "frozen-metadata.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    return path


# --------------------------------------------------------------------------
# toolchain capture (public provenance only; no environment dump)


def first_line(text: str) -> str | None:
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return None


def tool_version(argv: list[str], *, allow_failure: bool = True) -> str | None:
    try:
        return first_line(run(argv, check=not allow_failure, quiet=True).text)
    except (ToolError, FileNotFoundError, OSError):
        if not allow_failure:
            raise
        return None


def flutter_sdk_root() -> Path | None:
    try:
        machine = json.loads(run(["flutter", "--version", "--machine"], quiet=True).stdout or "{}")
    except (ReleaseError, json.JSONDecodeError, OSError):
        return None
    root = str(machine.get("flutterRoot", "")).strip()
    return Path(root) if root else None


def flutter_ndk_version() -> str | None:
    """The NDK version the Flutter Gradle plugin pins for this SDK.

    The runner's ANDROID_NDK_HOME usually names a different NDK than the one
    Gradle compiles with, so the receipt has to record the declared version.
    """
    root = flutter_sdk_root()
    if root is None:
        return None
    for relative in (
        "packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt",
        "packages/flutter_tools/gradle/src/main/groovy/flutter.groovy",
    ):
        path = root / relative
        if not path.is_file():
            continue
        match = re.search(r'ndkVersion\s*[:=][^\n]*?"(\d+\.\d+\.\d+)"', path.read_text(errors="ignore"))
        if match:
            return match.group(1)
    return None


def android_sdk_root() -> Path | None:
    sdk = env_value("ANDROID_SDK_ROOT") or env_value("ANDROID_HOME")
    return Path(sdk) if sdk else None


def installed_ndk_versions() -> list[str]:
    sdk = android_sdk_root()
    if sdk is None or not (sdk / "ndk").is_dir():
        return []
    return sorted(path.name for path in (sdk / "ndk").glob("*") if path.is_dir())


def assert_ndk_available(declared: str | None) -> None:
    """Fail before compilation if the pinned NDK is not installed."""
    if not declared:
        return
    sdk = android_sdk_root()
    if sdk is None or not (sdk / "ndk").is_dir():
        return
    if (sdk / "ndk" / declared).is_dir():
        return
    installed = installed_ndk_versions() or ["none"]
    raise ReleaseError(
        f"Flutter pins NDK {declared} but {sdk}/ndk contains {', '.join(installed)}; "
        "Gradle would fail or compile against the wrong NDK"
    )


def gem_versions(*names: str) -> list[str] | None:
    """Resolved gem versions: there is no Gemfile.lock, so drift must be visible."""
    try:
        text = run(["gem", "list", "--local", *names], quiet=True).text
    except (ReleaseError, FileNotFoundError, OSError):
        return None
    entries = [line.strip() for line in text.splitlines() if "(" in line and not line.startswith("***")]
    return entries or None


FLUTTER_PROVENANCE_KEYS = (
    "frameworkVersion",
    "frameworkRevision",
    "frameworkCommitDate",
    "engineRevision",
    "dartSdkVersion",
    "channel",
    "repositoryUrl",
    "repositoryBranch",
)


def flutter_provenance() -> dict:
    """Machine-readable Flutter provenance: a version string is not enough.

    The local 0.16.0 release used an SDK from a user branch, so the receipt has
    to name the exact framework and engine revisions, not "Flutter 3.44.8".
    """
    try:
        data = json.loads(run(["flutter", "--version", "--machine"], quiet=True).stdout or "{}")
    except (ReleaseError, json.JSONDecodeError, OSError):
        return {}
    return {key: str(data[key]) for key in FLUTTER_PROVENANCE_KEYS if data.get(key)}


def toolchain(platform: str, metadata: dict | None = None) -> dict:
    facts = {
        "flutter": tool_version(["flutter", "--version"]),
        "flutter_provenance": flutter_provenance() or None,
        "dart": tool_version(["dart", "--version"]),
        "rustc": tool_version(["rustc", "--version"]),
        "java": tool_version(["java", "-version"]),
    }
    if platform in APPLE_PLATFORMS:
        facts["xcode"] = tool_version(["xcodebuild", "-version"])
        # Reuse the pre-build observation; only a direct caller without metadata
        # (for example a test) probes here.
        provenance = (metadata or {}).get("fastlane_provenance") or fastlane_provenance()
        facts["fastlane"] = f"fastlane {provenance['reported']}"
        facts["fastlane_provenance"] = provenance
        facts["swift"] = tool_version(["swift", "--version"])
        facts["ruby"] = tool_version(["ruby", "--version"])
        facts["gems"] = gem_versions("fastlane", "cocoapods")
        # The pre-build guard already observed the version; reuse it.
        facts["cocoapods"] = (metadata or {}).get("pods", {}).get("installed") or tool_version(
            ["pod", "--version"]
        )
    if platform in SYMBOL_PLATFORMS:
        facts["age"] = tool_version(["age", "--version"])
    if platform == "android":
        facts["ndk"] = flutter_ndk_version()
        facts["ndk_env"] = _ndk_from_env()
        facts["ndk_installed"] = installed_ndk_versions() or None
        sdk = android_sdk_root()
        facts["sdk"] = str(sdk) if sdk else None
    return {key: value for key, value in facts.items() if value}


def _ndk_from_env() -> str | None:
    for name in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT"):
        value = env_value(name)
        if value:
            return Path(value).name
    return None


# --------------------------------------------------------------------------
# artifacts and receipts


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_checksum(path: Path) -> Path:
    checksum = path.with_name(path.name + ".sha256")
    checksum.write_text(f"{sha256_file(path)}  {path.name}\n")
    return checksum


def artifact_record(path: Path, platform: str) -> dict:
    return {
        "name": path.name,
        "path": f"dist/{platform}/{path.name}",
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path),
    }


def write_receipt(
    platform: str,
    metadata: dict,
    *,
    artifacts: list[dict],
    signing: dict,
    symbols: list[dict],
    symbols_archive: dict | None = None,
) -> Path:
    """Write the public-safe provenance receipt into dist/<platform>."""
    receipt = {
        "schema": "prism.release-receipt/v1",
        "platform": platform,
        "produced_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "version": metadata["version"],
        "source": metadata["source"],
        "run": metadata["run"],
        "toolchain": toolchain(platform, metadata),
        "artifacts": artifacts,
        "signing": signing,
        "symbols": symbols,
        "symbols_archive": symbols_archive,
        "pods": metadata.get("pods"),
        "dart_defines": metadata.get("dart_defines", {}),
        "publication": {
            "store_upload": False,
            "github_asset_attach": False,
            "site_publication": False,
            "version_bump": False,
        },
        "notes": RECEIPT_NOTES.get(platform, []),
    }
    path = dist_dir(platform) / "release-receipt.json"
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return path


RECEIPT_NOTES = {
    "android": [
        "Release AAB only: no Play upload, no track change.",
        "Plaintext symbolication files are never in dist/: only an age-encrypted archive is published.",
        "The encrypted archive is not durable on its own; an operator attaches it to the durable release record.",
    ],
    "ios-unsigned": [
        "Unsigned sideload IPA: no signing identity, profile or beta registration token was used.",
    ],
    "ios-store": [
        "App Store-signed IPA only: no App Store Connect upload or TestFlight distribution.",
    ],
    "macos": [
        "Notarization validates signing; it is not store or public publication.",
        "DMG was verified by mounting it read-only; the app was never installed or launched.",
    ],
}

# --------------------------------------------------------------------------
# credentials (names only in logs, values only in files)


def credentials_dir() -> Path:
    return state_dir() / "creds"


def require_credentials(platform: str) -> list[str]:
    """Validate credentials before any compilation starts.

    A forbidden secret is a workflow-contract violation, so it is reported
    before any missing-credential complaint.
    """
    forbidden = [name for name in FORBIDDEN_ENV[platform] if env_value(name)]
    if forbidden:
        raise UsageError(
            f"{platform} build must not receive {', '.join(forbidden)}: this job performs no store "
            "upload, produces a public artifact, and macos/ios-unsigned keep their existing "
            "credential-free build behaviour. Remove it from the job environment."
        )
    missing = [name for name in PLATFORM_SECRETS[platform] if not env_value(name)]
    if missing:
        raise UsageError(
            f"{platform} build is missing required credentials: {', '.join(missing)}. "
            "No compilation was started."
        )
    return list(PLATFORM_SECRETS[platform])


PLATFORM_TOOLS = {
    "android": ("flutter", "java", "keytool", "jarsigner", "unzip", "tar", "age"),
    "ios-unsigned": ("flutter", "unzip", "zip", "pod"),
    "ios-store": ("flutter", "fastlane", "security", "ditto", "xcodebuild", "tar", "age", "pod"),
    "macos": ("flutter", "fastlane", "security", "codesign", "hdiutil", "spctl", "xcrun", "tar", "age", "pod"),
}


# Nonsecret configuration a platform cannot build without.
PLATFORM_CONFIG = {
    "android": ("PRISM_RELEASE_SYMBOLS_RECIPIENT",),
    "ios-store": ("PRISM_RELEASE_SYMBOLS_RECIPIENT", "FASTLANE_VERSION"),
    "macos": ("PRISM_RELEASE_SYMBOLS_RECIPIENT", "FASTLANE_VERSION"),
}

# A plain `fastlane` resolves the newest installed gem, so a preinstalled newer
# fastlane on a runner silently replaces the pinned one. RubyGems' underscore
# selector activates exactly the requested version for the probe, the lane and
# the recorded provenance.
# RubyGems versions may carry dotted prerelease/build segments (2.239.0.pre.1).
GEM_VERSION_RE = re.compile(r"\d+\.\d+\.\d+(?:[.+-][0-9A-Za-z.\-+]+)*")

# `fastlane --version` prints a "fastlane installation at path:" banner whose
# following line is a path that happens to contain the version. Neither is a
# version report, so only an exact "fastlane X.Y.Z" line counts.
FASTLANE_REPORTED_RE = re.compile(
    r"^fastlane\s+(?P<version>\d+\.\d+\.\d+(?:[.+-][0-9A-Za-z.\-+]+)*)\s*$", re.MULTILINE
)

# Platforms whose generated symbolication data ships as an encrypted archive.
# ios-unsigned is deferred by the contract.
SYMBOL_PLATFORMS = ("android", "ios-store", "macos")


def require_tools(platform: str) -> None:
    """Fail before compiling when the runner is missing a tool this platform needs."""
    missing = [tool for tool in PLATFORM_TOOLS[platform] if not shutil.which(tool)]
    if missing:
        raise UsageError(
            f"{platform} build needs tools that are not on PATH: {', '.join(missing)}. "
            "No compilation was started."
        )


# A plain X25519 age recipient: "age1" + 58 bech32 characters. Plugin
# recipients ("age1<plugin>1...") and post-quantum ones ("age1pq1...") contain
# characters outside the bech32 alphabet and are refused, so age can never be
# asked to exec an age-plugin-* binary.
AGE_RECIPIENT_RE = re.compile(r"age1[02-9ac-hj-np-z]{58}")


def validate_age_recipient(value: str) -> str:
    if any(character in value for character in "\r\n"):
        raise UsageError("PRISM_RELEASE_SYMBOLS_RECIPIENT must be a single-line age recipient")
    if not AGE_RECIPIENT_RE.fullmatch(value):
        raise UsageError(
            "PRISM_RELEASE_SYMBOLS_RECIPIENT must be a plain X25519 age recipient "
            "(age1 followed by 58 bech32 characters). Plugin recipients (age1<name>1...) and "
            "post-quantum recipients (age1pq1...) are refused: they can make age execute an "
            "external plugin binary."
        )
    return value


def symbols_recipient() -> str:
    value = require_env(
        "PRISM_RELEASE_SYMBOLS_RECIPIENT",
        purpose="public age recipient for the encrypted symbol archive (repository variable)",
    )
    return validate_age_recipient(value)


PODFILE_LOCKS = {
    "ios-unsigned": "ios/Podfile.lock",
    "ios-store": "ios/Podfile.lock",
    "macos": "macos/Podfile.lock",
}

POD_VERSION_RE = re.compile(r"^\s*(\d+\.\d+\.\d+(?:[.+-][0-9A-Za-z.\-+]+)*)\s*$", re.MULTILINE)


def pod_lock_stamp(platform: str) -> tuple[str, str]:
    """The CocoaPods version stamped in this platform's committed Podfile.lock."""
    relative = PODFILE_LOCKS[platform]
    path = REPO_ROOT / relative
    if not path.is_file():
        raise ReleaseError(
            f"{relative} is missing; CocoaPods resolution cannot be verified before compiling"
        )
    match = re.search(r"^COCOAPODS:\s*(\S+)\s*$", path.read_text(encoding="utf-8"), re.MULTILINE)
    if match is None:
        raise ReleaseError(f"{relative} has no COCOAPODS: version stamp to compare against")
    return relative, match.group(1)


def installed_cocoapods_version() -> str:
    """`pod --version`, ignoring the UTF-8 warning CocoaPods prints on stderr."""
    text = run(["pod", "--version"], quiet=True, check=True).text
    matches = POD_VERSION_RE.findall(text)
    if not matches:
        raise ReleaseError(
            "could not read `pod --version`; CocoaPods did not print a version line. "
            "No compilation was started."
        )
    return matches[-1]


def assert_pod_version_matches_lock(platform: str) -> dict:
    """Fail before compiling when `pod install` would rewrite the committed lock.

    CocoaPods stamps its own version into Podfile.lock, so a runner whose pod
    differs from the one that wrote the lock rewrites that line and the final
    tracked-source guard fails after a full build. This catches it in seconds,
    before compilation, without weakening that guard.
    """
    relative, stamped = pod_lock_stamp(platform)
    installed = installed_cocoapods_version()
    if stamped != installed:
        raise ReleaseError(
            f"CocoaPods {installed} is installed but {relative} is stamped COCOAPODS: {stamped}; "
            "`pod install` would rewrite the lock and the build would fail the tracked-source guard "
            "after compiling. Reconcile the lock deliberately rather than in a build. "
            "No compilation was started."
        )
    return {"lock": relative, "stamped": stamped, "installed": installed}


def require_config(platform: str) -> dict:
    """Validate configuration and, for Apple platforms, prove the fastlane pin early.

    The probe runs here — before any keychain is created, any identity imported,
    any lane started and any compilation — so a selector that resolved the wrong
    gem fails in seconds instead of after a signed build. The observation is
    returned for caching in the build metadata; the receipt reuses it rather than
    probing a second time.
    """
    for name in PLATFORM_CONFIG.get(platform, ()):
        if not env_value(name):
            raise UsageError(
                f"{platform} build requires {name} (nonsecret configuration); "
                "an unset variable arrives as an empty string. No compilation was started."
            )
    if platform in SYMBOL_PLATFORMS:
        symbols_recipient()
    observations: dict = {}
    if platform in PODFILE_LOCKS:
        observations["pods"] = assert_pod_version_matches_lock(platform)
    if platform in APPLE_PLATFORMS:
        observations["fastlane_provenance"] = fastlane_provenance()
    return observations


def fastlane_version() -> str:
    """The pinned fastlane gem version the workflow installed."""
    value = require_env(
        "FASTLANE_VERSION", purpose="pinned fastlane gem version (workflow environment)"
    )
    if not GEM_VERSION_RE.fullmatch(value):
        raise UsageError(
            f"FASTLANE_VERSION must be a plain gem version such as 2.239.0, got {value!r}"
        )
    return value


def fastlane_command(*arguments: str) -> list[str]:
    """`fastlane` with RubyGems activation pinned to FASTLANE_VERSION."""
    return ["fastlane", f"_{fastlane_version()}_", *arguments]


def fastlane_provenance() -> dict:
    """Prove the pinned gem is the one that actually ran.

    The banner and its path line both mention a version, so the only acceptable
    evidence is the exact "fastlane <version>" line the running gem prints. If
    that line is missing, the build fails rather than recording a value nobody
    observed.
    """
    pinned = fastlane_version()
    text = run(fastlane_command("--version"), quiet=True, check=True).text
    match = FASTLANE_REPORTED_RE.search(text)
    if match is None:
        raise ReleaseError(
            f"could not read the activated fastlane version: `fastlane _{pinned}_ --version` printed no "
            "exact 'fastlane <version>' line, and the installation banner or its path is not a version "
            "report. Refusing to record provenance that was never observed."
        )
    reported = match.group("version")
    if reported != pinned:
        raise ReleaseError(
            f"`fastlane _{pinned}_ --version` reports {reported} but the controlled pin is {pinned}; "
            "a newer preinstalled gem may have been selected"
        )
    return {
        "pinned": pinned,
        "reported": reported,
        "activation": f"_{pinned}_",
        "verified": "the underscore-selected gem printed the exact pinned version",
    }


def fastlane_lane_command(lane: str) -> list[str]:
    return fastlane_command(lane)


def write_secret_file(owned: Owned, path: Path, data: bytes) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    path.write_bytes(data)
    os.chmod(path, 0o600)
    owned.add_file(path)
    return path


def decode_base64_secret(name: str, destination: Path, owned: Owned) -> Path:
    value = require_env(name)
    register_secret(value)
    try:
        data = base64.b64decode(value, validate=True)
    except ValueError as error:
        raise UsageError(f"{name} is not valid base64: {error}") from error
    if not data:
        raise UsageError(f"{name} decoded to an empty file")
    return write_secret_file(owned, destination, data)


def write_dart_defines(owned: Owned, metadata: dict, token: str | None) -> Path:
    """Private --dart-define-from-file payload; never a CLI literal."""
    version = metadata["version"]
    source = metadata["source"]
    defines = {
        "APP_VERSION": version["pubspec"],
        "GIT_REV": source["revision"][:7],
        "GIT_DESCRIBE": source["describe"],
        "GIT_BRANCH": source["branch"],
        "BUILT_AT": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    if token:
        defines["PRISM_BETA_REGISTRATION_TOKEN"] = token
        # The binary embeds the token; mask both the raw value and the form it
        # takes inside the file so neither can surface in a log line.
        register_secret(token, mask=True)
        # Actions masks the secret itself, not the derived forms we create.
        define_line = f"PRISM_BETA_REGISTRATION_TOKEN={token}"
        register_secret(define_line, mask=True)
        register_secret(base64.b64encode(define_line.encode("utf-8")).decode("ascii"), mask=True)
    path = state_dir() / "dart-defines.json"
    write_secret_file(owned, path, json.dumps(defines, sort_keys=True).encode("utf-8"))
    # Public-safe evidence of which defines the binary embedded (names only).
    metadata["dart_defines"] = {
        "keys": sorted(defines),
        "includes_beta_registration_token": "PRISM_BETA_REGISTRATION_TOKEN" in defines,
    }
    return path


def beta_token(platform: str) -> str | None:
    """The beta registration token, only for the platforms that embed it."""
    if platform not in BETA_DEFINE_PLATFORMS:
        return None
    return require_env("PRISM_BETA_REGISTRATION_TOKEN")


def apple_team_id() -> str:
    return env_value("PRISM_APPLE_TEAM_ID") or "GF2W9X3Y6L"


def apple_lane_env(platform: str) -> dict[str, str]:
    """Environment for a fastlane lane: paths only, never credential values."""
    env = child_env(platform, system_first_path=True)
    env["GITHUB_ACTIONS"] = "true"
    return env


def flutter_pub_get(platform: str) -> None:
    run(
        ["flutter", "pub", "get", "--enforce-lockfile"],
        cwd=REPO_ROOT,
        env=child_env(platform),
        stream=True,
    )


# --------------------------------------------------------------------------
# android


JAVA_PROPERTY_SPECIALS = set("\\:=#!")


def escape_java_property(value: str) -> str:
    """Escape a value for java.util.Properties (what Gradle reads)."""
    out = []
    for index, char in enumerate(value):
        if char == "\\":
            out.append("\\\\")
        elif char in JAVA_PROPERTY_SPECIALS:
            out.append("\\" + char)
        elif char == "\n":
            out.append("\\n")
        elif char == "\r":
            out.append("\\r")
        elif char == "\t":
            out.append("\\t")
        elif char == " " and index == 0:
            out.append("\\ ")
        else:
            out.append(char)
    return "".join(out)


def key_properties_text(keystore: Path, store_password: str, key_password: str, alias: str) -> str:
    lines = [
        f"storePassword={escape_java_property(store_password)}",
        f"keyPassword={escape_java_property(key_password)}",
        f"keyAlias={escape_java_property(alias)}",
        f"storeFile={escape_java_property(str(keystore))}",
    ]
    return "\n".join(lines) + "\n"


_SHA256_CERT_RE = re.compile(r"SHA256:\s*([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){31})")


def certificate_sha256(text: str, source: str) -> str:
    match = _SHA256_CERT_RE.search(text)
    if not match:
        raise ReleaseError(f"could not read a SHA256 certificate fingerprint from {source}")
    return match.group(1).replace(":", "").upper()


def keystore_fingerprint(keystore: Path, alias: str, store_password: str) -> str:
    env = dict(os.environ, PRISM_CI_KEYSTORE_STORE_PASSWORD=store_password)
    result = run(
        ["keytool", "-list", "-v", "-keystore", str(keystore), "-alias", alias,
         "-storepass:env", "PRISM_CI_KEYSTORE_STORE_PASSWORD"],
        env=env,
    )
    return certificate_sha256(result.text, f"keystore entry {alias}")


def aab_fingerprint(aab: Path) -> str:
    return certificate_sha256(run(["keytool", "-printcert", "-jarfile", str(aab)]).text, aab.name)


def assert_aab_signer(aab: Path, keystore: Path, alias: str, store_password: str) -> str:
    """Fail closed unless the AAB is signed by the configured upload certificate.

    Gradle falls back to the debug key when release signing is not configured;
    comparing against the upload keystore's own certificate is what makes that
    fallback impossible to ship.
    """
    run(["jarsigner", "-verify", str(aab)])
    expected = keystore_fingerprint(keystore, alias, store_password)
    actual = aab_fingerprint(aab)
    if actual != expected:
        raise ReleaseError(
            "the release AAB is not signed by the configured upload certificate "
            f"(artifact {actual}, keystore {expected}). Gradle's debug-key fallback must not ship."
        )
    return actual


def aab_abis(aab: Path) -> list[str]:
    listing = run(["unzip", "-l", str(aab)]).stdout
    present = {abi for abi in ANDROID_ABIS if re.search(rf"lib/{re.escape(abi)}/", listing)}
    missing = [abi for abi in ANDROID_ABIS if abi not in present]
    if missing:
        raise ReleaseError(f"release AAB is missing required ABIs: {', '.join(missing)}")
    return sorted(present)


def assert_safe_input(path: Path, *, label: str, base_root: Path | None = None) -> None:
    """Refuse symlinks, hardlinks, special files and escapes in an archive input.

    This runs before anything is copied or dereferenced, so a link cannot pull a
    file from outside the tree into an archive that ships publicly.
    """
    if base_root is None:
        base_root = path if path.is_dir() else path.parent
    base_real = base_root.resolve()
    if path.is_symlink():
        raise ReleaseError(f"{label}: refusing symlinked input {path}")
    if not path.exists():
        return
    info = path.lstat()
    if path.is_file():
        if not stat.S_ISREG(info.st_mode):
            raise ReleaseError(f"{label}: refusing non-regular input {path} (mode {oct(info.st_mode)})")
        if info.st_nlink > 1:
            raise ReleaseError(f"{label}: refusing hardlinked input {path}; its content may live outside the tree")
        if not _within(path.resolve(), base_real):
            raise ReleaseError(f"{label}: {path} resolves outside {base_real}")
        return
    for directory, subdirectories, filenames in os.walk(path, followlinks=False):
        for name in list(subdirectories) + list(filenames):
            entry = Path(directory) / name
            entry_info = entry.lstat()
            if stat.S_ISLNK(entry_info.st_mode):
                raise ReleaseError(
                    f"{label}: refusing symlink {entry}; a link is either archived as a link "
                    "(extraction escape) or dereferenced into the archive"
                )
            if not (stat.S_ISREG(entry_info.st_mode) or stat.S_ISDIR(entry_info.st_mode)):
                raise ReleaseError(f"{label}: refusing non-regular entry {entry} (mode {oct(entry_info.st_mode)})")
            if stat.S_ISREG(entry_info.st_mode) and entry_info.st_nlink > 1:
                raise ReleaseError(f"{label}: refusing hardlinked entry {entry}")
            if not _within(entry.resolve(), base_real):
                raise ReleaseError(f"{label}: {entry} resolves outside {base_real}")


MANIFEST_NAME = "manifest.json"


def inspect_symbols_tar(tar_path: Path, expected_entries: list[dict]) -> None:
    """Verify the produced tar without extracting anything.

    Regular files and directories only, no absolute or ".." member, and the
    member inventory and digests must agree with the staged manifest.
    """
    expected = {entry["path"] for entry in expected_entries}
    digests = {entry["path"]: entry["sha256"] for entry in expected_entries}
    seen: set[str] = set()
    with tarfile.open(tar_path, "r:gz") as archive:
        for member in archive.getmembers():
            if member.name.startswith("/") or ".." in PurePosixPath(member.name).parts:
                raise ReleaseError(f"symbols tar member {member.name!r} escapes the archive root")
            name = member.name[2:] if member.name.startswith("./") else member.name
            name = name.rstrip("/")
            if member.issym() or member.islnk():
                raise ReleaseError(f"symbols tar contains a link member {member.name!r}")
            if not (member.isfile() or member.isdir()):
                raise ReleaseError(f"symbols tar contains a non-regular member {member.name!r}")
            if member.isdir():
                continue
            handle = archive.extractfile(member)
            if handle is None:
                raise ReleaseError(f"symbols tar member {member.name!r} has no readable payload")
            if name == MANIFEST_NAME:
                manifest = json.loads(handle.read().decode("utf-8"))
                if {entry["path"] for entry in manifest.get("entries", [])} != expected:
                    raise ReleaseError("the archive manifest inventory disagrees with the staged files")
                continue
            if name not in expected:
                raise ReleaseError(f"symbols tar contains an unexpected member {member.name!r}")
            digest = hashlib.sha256()
            for chunk in iter(lambda: handle.read(1 << 20), b""):
                digest.update(chunk)
            if digest.hexdigest() != digests[name]:
                raise ReleaseError(f"symbols tar member {member.name!r} disagrees with its staged digest")
            seen.add(name)
    missing = expected - seen
    if missing:
        raise ReleaseError("symbols tar is missing staged files: " + ", ".join(sorted(missing)))


def unlink_or_fail(path: Path) -> None:
    """Plaintext symbol material must not survive the encryption step."""
    try:
        path.unlink(missing_ok=True)
    except OSError as error:
        raise ReleaseError(f"could not remove plaintext {path}: {error}") from error
    if path.exists():
        raise ReleaseError(f"plaintext {path} still exists after removal; refusing to continue")


def stage_android_symbols(owned: Owned, dart_symbols: Path) -> dict:
    """Gather every Android symbolication file under the staging root.

    They must not be published raw (public Actions artifacts are public), and
    they must not be discarded either: the crash-symbolication archive that
    ships in dist/ is an encrypted form of this directory, so everything lives
    under one root with a stable relative path and a digest per file.
    """
    root = symbols_dir("android")
    # Recorded before the first copy so cleanup can never miss the staging tree.
    owned.add_path(root)
    entries: list[dict] = []

    def add(kind: str, source: Path, destination: Path) -> None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.resolve() != destination.resolve():
            shutil.copyfile(source, destination)
        entries.append(
            {
                "kind": kind,
                "path": destination.relative_to(root).as_posix(),
                "sha256": sha256_file(destination),
                "bytes": destination.stat().st_size,
            }
        )

    dart = sorted(dart_symbols.glob("*.symbols"))
    if not dart:
        raise ReleaseError("no Dart symbol files were written; --split-debug-info did not take effect")
    assert_safe_input(dart_symbols, label="dart symbols")
    for path in dart:
        assert_safe_input(path, label="dart symbol file")
    for path in dart:
        add("dart-symbols", path, path)

    native_root = REPO_ROOT / "build" / "app" / "outputs" / "native-debug-symbols"
    if native_root.is_dir():
        assert_safe_input(native_root, label="native debug symbols")
        for path in sorted(native_root.glob("**/*.zip")):
            assert_safe_input(path, label="native debug symbols zip")
            add("native-debug-symbols", path, root / "native" / path.relative_to(native_root))
    else:
        warn("no native debug symbols zip under build/app/outputs/native-debug-symbols")

    mapping = REPO_ROOT / "build" / "app" / "outputs" / "mapping" / "release" / "mapping.txt"
    if mapping.is_file():
        assert_safe_input(mapping, label="R8 mapping")
        add("r8-mapping", mapping, root / "r8" / "mapping.txt")
    else:
        warn("no R8 mapping.txt under build/app/outputs/mapping/release")

    return {"root": root, "entries": entries}


def symbols_archive_path(platform: str, metadata: dict) -> Path:
    return dist_dir(platform) / (
        f"Prism-{metadata['version']['pubspec']}-{platform}-symbols.tar.gz.age"
    )


def apple_symbol_sources(platform: str) -> list[tuple[Path, str]]:
    if platform == "ios-store":
        return [(REPO_ROOT / "build" / "ios" / "ci" / "Runner.xcarchive" / "dSYMs",
                 "build/ios/ci/Runner.xcarchive/dSYMs")]
    return [(REPO_ROOT / "build" / "macos" / "Build" / "Products" / "Release",
             "build/macos/Build/Products/Release")]


def stage_apple_symbols(platform: str, owned: Owned) -> dict:
    """Copy the generated dSYM bundles under one staging root.

    A candidate whose dSYMs never reach the archive cannot be symbolicated
    later, so a missing bundle fails the build instead of shipping quietly.
    """
    root = symbols_dir(platform)
    owned.add_path(root)
    bundles: list[Path] = []
    searched: list[str] = []
    for source, label in apple_symbol_sources(platform):
        searched.append(label)
        if source.is_dir():
            bundles.extend(sorted(path for path in source.rglob("*.dSYM") if path.is_dir()))
    if not bundles:
        raise ReleaseError(
            f"no dSYM bundles were produced for {platform} (searched {', '.join(searched)}); "
            "refusing to ship a candidate that cannot be symbolicated"
        )
    for bundle in bundles:
        assert_safe_input(bundle, label=f"{platform} dSYM")
    entries: list[dict] = []
    for bundle in bundles:
        target = root / "dsym" / bundle.name
        shutil.copytree(bundle, target, dirs_exist_ok=True)
        for path in sorted(target.rglob("*")):
            if path.is_file():
                entries.append(
                    {
                        "kind": "dSYM",
                        "path": path.relative_to(root).as_posix(),
                        "sha256": sha256_file(path),
                        "bytes": path.stat().st_size,
                    }
                )
    return {"root": root, "entries": entries}


def encrypt_symbols_archive(owned: Owned, platform: str, metadata: dict, staged: dict) -> dict:
    """tar the staged symbol tree and age-encrypt it into dist/android.

    The plaintext never leaves $RUNNER_TEMP: the tarball is written there, the
    archive in dist/ is ciphertext only, and the plaintext tar is deleted as
    soon as age has consumed it. CI holds no decryption identity, so the archive
    is write-only from the runner's side.
    """
    root: Path = staged["root"]
    recipient = symbols_recipient()
    manifest = {
        "schema": "prism.symbols-manifest/v1",
        "platform": platform,
        "version": metadata["version"]["pubspec"],
        "revision": metadata["source"]["revision"],
        "recipient_hint": "decrypt with the release recovery identity",
        "entries": staged["entries"],
    }
    manifest_path = root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    own_path(owned, root)

    # Second pass, immediately before archiving: the staged tree itself must
    # still contain only regular files and directories.
    assert_safe_input(root, label="staged symbols")

    plaintext_tar = state_dir() / f"{platform}-symbols.tar.gz"
    owned.add_file(plaintext_tar)
    # COPYFILE_DISABLE stops macOS bsdtar from adding ._* AppleDouble members for
    # extended attributes, which would otherwise be unexpected archive entries.
    run(
        ["tar", "-czf", str(plaintext_tar), "-C", str(root), "."],
        cwd=REPO_ROOT,
        env=dict(child_env(platform), COPYFILE_DISABLE="1"),
    )
    inspect_symbols_tar(plaintext_tar, staged["entries"])

    recipient_file = write_secret_file(owned, state_dir() / "symbols-recipient.txt", (recipient + "\n").encode("utf-8"))
    archive = symbols_archive_path(platform, metadata)
    archive.parent.mkdir(parents=True, exist_ok=True)
    run(["age", "-R", str(recipient_file), "-o", str(archive), str(plaintext_tar)])
    unlink_or_fail(plaintext_tar)
    write_checksum(archive)

    log(f"encrypted {len(staged['entries'])} symbolication file(s) into {archive.name}")
    return {
        "format": "tar.gz.age",
        "encrypted": True,
        # Not durable by itself: 7-day CI artifacts are not a release record, and
        # this workflow has read-only permissions with no publication surface.
        "durable": False,
        "publication_required": True,
        "recipient": recipient,
        "plaintext_in_dist": False,
        "plaintext_removed": not plaintext_tar.exists(),
        "members": len(staged["entries"]),
        "operator_action": (
            "a parent-owned publication step attaches this archive to a new draft release "
            "and verifies its digest against this receipt"
        ),
        "path": f"dist/{platform}/{archive.name}",
    }


def own_path(owned: Owned, path: Path) -> None:
    owned.add_path(path)


def build_android(owned: Owned, metadata: dict, defines: Path) -> dict:
    assert_ndk_available(flutter_ndk_version())
    keystore = decode_base64_secret(
        "ANDROID_UPLOAD_KEYSTORE_BASE64", credentials_dir() / "upload-keystore.jks", owned
    )
    store_password = require_env("ANDROID_UPLOAD_STORE_PASSWORD")
    key_password = require_env("ANDROID_UPLOAD_KEY_PASSWORD")
    alias = require_env("ANDROID_UPLOAD_KEY_ALIAS")
    register_secret(store_password, mask=True)
    register_secret(key_password, mask=True)

    # The Gradle release signing config reads app/key.properties; the file is
    # this run's, is recorded as owned, and is removed again in cleanup.
    key_properties = REPO_ROOT / "android" / "app" / "key.properties"
    if key_properties.exists():
        raise ReleaseError("android/app/key.properties already exists; refusing to overwrite")
    key_properties.write_text(key_properties_text(keystore, store_password, key_password, alias))
    os.chmod(key_properties, 0o600)
    owned.add_file(key_properties)

    symbol_root = symbols_dir("android")
    dart_symbols = symbol_root / "dart"
    dart_symbols.mkdir(parents=True, exist_ok=True)

    run(
        [
            "flutter", "build", "appbundle",
            "--release",
            "--no-tree-shake-icons",
            f"--dart-define-from-file={defines}",
            f"--split-debug-info={dart_symbols}",
        ],
        cwd=REPO_ROOT,
        env=child_env("android"),
        stream=True,
    )

    aab = REPO_ROOT / "build" / "app" / "outputs" / "bundle" / "release" / "app-release.aab"
    if not aab.is_file():
        raise ReleaseError("flutter build appbundle produced no build/app/outputs/bundle/release/app-release.aab")

    signer = assert_aab_signer(aab, keystore, alias, store_password)
    abis = aab_abis(aab)

    staged_symbols = stage_android_symbols(owned, dart_symbols)

    artifact = dist_dir("android") / f"Prism-{metadata['version']['pubspec']}-android.aab"
    artifact.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(aab, artifact)
    write_checksum(artifact)

    signing = {
        "scheme": "release-upload-keystore",
        "signer_sha256": signer,
        "abis": abis,
        "gradle_debug_key_fallback": "excluded: artifact signer compared to the upload certificate",
    }
    return {
        "artifacts": [artifact_record(artifact, "android")],
        "signing": signing,
        "symbols": staged_symbols["entries"],
        "staged_symbols": staged_symbols,
    }


# --------------------------------------------------------------------------
# ios unsigned


def build_ios_unsigned(owned: Owned, metadata: dict, defines: Path) -> dict:
    run(
        [
            "flutter", "build", "ios",
            "--release",
            "--no-codesign",
            "--no-tree-shake-icons",
            f"--dart-define-from-file={defines}",
        ],
        cwd=REPO_ROOT,
        env=child_env("ios-unsigned", system_first_path=True),
        stream=True,
    )

    version = metadata["version"]["pubspec"]
    # Consumer contract: prism-site builds this name with the short revision in
    # it (Prism-<version>-<git short>-ios-unsigned.ipa). Do not drop the hash.
    short = metadata["source"]["short_revision"]
    artifact = dist_dir("ios-unsigned") / f"Prism-{version}-{short}-ios-unsigned.ipa"
    artifact.parent.mkdir(parents=True, exist_ok=True)
    run(
        ["scripts/package_unsigned_ipa.sh", str(artifact)],
        cwd=REPO_ROOT,
        env=child_env("ios-unsigned", system_first_path=True),
        stream=True,
    )
    if not artifact.is_file() or artifact.stat().st_size == 0:
        raise ReleaseError(f"unsigned sideload packing produced no IPA at {artifact}")

    listing = run(["unzip", "-l", str(artifact)]).stdout
    if "Payload/Runner.app/" not in listing:
        raise ReleaseError("unsigned sideload IPA has no Payload/Runner.app payload")
    if "embedded.mobileprovision" in listing or "_CodeSignature" in listing:
        raise ReleaseError("unsigned sideload IPA contains signing material; --no-codesign did not hold")

    write_checksum(artifact)
    signing = {
        "scheme": "none",
        "identity": None,
        "profiles": [],
        "verified": "built with --no-codesign; no identity, profile or registration token used",
    }
    return {
        "artifacts": [artifact_record(artifact, "ios-unsigned")],
        "signing": signing,
        "symbols": [],
        "symbols_archive": None,
    }


# --------------------------------------------------------------------------
# apple signed platforms (fastlane lanes reuse the audited helpers)


def read_signing_facts(platform: str) -> dict:
    path = state_dir() / "signing-facts.json"
    if not path.is_file():
        raise ReleaseError(f"the {platform} fastlane lane wrote no signing facts; verification did not run")
    return json.loads(path.read_text())


def build_apple(owned: Owned, platform: str, metadata: dict, defines: Path) -> dict:
    version = metadata["version"]
    team = apple_team_id()
    creds = credentials_dir()

    if platform == "ios-store":
        p12 = decode_base64_secret("IOS_DISTRIBUTION_P12_BASE64", creds / "ios-distribution.p12", owned)
        p12_password = require_env("IOS_DISTRIBUTION_P12_PASSWORD")
        profile = decode_base64_secret(
            "IOS_APP_STORE_PROFILE_BASE64", creds / "ios-app-store.mobileprovision", owned
        )
        lane = "ci_ios_store"
    else:
        p12 = decode_base64_secret("MACOS_DEVELOPER_ID_P12_BASE64", creds / "developer-id.p12", owned)
        p12_password = require_env("MACOS_DEVELOPER_ID_P12_PASSWORD")
        profile = decode_base64_secret(
            "MACOS_DEVELOPER_ID_PROFILE_BASE64", creds / "developer-id.provisionprofile", owned
        )
        lane = "ci_macos_dmg"

    register_secret(p12_password, mask=True)
    fields = profile_fields(profile)
    installed = install_profile(owned, profile)
    profile_name = str(fields.get("Name", "")).strip()
    if not profile_name:
        raise ReleaseError(f"provisioning profile {profile.name} has no Name; xcodebuild cannot select it")

    keychain, keychain_password = create_ephemeral_keychain(owned)
    import_p12(keychain, keychain_password, p12, p12_password)

    env = apple_lane_env(platform)
    env.update(
        {
            "PRISM_CI_DART_DEFINES_FILE": str(defines),
            "PRISM_CI_ARTIFACT_DIR": str(dist_dir(platform)),
            "PRISM_CI_STATE_DIR": str(state_dir()),
            "PRISM_CI_PROFILE_PATH": str(installed),
            "PRISM_CI_PROFILE_NAME": profile_name,
            "PRISM_CI_VERSION": version["pubspec"],
            "PRISM_CI_VERSION_NAME": version["name"],
            "PRISM_CI_BUILD_NUMBER": version["build"],
            "PRISM_APPLE_TEAM_ID": team,
        }
    )
    if platform == "macos":
        p8 = require_env("ASC_KEY_P8")
        register_secret(p8, mask=True)
        p8_bytes = p8.encode("utf-8")
        if not p8_bytes.endswith(b"\n"):
            p8_bytes += b"\n"
        asc_key = write_secret_file(owned, creds / "AuthKey.p8", p8_bytes)
        env.update(
            {
                "PRISM_MAC_PROVISIONING_PROFILE": str(installed),
                "ASC_KEY_ID": require_env("ASC_KEY_ID"),
                "ASC_ISSUER_ID": require_env("ASC_ISSUER_ID"),
                "ASC_KEY_FILEPATH": str(asc_key),
            }
        )

    dist = dist_dir(platform)
    dist.mkdir(parents=True, exist_ok=True)
    run(fastlane_lane_command(lane), cwd=REPO_ROOT, env=env, stream=True)

    produced = [
        path
        for path in sorted(dist.iterdir())
        if path.is_file() and path.suffix in {".ipa", ".dmg"}
    ]
    if len(produced) != 1:
        raise ReleaseError(
            f"expected exactly one {platform} artifact in {dist}, found "
            + (", ".join(path.name for path in produced) or "none")
        )
    artifact = produced[0]
    write_checksum(artifact)
    signing = read_signing_facts(platform)
    signing["profile"] = profile_summary(fields)
    signing["team_id"] = team
    return {
        "artifacts": [artifact_record(artifact, platform)],
        "signing": signing,
        "symbols": [],
        "symbols_archive": None,
    }

# --------------------------------------------------------------------------
# cleanup


def _within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except (ValueError, OSError):
        return False


def _restore_keychain(state: dict) -> None:
    keychain = state.get("keychain")
    original = state.get("keychain_search_list")
    if not keychain:
        return
    if not github_actions():
        warn(f"refusing to delete the keychain {keychain} outside GitHub Actions")
        return
    if not shutil.which("security"):
        warn("security tool is not available; the ephemeral keychain was not deleted")
        return
    keychain_path = Path(keychain)
    if not _within(keychain_path, runner_temp()):
        warn(f"refusing to touch a keychain outside RUNNER_TEMP: {keychain_path}")
        return
    if original is not None:
        run(["security", "list-keychains", "-d", "user", "-s", *original], check=False)
    if keychain_path.exists():
        run(["security", "delete-keychain", str(keychain_path)], check=False)
        log("cleanup: deleted the ephemeral signing keychain")
    else:
        log("cleanup: ephemeral keychain already gone")


def _remove_profiles(state: dict) -> None:
    entries = state.get("profiles", [])
    if not entries:
        return
    if not github_actions():
        # Same guard as the keychain: a stale state file must never let a local
        # run delete profiles out of a person's real profile directory.
        warn(f"refusing to delete {len(entries)} provisioning profile(s) outside GitHub Actions")
        return
    root = profile_search_path()
    for entry in entries:
        path = Path(entry)
        if not _within(path, root):
            warn(f"refusing to delete a provisioning profile outside the runner profile directory: {path}")
            continue
        if path.exists():
            path.unlink()
            log(f"cleanup: removed provisioned profile {path.name}")


# The only repository paths this tool may create and delete: Gradle's release
# signing config and nothing else. Everything else it writes lives in RUNNER_TEMP.
REPO_OWNED_FILES = ("android/app/key.properties",)


def _deletable(path: Path, temp_root: Path) -> bool:
    if _within(path, temp_root):
        return True
    try:
        relative = path.resolve().relative_to(REPO_ROOT.resolve())
    except ValueError:
        return False
    return str(relative) in REPO_OWNED_FILES


def _remove_owned_paths(state: dict) -> None:
    temp_root = runner_temp()
    entries = [Path(entry) for entry in state.get("files", []) + state.get("paths", [])]
    for path in sorted(entries, key=lambda item: len(item.parts), reverse=True):
        if not _deletable(path, temp_root):
            warn(f"refusing to delete a path this tool does not own: {path}")
            continue
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
        elif path.exists():
            path.unlink()


def cleanup() -> int:
    """Remove exactly what this run created. Safe to run when nothing happened."""
    owned = load_owned()
    if owned is None:
        log("cleanup: nothing owned by this run")
        return EXIT_OK
    state = owned.state
    _restore_keychain(state)
    _remove_profiles(state)
    _remove_owned_paths(state)
    shutil.rmtree(state_dir(), ignore_errors=True)
    try:
        assert_no_signing_material_in_tree()
    except ReleaseError as error:
        warn(str(error))
    log("cleanup: run-owned secret and signing state removed")
    return EXIT_OK


# --------------------------------------------------------------------------
# commands


def preflight(platform: str) -> int:
    """Read-only source check; writes only the frozen metadata snapshot."""
    metadata = freeze_metadata(platform)
    missing = [name for name in PLATFORM_SECRETS[platform] if not env_value(name)]
    summary = {
        "platform": platform,
        "version": metadata["version"],
        "revision": metadata["source"]["revision"],
        "branch": metadata["source"]["branch"],
        "sync_pins": metadata["source"]["sync_pins"],
        "clean": metadata["source"]["clean"],
        "credentials_present": sorted(set(PLATFORM_SECRETS[platform]) - set(missing)),
        "credentials_missing": missing,
        "dist": f"dist/{platform}",
        "flutter": shutil.which("flutter"),
    }
    log(json.dumps(summary, indent=2, sort_keys=True))
    if missing:
        warn(
            "preflight: this environment does not have "
            + ", ".join(missing)
            + " (build validates credentials again before compiling)"
        )
    if not shutil.which("flutter"):
        warn("preflight: flutter is not on PATH; the build step needs it")
    if platform in APPLE_PLATFORMS and not shutil.which("fastlane"):
        warn("preflight: fastlane is not on PATH; the build step needs it")
    return EXIT_OK


BUILDERS = {
    "android": build_android,
    "ios-unsigned": build_ios_unsigned,
    "ios-store": build_apple,
    "macos": build_apple,
}


def build(platform: str) -> int:
    if not github_actions():
        raise UsageError(
            "refusing to build: hosted builds install signing material and only run inside "
            "GitHub Actions (GITHUB_ACTIONS=true). Nothing was changed."
        )
    owned = Owned()
    succeeded = False
    try:
        metadata = freeze_metadata(platform)
        require_tools(platform)
        metadata.update(require_config(platform))
        save_frozen(metadata)
        require_credentials(platform)
        defines = write_dart_defines(owned, metadata, beta_token(platform))
        flutter_pub_get(platform)
        metadata["source"]["resolved_sync_pins"] = assert_resolved_sync_pins(
            metadata["source"]["sync_pins"]
        )
        save_frozen(metadata)
        builder = BUILDERS[platform]
        if platform in APPLE_PLATFORMS:
            outcome = builder(owned, platform, metadata, defines)
        else:
            outcome = builder(owned, metadata, defines)
        if platform in SYMBOL_PLATFORMS:
            staged = outcome.pop("staged_symbols", None) or stage_apple_symbols(platform, owned)
            archive = encrypt_symbols_archive(owned, platform, metadata, staged)
            outcome["artifacts"].append(artifact_record(symbols_archive_path(platform, metadata), platform))
            outcome["symbols"] = staged["entries"]
            outcome["symbols_archive"] = archive
        receipt = write_receipt(
            platform,
            metadata,
            artifacts=outcome["artifacts"],
            signing=outcome["signing"],
            symbols=outcome["symbols"],
            symbols_archive=outcome.get("symbols_archive"),
        )
        succeeded = True
        log(f"wrote dist/{platform}: " + ", ".join(item["name"] for item in outcome["artifacts"]))
        log(f"receipt: {receipt.relative_to(REPO_ROOT)}")
        return EXIT_OK
    finally:
        failed = sys.exc_info()[0] is not None
        if failed:
            # A failed run must never leave a publishable-looking partial
            # artifact behind for an always-run upload step to pick up.
            shutil.rmtree(dist_dir(platform), ignore_errors=True)
        try:
            cleanup()
            assert_no_signing_material_in_tree()
            if succeeded:
                assert_tracked_source_unchanged()
        except ReleaseError as error:
            shutil.rmtree(dist_dir(platform), ignore_errors=True)
            if failed:
                warn(f"post-build check: {error}")
            else:
                raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="release_ci.py",
        description="Hosted release build helpers (build only; never uploads or publishes).",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name, help_text in (
        ("preflight", "verify the checkout, version, pins and expected revision"),
        ("build", "build one platform's artifacts into dist/<platform>/"),
    ):
        subparser = subparsers.add_parser(name, help=help_text)
        subparser.add_argument("--platform", required=True, choices=PLATFORMS)
    subparsers.add_parser("cleanup", help="remove this run's ephemeral secrets and signing state")
    args = parser.parse_args(argv)
    try:
        if args.command == "preflight":
            return preflight(args.platform)
        if args.command == "build":
            return build(args.platform)
        return cleanup()
    except ReleaseError as error:
        print(redact(f"error: {error}"), file=sys.stderr)
        return error.exit_code
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        return EXIT_FAILURE


if __name__ == "__main__":
    sys.exit(main())
