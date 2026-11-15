"""Behavioural regression tests for fastlane/ci_signing.rb's iOS store validation.

Real Ruby, one process, the real module; only the Fastlane UI is stubbed. No
signing identity, provisioning profile or certificate is used: profile fields
and "certificate" bytes are synthesised, and nothing is written outside a
temporary directory.

Run: python3 -m unittest discover -s scripts/tests -p 'test_*.py'
"""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

FASTLANE = Path(__file__).resolve().parents[2] / "fastlane"
CI_SIGNING = FASTLANE / "ci_signing.rb"
FASTFILE = FASTLANE / "Fastfile"
RUBY = shutil.which("ruby")

TEAM = "GF2W9X3Y6L"
BUNDLE = "com.prismplural.prism"
APP_ID = f"{TEAM}.{BUNDLE}"
CERT = b"fake-der-bytes-not-a-real-certificate"
CERT_SHA1 = hashlib.sha1(CERT).hexdigest().upper()
APP_ATTEST = "com.apple.developer.devicecheck.appattest-environment"

DRIVER = r"""
$LOAD_PATH.unshift ARGV.shift
require "base64"
require "json"
module FastlaneCore
  module Interface
    class UserError < StandardError; end
  end

  # The real namespace. A top-level ::UI must NOT be defined: fastlane has no
  # such constant, and stubbing one is what hid the NameError that broke the
  # hosted macOS run.
  module UI
    def self.user_error!(message)
      raise FastlaneCore::Interface::UserError, message.to_s
    end

    def self.abort_with_message!(message)
      raise FastlaneCore::Interface::UserError, message.to_s
    end

    def self.success(_message); end
    def self.message(_message); end
    def self.important(_message); end
  end
end
require "ci_signing"

payload = JSON.parse(File.read(ARGV.shift))
results = payload["cases"].map do |value|
  profile = value["profile"]
  expiry = profile["ExpirationDate"]
  profile["ExpirationDate"] = Time.at(expiry.to_i) if expiry.is_a?(Numeric)
  profile["DeveloperCertificates"] =
    Array(value["developer_certificates"]).map { |item| Base64.decode64(item) }
  begin
    classification = CISigning.validate_ios_store_profile!(
      profile, value["entitlements"],
      team_id: value["team_id"], bundle_id: value["bundle_id"],
      certificate_sha1: value["certificate_sha1"]
    )
    { "ok" => true, "error" => nil, "classification" => classification }
  rescue StandardError => error
    { "ok" => false, "error" => "#{error.class}: #{error.message}", "classification" => nil }
  end
end
puts JSON.generate("results" => results)
"""


def profile(*, groups=None, app_attest="production", all_devices=False, device_bound=False,
            expiration=4070908800, team=TEAM, app_identifier=APP_ID) -> dict:
    """A distribution profile; `groups` are its keychain patterns."""
    entitlements = {
        "application-identifier": app_identifier,
        "com.apple.developer.team-identifier": team,
        "get-task-allow": False,
    }
    if groups is not None:
        entitlements["keychain-access-groups"] = groups
    if app_attest is not None:
        entitlements[APP_ATTEST] = app_attest
    result = {
        "Name": "Prism App Store",
        "UUID": "11111111-2222-3333-4444-555555555555",
        "TeamIdentifier": [team],
        "Platform": ["iOS"],
        "ExpirationDate": expiration,
        "Entitlements": entitlements,
    }
    if all_devices:
        result["ProvisionsAllDevices"] = True
    if device_bound:
        result["ProvisionedDevices"] = ["00008030-0000"]
    return result


def app(*, groups=..., app_attest="production", get_task_allow=False) -> dict:
    """App entitlements. Omit `groups` entirely for the shipped shape."""
    entitlements = {
        "application-identifier": APP_ID,
        "com.apple.developer.team-identifier": TEAM,
        "get-task-allow": get_task_allow,
    }
    if groups is not ...:
        entitlements["keychain-access-groups"] = groups
    if app_attest is not None:
        entitlements[APP_ATTEST] = app_attest
    return entitlements


def case(profile_value=None, entitlements=None, *, certificate_sha1=CERT_SHA1, bundle=BUNDLE) -> dict:
    return {
        "profile": profile_value if profile_value is not None else profile(groups=[APP_ID, f"{TEAM}.*"]),
        "entitlements": entitlements if entitlements is not None else app(groups=[APP_ID]),
        "team_id": TEAM,
        "bundle_id": bundle,
        "certificate_sha1": certificate_sha1,
        "developer_certificates": [base64.b64encode(CERT).decode()],
    }


def without(mapping: dict, key: str) -> dict:
    return {name: value for name, value in mapping.items() if name != key}


def run_validator(cases: list[dict]) -> list[dict]:
    with tempfile.TemporaryDirectory() as directory:
        payload = Path(directory) / "cases.json"
        payload.write_text(json.dumps({"cases": cases}))
        driver = Path(directory) / "driver.rb"
        driver.write_text(DRIVER)
        completed = subprocess.run(
            [RUBY, str(driver), str(FASTLANE), str(payload)],
            capture_output=True,
            text=True,
        )
    if completed.returncode != 0:
        raise AssertionError(f"ruby driver failed: {completed.stderr}")
    return json.loads(completed.stdout)["results"]


@unittest.skipUnless(RUBY, "ruby is not available on this machine")
class IosStoreValidationTest(unittest.TestCase):
    """Each case is a shape a real build or profile actually takes."""

    @classmethod
    def setUpClass(cls):
        shipped_profile = profile(groups=[f"{TEAM}.*", "com.apple.token"])
        token_only = profile(groups=["com.apple.token"])
        exact_id = profile(groups=[APP_ID])
        declared_both = profile(groups=[APP_ID, f"{TEAM}.other.group"])
        no_attest = without(profile(groups=[APP_ID, f"{TEAM}.*"])["Entitlements"], APP_ATTEST)

        cls.names = [
            # shipped shape: no keychain entitlement, profile authorizes TEAM.*
            "shipped_shape",
            "implicit_exact_id_profile",
            "implicit_unauthorized_profile",
            "malformed_null",
            "malformed_empty",
            "malformed_string",
            "declared_with_default_first",
            "declared_wrong_first_group",
            "declared_without_default",
            "declared_unauthorized_group",
            "development",
            "missing_appattest",
            "development_appattest",
            "profile_without_appattest",
            "profile_attest_allowlist_array",
            "enterprise_all_devices",
            "device_bound",
            "expired",
            "wrong_team",
            "unauthorized_certificate",
            "profile_for_other_bundle",
        ]
        cls.cases = [
            case(profile_value=shipped_profile, entitlements=app()),
            case(profile_value=exact_id, entitlements=app()),
            case(profile_value=token_only, entitlements=app()),
            case(entitlements=app(groups=None)),
            case(entitlements=app(groups=[])),
            case(entitlements=app(groups=APP_ID)),
            case(profile_value=declared_both, entitlements=app(groups=[APP_ID, f"{TEAM}.other.group"])),
            case(profile_value=declared_both,
                 entitlements=app(groups=[f"{TEAM}.other.group", APP_ID])),
            case(entitlements=app(groups=[f"{TEAM}.some.other.group"])),
            case(entitlements=app(groups=[APP_ID, "com.someoneelse.group"])),
            case(entitlements=app(groups=[APP_ID], get_task_allow=True)),
            case(entitlements=app(groups=[APP_ID], app_attest=None)),
            case(entitlements=app(groups=[APP_ID], app_attest="development")),
            case(profile_value={**profile(groups=[APP_ID, f"{TEAM}.*"]), "Entitlements": no_attest},
                 entitlements=app(groups=[APP_ID])),
            case(profile_value=profile(groups=[APP_ID], app_attest=["development", "production"]),
                 entitlements=app(groups=[APP_ID])),
            case(profile_value=profile(groups=[APP_ID, f"{TEAM}.*"], all_devices=True),
                 entitlements=app(groups=[APP_ID])),
            case(profile_value=profile(groups=[APP_ID, f"{TEAM}.*"], device_bound=True),
                 entitlements=app(groups=[APP_ID])),
            case(profile_value=profile(groups=[APP_ID, f"{TEAM}.*"], expiration=1000000000),
                 entitlements=app(groups=[APP_ID])),
            case(profile_value=profile(groups=[APP_ID, f"{TEAM}.*"], team="OTHERTEAM1"),
                 entitlements=app(groups=[APP_ID])),
            case(entitlements=app(groups=[APP_ID]), certificate_sha1="0" * 40),
            case(profile_value=profile(groups=[APP_ID], app_identifier=f"{TEAM}.com.example.other"),
                 entitlements=app(groups=[APP_ID])),
        ]
        cls.by_name = dict(zip(cls.names, run_validator(cls.cases), strict=True))

    def result(self, name: str) -> dict:
        return self.by_name[name]

    def assert_accepted(self, name: str) -> dict:
        result = self.result(name)
        self.assertTrue(result["ok"], f"{name} should have been accepted: {result['error']}")
        return result["classification"]

    def assert_rejected(self, name: str, fragment: str) -> None:
        result = self.result(name)
        self.assertFalse(result["ok"], f"{name} should have been rejected")
        self.assertIn(fragment, result["error"], f"{name}: unexpected message")

    # -- the shipped shape -------------------------------------------------

    def test_shipped_shape_without_keychain_entitlement_is_accepted(self):
        classification = self.assert_accepted("shipped_shape")
        self.assertEqual(classification["keychain_groups"], "implicit")
        self.assertEqual(classification["keychain_access_groups"], [])
        self.assertEqual(classification["effective_default_keychain_group"], APP_ID)

    def test_implicit_default_is_accepted_when_the_profile_names_the_exact_id(self):
        classification = self.assert_accepted("implicit_exact_id_profile")
        self.assertEqual(classification["keychain_groups"], "implicit")
        self.assertEqual(classification["keychain_access_groups"], [])

    def test_implicit_default_is_refused_when_the_profile_does_not_authorize_it(self):
        self.assert_rejected(
            "implicit_unauthorized_profile",
            f"profile does not authorize the implicit default keychain group {APP_ID}",
        )

    # -- malformed declarations -------------------------------------------

    def test_malformed_declarations_are_refused(self):
        for name in ("malformed_null", "malformed_empty", "malformed_string"):
            self.assert_rejected(name, "malformed keychain-access-groups")

    # -- explicit declarations --------------------------------------------

    def test_declared_groups_with_the_default_first_are_accepted(self):
        classification = self.assert_accepted("declared_with_default_first")
        self.assertEqual(classification["keychain_groups"], "explicit")
        self.assertEqual(
            classification["keychain_access_groups"], [APP_ID, f"{TEAM}.other.group"]
        )
        self.assertEqual(classification["effective_default_keychain_group"], APP_ID)

    def test_declared_groups_with_the_wrong_effective_default_are_refused(self):
        # The profile authorizes both groups, so only the first-entry rule fails.
        self.assert_rejected(
            "declared_wrong_first_group",
            f"declares \"{TEAM}.other.group\" as its effective default keychain group",
        )

    def test_declared_groups_without_the_default_are_refused(self):
        self.assert_rejected("declared_without_default", "effective default keychain group")

    def test_declared_group_the_profile_does_not_authorize_is_refused(self):
        self.assert_rejected("declared_unauthorized_group", "does not authorize keychain access group")

    # -- unchanged checks --------------------------------------------------

    def test_app_attest_three_distinct_refusals(self):
        self.assert_rejected("missing_appattest", "missing the App Attest entitlement")
        self.assert_rejected("development_appattest", "not production")
        self.assert_rejected(
            "profile_without_appattest", "does not authorize the production App Attest environment"
        )

    def test_profile_allowlist_array_with_development_and_production_is_accepted(self):
        # The real profile hands back ["development", "production"], so the
        # allowlist must be read as a list rather than compared as a string.
        classification = self.assert_accepted("profile_attest_allowlist_array")
        self.assertEqual(classification["effective_default_keychain_group"], APP_ID)

    def test_development_and_enterprise_shapes_are_refused(self):
        self.assert_rejected("development", "get-task-allow")
        self.assert_rejected("device_bound", "device-bound")
        self.assert_rejected("enterprise_all_devices", "enterprise rather than App Store")

    def test_profile_lifetime_team_and_certificate_are_enforced(self):
        self.assert_rejected("expired", "expired")
        self.assert_rejected("wrong_team", "team does not match")
        self.assert_rejected("unauthorized_certificate", "does not authorize the signing certificate")
        self.assert_rejected("profile_for_other_bundle", "does not authorize app identifier")

    # -- receipt consistency ----------------------------------------------

    def test_receipt_pair_is_never_inconsistent(self):
        for name in ("shipped_shape", "implicit_exact_id_profile"):
            classification = self.result(name)["classification"]
            self.assertEqual(classification["keychain_groups"], "implicit")
            self.assertEqual(classification["keychain_access_groups"], [])
        for name in ("declared_with_default_first",):
            classification = self.result(name)["classification"]
            self.assertEqual(classification["keychain_groups"], "explicit")
            self.assertTrue(classification["keychain_access_groups"])
            self.assertEqual(classification["keychain_access_groups"][0], APP_ID)


@unittest.skipUnless(RUBY, "ruby is not available on this machine")
class ReceiptWordingTest(unittest.TestCase):
    """The facts string must distinguish implicit from declared, and never lie."""

    def source(self) -> str:
        return CI_SIGNING.read_text()

    def test_verified_text_differs_between_the_two_modes(self):
        text = self.source()
        self.assertIn('"implicit default keychain group #{keychain[\'effective_default_keychain_group\']} authorized by the profile"', text)
        self.assertIn('"declared keychain groups authorized (effective default "', text)

    def test_receipt_records_actual_claims_and_the_mode(self):
        text = self.source()
        self.assertIn('"keychain_groups" => keychain["keychain_groups"]', text)
        self.assertIn('"keychain_access_groups" => keychain["keychain_access_groups"]', text)
        self.assertIn('"effective_default_keychain_group" => keychain["effective_default_keychain_group"]', text)
        # No invented group: the old Array(entitlements[...]) path is gone.
        self.assertNotIn('"keychain_access_groups" => Array(entitlements["keychain-access-groups"])', text)

    def test_app_attest_is_read_through_an_array_allowlist(self):
        self.assertIn("Array(allowed[APP_ATTEST_ENTITLEMENT]).map(&:to_s).include?", self.source())

    def test_deep_strict_verification_only(self):
        for line in self.source().splitlines():
            if '"--deep"' in line:
                self.assertIn("--verify", line, f"--deep outside verification: {line.strip()}")

    def test_shipped_entitlement_file_is_not_extended_with_keychain_sharing(self):
        # The app intentionally has no Keychain Sharing; the validator adapts to
        # it, the app does not gain an entitlement for the validator's sake.
        entitlements = (Path(__file__).resolve().parents[2] / "ios" / "Runner" / "Runner.entitlements").read_text()
        self.assertNotIn("keychain-access-groups", entitlements)


SIGNATURE_DRIVER = r"""
$LOAD_PATH.unshift ARGV.shift
require "json"
module FastlaneCore
  module Interface
    class UserError < StandardError; end
  end
  module UI
    def self.user_error!(message)
      raise FastlaneCore::Interface::UserError, message.to_s
    end
    def self.important(_message); end
    def self.success(_message); end
    def self.message(_message); end
  end
end
require "ci_signing"
begin
  classification = CISigning.assert_no_identity_signature!(ARGV.shift)
  puts JSON.generate("ok" => true, "classification" => classification)
rescue FastlaneCore::Interface::UserError => error
  puts JSON.generate("ok" => false, "error" => error.message)
end
"""

SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
CLANG = shutil.which("clang")
FASTLANE_BIN = shutil.which("fastlane")


@unittest.skipUnless(RUBY, "ruby is not available on this machine")
class SignatureStateTest(unittest.TestCase):
    """The guard must classify, never equate codesign success with an identity."""

    def setUp(self):
        self.temp = tempfile.mkdtemp(prefix="prism-signature-state-")
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.dir = Path(self.temp)
        self.driver = self.dir / "signature_driver.rb"
        self.driver.write_text(SIGNATURE_DRIVER)

    def run_guard(self, target: Path, *, path: str = SYSTEM_PATH) -> dict:
        completed = subprocess.run(
            [RUBY, str(self.driver), str(FASTLANE), str(target)],
            capture_output=True, text=True, env={**os.environ, "PATH": path},
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    @unittest.skipUnless(CLANG, "clang is not available on this machine")
    def compile_binary(self, *, adhoc: bool) -> Path:
        source = self.dir / "mini.c"
        source.write_text("int main(void){return 0;}\n")
        target = self.dir / ("adhoc-mini" if adhoc else "unsigned-mini")
        arguments = ["clang", "-O0"]
        if not adhoc:
            arguments.append("-Wl,-no_adhoc_codesign")
        subprocess.run([*arguments, "-o", str(target), str(source)], check=True, capture_output=True)
        return target

    def fake_codesign(self, *, stdout: str = "", stderr: str = "", status: int = 0) -> Path:
        directory = self.dir / f"fake-codesign-{abs(hash((stdout, stderr, status)))}"
        directory.mkdir(exist_ok=True)
        (directory / "stdout.txt").write_text(stdout)
        (directory / "stderr.txt").write_text(stderr)
        script = directory / "codesign"
        script.write_text(
            "#!/bin/sh\n"
            'here="$(dirname "$0")"\n'
            'cat "$here/stdout.txt"\n'
            'cat "$here/stderr.txt" 1>&2\n'
            f"exit {status}\n"
        )
        script.chmod(0o755)
        return directory

    @unittest.skipUnless(sys.platform == "darwin" and os.uname().machine == "arm64" and CLANG and shutil.which("codesign"), "requires Apple-silicon clang and codesign")
    def test_linker_adhoc_binary_is_accepted_and_classified(self):
        result = self.run_guard(self.compile_binary(adhoc=True))
        self.assertTrue(result["ok"], result)
        classification = result["classification"]
        self.assertEqual(classification["state"], "adhoc")
        self.assertEqual(classification["signature"], "adhoc")
        self.assertEqual(classification["team_identifier"], "not set")
        self.assertEqual(classification["authorities"], [])
        self.assertIn("adhoc", classification["flags"])

    @unittest.skipUnless(sys.platform == "darwin" and CLANG and shutil.which("codesign"), "requires Apple clang and codesign")
    def test_genuinely_unsigned_binary_is_accepted_as_unsigned(self):
        result = self.run_guard(self.compile_binary(adhoc=False))
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["classification"]["state"], "unsigned")

    def test_identity_signature_is_refused_and_named(self):
        directory = self.fake_codesign(stderr=(
            "Authority=Developer ID Application: Prism Plural (GF2W9X3Y6L)\n"
            "Authority=Developer ID Certification Authority\n"
            "TeamIdentifier=GF2W9X3Y6L\n"
            "Signature=adhoc\n"
        ))
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("signed by an identity", result["error"])
        self.assertIn("Prism Plural", result["error"])
        self.assertIn("GF2W9X3Y6L", result["error"])
        self.assertIn("did not take effect", result["error"])

    def test_unrecognised_signed_metadata_is_refused(self):
        directory = self.fake_codesign(stderr="Signature=someday-new-format\nTeamIdentifier=not set\n")
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("not understood", result["error"])
        self.assertIn("refused", result["error"])

    def test_inspection_error_is_not_treated_as_unsigned(self):
        directory = self.fake_codesign(stderr="csops: operation not permitted\n", status=1)
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("inspection error as unsigned", result["error"])
        self.assertIn("operation not permitted", result["error"])

    def test_the_documented_not_signed_line_is_accepted_for_this_path(self):
        target = self.dir / "unsigned.app"
        directory = self.fake_codesign(
            stderr=f"{target}: code object is not signed at all\n", status=1
        )
        result = self.run_guard(target, path=f"{directory}:{SYSTEM_PATH}")
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["classification"]["state"], "unsigned")

    def test_a_not_signed_line_for_another_path_is_refused(self):
        directory = self.fake_codesign(stderr="/tmp/x: code object is not signed at all\n", status=1)
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("inspection error as unsigned", result["error"])

    def test_a_mixed_not_signed_line_and_error_is_refused(self):
        target = self.dir / "mixed.app"
        directory = self.fake_codesign(
            stderr=f"{target}: code object is not signed at all\ncsops: operation not permitted\n",
            status=1,
        )
        result = self.run_guard(target, path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("inspection error as unsigned", result["error"])

    def test_not_signed_output_with_a_zero_exit_is_refused(self):
        target = self.dir / "weird.app"
        directory = self.fake_codesign(
            stderr=f"{target}: code object is not signed at all\n", status=0
        )
        result = self.run_guard(target, path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("not understood", result["error"])

    def test_missing_team_identifier_is_not_accepted_as_adhoc(self):
        directory = self.fake_codesign(stderr="Signature=adhoc\nCodeDirectory v=20400 flags=0x2(adhoc)\n")
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("not understood", result["error"])

    def test_empty_authority_marker_with_adhoc_is_refused(self):
        directory = self.fake_codesign(
            stderr="Signature=adhoc\nTeamIdentifier=not set\nAuthority=\n"
        )
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("signed by an identity", result["error"])

    def test_authority_after_the_metadata_budget_is_refused_as_truncated(self):
        filler = "\n".join(["TeamIdentifier=not set"] * 600)
        directory = self.fake_codesign(
            stderr=f"Signature=adhoc\n{filler}\nAuthority=Developer ID Application: Someone\n"
        )
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("exceeded the", result["error"])
        self.assertIn("partial inspection", result["error"])

    def test_conflicting_signature_metadata_is_refused(self):
        directory = self.fake_codesign(
            stderr="Signature=adhoc\nSignature=other\nTeamIdentifier=not set\n"
        )
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("conflicting signature metadata", result["error"])
        self.assertIn("Signature", result["error"])

    def test_conflicting_team_metadata_is_refused(self):
        directory = self.fake_codesign(
            stderr="Signature=adhoc\nTeamIdentifier=not set\nTeamIdentifier=GF2W9X3Y6L\n"
        )
        result = self.run_guard(self.dir / "whatever.app", path=f"{directory}:{SYSTEM_PATH}")
        self.assertFalse(result["ok"])
        self.assertIn("conflicting signature metadata", result["error"])
        self.assertIn("TeamIdentifier", result["error"])


@unittest.skipUnless(RUBY, "ruby is not available on this machine")
class UiNamespaceTest(unittest.TestCase):
    """The real gem has no top-level UI; only FastlaneCore::UI exists."""

    def test_ci_signing_has_no_bare_ui_reference(self):
        source = CI_SIGNING.read_text()
        self.assertIsNone(re.search(r"(?<!FastlaneCore::)\bUI\.", source))
        self.assertIn("FastlaneCore::UI.user_error!", source)

    def test_a_required_file_using_bare_ui_raises_name_error(self):
        with tempfile.TemporaryDirectory() as directory:
            library = Path(directory) / "bare_ui_lib.rb"
            library.write_text("module BareUiLib\n  module_function\n\n  def go\n    UI.user_error!('x')\n  end\nend\n")
            driver = Path(directory) / "driver.rb"
            driver.write_text(
                "module FastlaneCore\n  module Interface\n    class UserError < StandardError; end\n  end\n"
                "  module UI\n    def self.user_error!(m)\n      raise FastlaneCore::Interface::UserError, m.to_s\n    end\n  end\nend\n"
                f"require {json.dumps(str(library))}\n"
                "begin\n  BareUiLib.go\n  puts 'NO ERROR'\nrescue NameError => error\n  puts error.class\nend\n"
            )
            completed = subprocess.run([RUBY, str(driver)], capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("NameError", completed.stdout)


@unittest.skipUnless(FASTLANE_BIN and RUBY, "fastlane is not installed on this machine")
class RealGemErrorPathTest(unittest.TestCase):
    """Drive the actual gem: FastlaneCore::UI works from a required file."""

    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.mkdtemp(prefix="prism-fastlane-ui-")
        fastlane_dir = Path(cls.directory) / "fastlane"
        fastlane_dir.mkdir()
        (Path(cls.directory) / "helper_lib.rb").write_text(
            "module HelperLib\n  module_function\n\n"
            "  def boom\n    FastlaneCore::UI.user_error!('helper says no')\n  end\nend\n"
        )
        (fastlane_dir / "Fastfile").write_text(
            "default_platform(:ios)\nrequire_relative \"../helper_lib\"\n\n"
            "platform :ios do\n  lane :boom do\n    HelperLib.boom\n  end\nend\n"
        )

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(getattr(cls, "directory", ""), ignore_errors=True)

    def test_required_file_error_path_reaches_the_real_gem_ui(self):
        completed = subprocess.run(
            [FASTLANE_BIN, "boom"], cwd=self.directory, capture_output=True, text=True, timeout=180,
            env={**os.environ, "FASTLANE_SKIP_UPDATE_CHECK": "1", "FASTLANE_HIDE_CHANGELOG": "1",
                 "FASTLANE_DISABLE_ANALYTICS": "1", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8"},
        )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("helper says no", completed.stderr + completed.stdout)
        self.assertNotIn("uninitialized constant", completed.stderr + completed.stdout)


SEED_DRIVER = r"""
$LOAD_PATH.unshift ARGV.shift
require "json"
module FastlaneCore
  module Interface
    class UserError < StandardError; end
  end
  module UI
    def self.user_error!(message)
      raise FastlaneCore::Interface::UserError, message.to_s
    end
    def self.important(message)
      File.write(ENV["SEED_LOG"], "important: #{message}\n", mode: "a")
    end
    def self.success(_message); end
    def self.message(_message); end
  end
end
require "ci_signing"
begin
  result = CISigning.seed_archive_adhoc_entitlements!(ARGV[0], entitlements_path: ARGV[1])
  puts JSON.generate("ok" => true, "result" => result)
rescue FastlaneCore::Interface::UserError => error
  puts JSON.generate("ok" => false, "error" => error.message)
end
"""


@unittest.skipUnless(RUBY, "ruby is not available on this machine")
class ArchiveAdhocSeedTest(unittest.TestCase):
    """The seed signs nested code inside-out, never --deep, and refuses without App Attest."""

    def setUp(self):
        self.temp = tempfile.mkdtemp(prefix="prism-adhoc-seed-")
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.dir = Path(self.temp)
        self.driver = self.dir / "seed_driver.rb"
        self.driver.write_text(SEED_DRIVER)
        self.log = self.dir / "calls.log"
        self.log.touch()
        self.app = self.dir / "Runner.app"
        (self.app / "Frameworks" / "App.framework").mkdir(parents=True)
        (self.app / "Frameworks" / "Flutter.framework").mkdir(parents=True)
        (self.app / "Frameworks" / "libplugin.dylib").parent.mkdir(parents=True, exist_ok=True)
        (self.app / "Frameworks" / "libplugin.dylib").write_bytes(b"binary")
        self.entitlements = self.dir / "Runner.entitlements"
        self.write_entitlements("production")
        self.bin = self.dir / "bin"
        self.bin.mkdir()
        self.fake_tools()

    def write_entitlements(self, app_attest):
        payload = {"com.apple.developer.devicecheck.appattest-environment": app_attest} if app_attest else {}
        self.entitlements.write_bytes(plistlib.dumps(payload, fmt=plistlib.FMT_XML))

    def fake_tools(self):
        codesign = self.bin / "codesign"
        codesign.write_text(
            "#!/bin/sh\n"
            f'printf "%s\\n" "$*" >> {self.log}\n'
            'last=""\n'
            'for a in "$@"; do last="$a"; done\n'
            'case "$*" in\n'
            '  *"-d --entitlements"*)\n'
            f'    cat "{self.entitlements}"\n'
            '    ;;\n'
            'esac\n'
            "exit 0\n"
        )
        codesign.chmod(0o755)
        plutil = self.bin / "plutil"
        plutil.write_text(
            "#!/bin/sh\n"
            'last=""\n'
            'for a in "$@"; do last="$a"; done\n'
            f'exec {sys.executable} -c "import plistlib,sys,json;'
            "print(json.dumps(plistlib.loads(open(sys.argv[1],'rb').read()),default=str))\" \"$last\"\n"
        )
        plutil.chmod(0o755)

    def run_seed(self) -> dict:
        completed = subprocess.run(
            [RUBY, str(self.driver), str(FASTLANE), str(self.app), str(self.entitlements)],
            capture_output=True, text=True,
            env={**os.environ, "PATH": f"{self.bin}:{os.environ.get('PATH','')}", "SEED_LOG": str(self.dir / "seed.log")},
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def seed_calls(self):
        return [line for line in self.log.read_text().splitlines() if "--sign" in line]

    def test_nested_code_is_signed_inside_out_before_the_app(self):
        result = self.run_seed()
        self.assertTrue(result["ok"], result)
        self.assertTrue(result["result"]["seeded"])
        self.assertEqual(result["result"]["app_attest_environment"], "production")
        calls = self.seed_calls()
        self.assertEqual(len(calls), 4, calls)  # two frameworks, one dylib, then the app
        self.assertTrue(calls[0].endswith("App.framework"))
        self.assertTrue(calls[1].endswith("Flutter.framework"))
        self.assertTrue(calls[2].endswith("libplugin.dylib"))
        self.assertTrue(calls[3].endswith("Runner.app"), calls[3])
        # The app is the only call carrying entitlements, and nothing uses --deep.
        self.assertEqual([call for call in calls if "--entitlements" in call], [calls[3]])
        for call in calls:
            self.assertNotIn("--deep", call)
            self.assertIn("--sign -", call)

    def test_app_extension_is_refused_before_any_signing(self):
        (self.app / "PlugIns" / "Widget.appex").mkdir(parents=True)
        result = self.run_seed()
        self.assertFalse(result["ok"])
        self.assertIn("app extensions", result["error"])
        self.assertIn("Nothing was signed", result["error"])
        self.assertEqual(self.seed_calls(), [], "no codesign call may happen before the refusal")

    def test_nested_frameworks_are_signed_before_their_enclosing_framework(self):
        shutil.rmtree(self.app)
        (self.app / "Frameworks" / "Outer.framework" / "Frameworks").mkdir(parents=True)
        (self.app / "Frameworks" / "Outer.framework" / "Frameworks" / "Inner.framework").mkdir()
        (self.app / "Frameworks" / "Outer.framework" / "Frameworks" / "Lib.dylib").write_bytes(b"bin")
        (self.app / "Frameworks" / "z.dylib").write_bytes(b"bin")
        result = self.run_seed()
        self.assertTrue(result["ok"], result)
        calls = self.seed_calls()
        order = [call.split()[-1] for call in calls]
        self.assertEqual(
            order,
            [
                str(self.app / "Frameworks" / "Outer.framework" / "Frameworks" / "Inner.framework"),
                str(self.app / "Frameworks" / "Outer.framework" / "Frameworks" / "Lib.dylib"),
                str(self.app / "Frameworks" / "Outer.framework"),
                str(self.app / "Frameworks" / "z.dylib"),
                str(self.app),
            ],
            order,
        )
        self.assertEqual(result["result"]["nested"], 4)
        # Still exactly one entitlements-bearing call, and it is the app.
        self.assertEqual([call for call in calls if "--entitlements" in call], [calls[-1]])

    def test_symlinked_nested_item_is_skipped_not_signed(self):
        target = self.dir / "outside.dylib"
        target.write_bytes(b"bin")
        (self.app / "Frameworks" / "linked.dylib").symlink_to(target)
        result = self.run_seed()
        self.assertTrue(result["ok"], result)
        self.assertNotIn(
            str(self.app / "Frameworks" / "linked.dylib"), [call.split()[-1] for call in self.seed_calls()]
        )
        skipped = result["result"]["skipped_symlinks"]
        self.assertEqual(len(skipped), 1, skipped)
        self.assertTrue(skipped[0].endswith("linked.dylib"))
        self.assertTrue(target.exists(), "the symlink target must not be touched")

    def test_missing_app_attest_is_refused_before_any_signing(self):
        self.write_entitlements(None)
        result = self.run_seed()
        self.assertFalse(result["ok"])
        self.assertIn("must carry", result["error"])
        self.assertEqual(self.seed_calls(), [])

    def test_development_app_attest_is_refused(self):
        self.write_entitlements("development")
        result = self.run_seed()
        self.assertFalse(result["ok"])
        self.assertIn("production", result["error"])
        self.assertEqual(self.seed_calls(), [])

    def test_a_missing_entitlements_file_is_refused(self):
        self.entitlements.unlink()
        result = self.run_seed()
        self.assertFalse(result["ok"])
        self.assertIn("source entitlements are missing", result["error"])


class IosStoreLaneShapeTest(unittest.TestCase):
    """Static contract for the Option B lane: unsigned archive, seed, standard export, verify."""

    def lane(self) -> str:
        source = FASTFILE.read_text()
        start = source.index("lane :ci_ios_store do")
        end = source.index("platform :mac do", start)
        return source[start:end]

    def test_archive_disables_signing_and_names_no_profile(self):
        body = self.lane()
        for expected in ("CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY="):
            self.assertIn(expected, body)
        self.assertNotIn("PROVISIONING_PROFILE_SPECIFIER", body)
        self.assertNotIn("CODE_SIGN_STYLE=Manual", body)
        self.assertNotIn("allowProvisioningUpdates", body)

    def test_seed_sits_between_archive_and_export(self):
        body = self.lane()
        archive = body.index("xcodebuild archive")
        seed = body.index("seed_archive_adhoc_entitlements!")
        export = body.index("xcodebuild -exportArchive")
        verify = body.index("verify_ios_store_ipa")
        self.assertLess(archive, seed)
        self.assertLess(seed, export)
        self.assertLess(export, verify)

    def test_seed_uses_the_source_entitlements_file(self):
        self.assertIn(
            'entitlements_path: File.join(root, "ios", "Runner", "Runner.entitlements")',
            self.lane(),
        )

    def test_export_keeps_the_app_only_profile_map(self):
        body = self.lane()
        self.assertIn("write_export_options_plist", body)
        self.assertIn("bundle_id: bundle_id", body)
        self.assertIn("provisioningProfiles", CI_SIGNING.read_text())

    def test_final_verification_still_requires_app_attest_and_keychain_policy(self):
        verifier = CI_SIGNING.read_text()
        self.assertIn("validate_ios_store_profile!", verifier)
        self.assertIn("APP_ATTEST_ENTITLEMENT", verifier)
        self.assertIn("keychain-access-groups", verifier)
        self.assertIn("get-task-allow", verifier)
        # The seed never manufactures an explicit keychain-sharing claim.
        seed = verifier.split("def seed_archive_adhoc_entitlements!", 1)[1].split("\n  end", 1)[0]
        self.assertNotIn("keychain-access-groups", seed)


@unittest.skipUnless(
    RUBY and sys.platform == "darwin" and shutil.which("codesign") and shutil.which("clang") and shutil.which("plutil"),
    "requires Darwin codesign, clang and plutil",
)
class RealCodesignSeedTest(unittest.TestCase):
    """The real seed CLI on a synthetic iOS bundle: ad-hoc, entitlements preserved."""

    def setUp(self):
        self.temp = tempfile.mkdtemp(prefix="prism-real-seed-")
        self.addCleanup(shutil.rmtree, self.temp, True)
        self.dir = Path(self.temp)
        self.app = self.dir / "Runner.app"
        (self.app / "Frameworks").mkdir(parents=True)
        (self.app / "Info.plist").write_text(
            '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
            '"http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>'
            "<key>CFBundleExecutable</key><string>Runner</string>"
            "<key>CFBundleIdentifier</key><string>com.prismplural.prism</string></dict></plist>"
        )
        source = self.dir / "m.c"
        source.write_text("int main(void){return 0;}\n")
        subprocess.run(["clang", "-O0", "-o", str(self.app / "Runner"), str(source)], check=True, capture_output=True)
        subprocess.run(
            ["clang", "-O0", "-dynamiclib", "-o", str(self.app / "Frameworks" / "libplugin.dylib"), str(source)],
            check=True, capture_output=True,
        )
        self.entitlements = self.dir / "Runner.entitlements"
        self.entitlements.write_bytes(plistlib.dumps(
            {"com.apple.developer.devicecheck.appattest-environment": "production"}, fmt=plistlib.FMT_XML
        ))
        self.driver = self.dir / "seed_driver.rb"
        self.driver.write_text(SEED_DRIVER)

    def run_seed(self) -> dict:
        completed = subprocess.run(
            [RUBY, str(self.driver), str(FASTLANE), str(self.app), str(self.entitlements)],
            capture_output=True, text=True,
            env={**os.environ, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "SEED_LOG": str(self.dir / "seed.log")},
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_real_seed_produces_an_adhoc_app_with_app_attest(self):
        result = self.run_seed()
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["result"]["app_attest_environment"], "production")
        self.assertEqual(result["result"]["nested"], 1)
        verify = subprocess.run(["codesign", "--verify", "--strict", str(self.app)], capture_output=True, text=True)
        self.assertEqual(verify.returncode, 0, verify.stderr)
        shown = subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(self.app)], capture_output=True, text=True
        ).stdout
        self.assertIn("com.apple.developer.devicecheck.appattest-environment", shown)
        self.assertIn("production", shown)

    def test_real_seed_refuses_without_app_attest(self):
        self.entitlements.write_bytes(plistlib.dumps({"get-task-allow": False}, fmt=plistlib.FMT_XML))
        result = self.run_seed()
        self.assertFalse(result["ok"])
        self.assertIn("must carry", result["error"])
        # Nothing was signed: the app still carries only the linker signature.
        shown = subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(self.app)], capture_output=True, text=True
        ).stdout
        self.assertNotIn("appattest-environment", shown)
