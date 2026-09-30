require "minitest/autorun"
require_relative "../../fastlane/macos_signing"

class MacOSSigningTest < Minitest::Test
  TEAM = "TEST123456"
  BUNDLE = "com.example.prism"
  APP_ID = "#{TEAM}.#{BUNDLE}"

  def setup
    @claims = {
      "com.apple.application-identifier" => APP_ID,
      "com.apple.developer.team-identifier" => TEAM,
      "keychain-access-groups" => [APP_ID],
    }
    @profile = {
      "ProvisionsAllDevices" => true,
      "Platform" => ["OSX"],
      "TeamIdentifier" => [TEAM],
      "ExpirationDate" => Time.now + 3600,
      "DeveloperCertificates" => ["fixture-certificate"],
      "Entitlements" => @claims.merge("keychain-access-groups" => ["#{TEAM}.*"]),
    }
  end

  def validate
    MacOSSigning.validate!(@profile, @claims, bundle_id: BUNDLE, team_id: TEAM,
      certificate_sha1: Digest::SHA1.hexdigest("fixture-certificate"))
  end

  def test_accepts_matching_developer_id_profile
    assert validate
  end

  def test_rejects_released_five_key_configuration
    @claims = { "com.apple.security.app-sandbox" => true }
    assert_raises(ArgumentError) { validate }
  end

  def test_rejects_empty_keychain_group_array
    @claims["keychain-access-groups"] = []
    assert_raises(ArgumentError) { validate }
  end

  def test_rejects_development_and_store_profiles
    @profile.delete("ProvisionsAllDevices")
    assert_raises(ArgumentError) { validate }
    @profile["ProvisionsAllDevices"] = true
    @profile["ProvisionedDevices"] = ["fixture-device"]
    assert_raises(ArgumentError) { validate }
  end

  def test_rejects_wrong_team_app_and_keychain_group
    @profile["Entitlements"]["com.apple.application-identifier"] = "#{TEAM}.com.other.app"
    assert_raises(ArgumentError) { validate }
    @profile["Entitlements"]["com.apple.application-identifier"] = APP_ID
    @profile["TeamIdentifier"] = ["OTHERTEAM"]
    assert_raises(ArgumentError) { validate }
    @profile["TeamIdentifier"] = [TEAM]
    @claims["keychain-access-groups"] << "OTHERTEAM.com.other.app"
    assert_raises(ArgumentError) { validate }
  end

  def test_rejects_expired_profile_and_unauthorized_certificate
    @profile["ExpirationDate"] = Time.now - 1
    assert_raises(ArgumentError) { validate }
    @profile["ExpirationDate"] = Time.now + 3600
    @profile["DeveloperCertificates"] = ["other-certificate"]
    assert_raises(ArgumentError) { validate }
  end

  def test_rejects_debug_attachment
    @claims["com.apple.security.get-task-allow"] = true
    assert_raises(ArgumentError) { validate }
  end

  def test_rejects_unresolved_claims
    @claims["keychain-access-groups"] << "$(AppIdentifierPrefix)com.example.prism"
    assert_raises(ArgumentError) { validate }
  end

  def test_entitlement_plist_round_trip
    @claims["com.apple.security.app-sandbox"] = true
    assert_equal @claims, MacOSSigning.parse_plist(MacOSSigning.plist(@claims))
  end
end
