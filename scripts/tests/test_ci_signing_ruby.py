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
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

FASTLANE = Path(__file__).resolve().parents[2] / "fastlane"
CI_SIGNING = FASTLANE / "ci_signing.rb"
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
end
module UI
  def self.user_error!(message)
    raise FastlaneCore::Interface::UserError, message.to_s
  end
  def self.success(_message); end
  def self.important(_message); end
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
