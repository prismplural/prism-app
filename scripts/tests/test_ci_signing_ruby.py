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
    CISigning.validate_ios_store_profile!(
      profile, value["entitlements"],
      team_id: value["team_id"], bundle_id: value["bundle_id"],
      certificate_sha1: value["certificate_sha1"]
    )
    { "ok" => true, "error" => nil }
  rescue StandardError => error
    { "ok" => false, "error" => "#{error.class}: #{error.message}" }
  end
end
puts JSON.generate("results" => results)
"""


def valid_profile() -> dict:
    return {
        "Name": "Prism App Store",
        "UUID": "11111111-2222-3333-4444-555555555555",
        "TeamIdentifier": [TEAM],
        "Platform": ["iOS"],
        "ExpirationDate": 4070908800,  # 2099-01-01
        "Entitlements": {
            "application-identifier": APP_ID,
            "com.apple.developer.team-identifier": TEAM,
            "keychain-access-groups": [APP_ID, f"{TEAM}.*"],
            "get-task-allow": False,
            "com.apple.developer.devicecheck.appattest-environment": "production",
        },
    }


def valid_entitlements() -> dict:
    return {
        "application-identifier": APP_ID,
        "com.apple.developer.team-identifier": TEAM,
        "keychain-access-groups": [APP_ID],
        "get-task-allow": False,
        "com.apple.developer.devicecheck.appattest-environment": "production",
    }


def case(profile=None, entitlements=None, *, certificate_sha1=CERT_SHA1, bundle=BUNDLE) -> dict:
    return {
        "profile": profile if profile is not None else valid_profile(),
        "entitlements": entitlements if entitlements is not None else valid_entitlements(),
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
    """Each case is a distinct production failure the validator must refuse."""

    @classmethod
    def setUpClass(cls):
        profile = valid_profile()
        entitlements = valid_entitlements()
        cls.names = [
            "valid",
            "development",
            "missing_appattest",
            "development_appattest",
            "profile_without_appattest",
            "missing_keychain_groups",
            "empty_keychain_groups",
            "no_default_keychain_group",
            "unauthorized_keychain_group",
            "enterprise_all_devices",
            "device_bound",
            "expired",
            "wrong_team",
            "unauthorized_certificate",
            "profile_for_other_bundle",
        ]
        cls.cases = [
            case(),
            case(entitlements={**entitlements, "get-task-allow": True}),
            case(entitlements=without(entitlements, "com.apple.developer.devicecheck.appattest-environment")),
            case(entitlements={**entitlements,
                               "com.apple.developer.devicecheck.appattest-environment": "development"}),
            case(profile={**profile,
                          "Entitlements": without(profile["Entitlements"],
                                                  "com.apple.developer.devicecheck.appattest-environment")}),
            case(entitlements=without(entitlements, "keychain-access-groups")),
            case(entitlements={**entitlements, "keychain-access-groups": []}),
            case(entitlements={**entitlements, "keychain-access-groups": [f"{TEAM}.some.other.group"]}),
            case(entitlements={**entitlements, "keychain-access-groups": [APP_ID, "com.someoneelse.group"]}),
            case(profile={**profile, "ProvisionsAllDevices": True}),
            case(profile={**profile, "ProvisionedDevices": ["00008030-0000"]}),
            case(profile={**profile, "ExpirationDate": 1000000000}),
            case(profile={**profile, "TeamIdentifier": ["OTHERTEAM1"]}),
            case(certificate_sha1="0" * 40),
            case(profile={**profile,
                          "Entitlements": {**profile["Entitlements"],
                                           "application-identifier": f"{TEAM}.com.example.other"}}),
        ]
        cls.by_name = dict(zip(cls.names, run_validator(cls.cases), strict=True))

    def assert_rejected(self, name: str, fragment: str) -> None:
        result = self.by_name[name]
        self.assertFalse(result["ok"], f"{name} should have been rejected")
        self.assertIn(fragment, result["error"], f"{name}: unexpected message")

    def test_valid_profile_is_accepted(self):
        self.assertTrue(self.by_name["valid"]["ok"], self.by_name["valid"]["error"])

    def test_app_attest_environment_is_required(self):
        self.assert_rejected("missing_appattest", "missing the App Attest entitlement")

    def test_development_app_attest_is_rejected(self):
        self.assert_rejected("development_appattest", "not production")

    def test_profile_must_authorize_app_attest(self):
        self.assert_rejected(
            "profile_without_appattest", "does not authorize the production App Attest environment"
        )

    def test_default_keychain_group_is_required(self):
        self.assert_rejected("missing_keychain_groups", "no keychain-access-groups")
        self.assert_rejected("empty_keychain_groups", "no keychain-access-groups")
        self.assert_rejected("no_default_keychain_group", "missing its default keychain group")

    def test_profile_must_authorize_every_keychain_group(self):
        self.assert_rejected("unauthorized_keychain_group", "does not authorize keychain access group")

    def test_enterprise_all_devices_profile_is_rejected(self):
        self.assert_rejected("enterprise_all_devices", "enterprise rather than App Store")

    def test_development_shapes_are_rejected(self):
        self.assert_rejected("development", "get-task-allow")
        self.assert_rejected("device_bound", "device-bound")

    def test_profile_lifetime_team_and_certificate_are_enforced(self):
        self.assert_rejected("expired", "expired")
        self.assert_rejected("wrong_team", "team does not match")
        self.assert_rejected("unauthorized_certificate", "does not authorize the signing certificate")

    def test_profile_for_another_bundle_is_rejected(self):
        self.assert_rejected("profile_for_other_bundle", "does not authorize app identifier")


@unittest.skipUnless(RUBY, "ruby is not available on this machine")
class SignatureVerificationTest(unittest.TestCase):
    """The verifier must verify deeply but never sign with --deep."""

    def source(self) -> str:
        return CI_SIGNING.read_text()

    def test_deep_strict_verification_is_used(self):
        self.assertIn('"codesign", "--verify", "--deep", "--strict"', self.source())

    def test_deep_is_never_combined_with_signing(self):
        for line in self.source().splitlines():
            if '"--deep"' in line:
                self.assertIn("--verify", line, f"--deep outside verification: {line.strip()}")

    def test_receipt_records_the_actual_app_attest_environment(self):
        text = self.source()
        self.assertIn('"app_attest_environment" => entitlements[APP_ATTEST_ENTITLEMENT]', text)
        self.assertIn('"keychain_access_groups" => Array(entitlements["keychain-access-groups"])', text)
        self.assertNotIn('"verified" => "distribution signature, production entitlements', text)
