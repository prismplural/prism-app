require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

require_relative "macos_signing"

# Build-only helpers for the hosted release pipeline.
#
# These lanes never upload: no App Store Connect submission, no TestFlight
# distribution, no GitHub release asset. They exist so the hosted workflow can
# build and *verify* the same signed artifacts the owner's Mac produced, and
# they refuse to touch signing state outside GitHub Actions.
module CISigning
  module_function

  def require_ci!(action)
    return if ENV["GITHUB_ACTIONS"].to_s.strip.casecmp("true").zero?

    UI.user_error!(
      "refusing to #{action}: hosted release lanes only run inside GitHub Actions " \
      "(GITHUB_ACTIONS=true). Nothing was changed."
    )
  end

  def env!(name)
    value = ENV[name].to_s.strip
    UI.user_error!("#{name} is not set") if value.empty?
    value
  end

  # Private temp file written by scripts/release_ci.py: the beta registration
  # token reaches Flutter as a file, never as a CLI literal.
  def dart_define_flag
    path = env!("PRISM_CI_DART_DEFINES_FILE")
    UI.user_error!("dart defines file is missing: #{path}") unless File.file?(path)
    "--dart-define-from-file=#{path}"
  end

  def artifact_dir
    dir = env!("PRISM_CI_ARTIFACT_DIR")
    FileUtils.mkdir_p(dir)
    dir
  end

  def state_dir
    dir = env!("PRISM_CI_STATE_DIR")
    FileUtils.mkdir_p(dir)
    dir
  end

  def write_signing_facts(facts)
    path = File.join(state_dir, "signing-facts.json")
    File.write(path, JSON.pretty_generate(facts) + "\n")
    path
  end

  # ------------------------------------------------------------------------
  # process helpers

  def capture!(*argv)
    stdout, stderr, status = Open3.capture3(*argv.map(&:to_s))
    unless status.success?
      tail = (stderr.lines.last(20) + stdout.lines.last(5)).join.strip
      UI.user_error!("command failed (#{status.exitstatus}): #{argv.join(' ')}\n#{tail}")
    end
    stdout
  end

  def plist_json(path)
    JSON.parse(capture!("plutil", "-convert", "json", "-o", "-", path))
  end

  def provisioning_profile(path)
    MacOSSigning.parse_plist(capture!("security", "cms", "-D", "-i", path))
  end

  def entitlements(app_path)
    stdout, stderr, status = Open3.capture3("codesign", "-d", "--entitlements", ":-", app_path.to_s)
    UI.user_error!("could not read entitlements from #{app_path}:\n#{stderr}") unless status.success?
    xml = stdout.strip
    return {} if xml.empty?

    Dir.mktmpdir("prism-entitlements") do |dir|
      path = File.join(dir, "entitlements.plist")
      File.write(path, xml)
      plist_json(path)
    end
  end

  def codesign_authorities(app_path)
    _stdout, stderr, status = Open3.capture3("codesign", "-dvvv", app_path.to_s)
    UI.user_error!("could not read the signature of #{app_path}:\n#{stderr}") unless status.success?
    stderr.scan(/^Authority=(.*)$/).flatten.map(&:strip)
  end

  def signing_certificate_sha1(app_path)
    Dir.mktmpdir("prism-signer") do |dir|
      prefix = File.join(dir, "signer")
      capture!("codesign", "-d", "--extract-certificates=#{prefix}", app_path)
      der = "#{prefix}0"
      UI.user_error!("could not extract the signing certificate from #{app_path}") unless File.file?(der)
      Digest::SHA1.hexdigest(File.binread(der)).upcase
    end
  end

  # Xcode 15+ renamed the export method; Xcode 26 rejects the old spelling.
  # The bundle identifier of the built application, read from the Release build
  # settings instead of the first PRODUCT_BUNDLE_IDENTIFIER in the pbxproj
  # (RunnerTests also carries one, and order is not a contract).
  def bundle_identifier(workspace:, scheme:, configuration: "Release", destination: nil)
    base = ["xcodebuild", "-showBuildSettings", "-workspace", workspace,
            "-scheme", scheme, "-configuration", configuration]
    base += ["-destination", destination] if destination
    begin
      payload = JSON.parse(capture!(*base, "-json"))
      entries = payload.is_a?(Hash) ? [payload] : Array(payload)
      entry = entries.find { |candidate| candidate["target"] == scheme } || entries.first
      value = entry && entry.dig("buildSettings", "PRODUCT_BUNDLE_IDENTIFIER").to_s.strip
    rescue JSON::ParserError
      value = capture!(*base).scan(/^\s*PRODUCT_BUNDLE_IDENTIFIER = (\S+)/).flatten.first.to_s.strip
    end
    UI.user_error!("could not resolve PRODUCT_BUNDLE_IDENTIFIER for #{scheme} in #{configuration}") if value.to_s.empty?
    value
  end

  def app_store_export_method
    version = capture!("xcodebuild", "-version")[/Xcode (\d+)/, 1].to_i
    version >= 15 ? "app-store-connect" : "app-store"
  end

  # Export options carry a nested provisioningProfiles dictionary, so they are
  # written as JSON and converted by plutil rather than through the flat
  # entitlement plist helper. Nothing here is secret.
  def write_export_options_plist(path, method:, team_id:, bundle_id:, profile_name:, signing_certificate: nil)
    options = {
      "method" => method,
      "signingStyle" => "manual",
      "teamID" => team_id,
      # Manual signing resolved narrowly: only the application bundle is named;
      # Pods frameworks are signed with this identity, not provisioned blindly.
      "provisioningProfiles" => { bundle_id => profile_name },
      "manageAppVersionAndBuildNumber" => false,
      "uploadSymbols" => false,
      "destination" => "export",
    }
    options["signingCertificate"] = signing_certificate if signing_certificate
    json_path = "#{path}.json"
    File.write(json_path, JSON.generate(options))
    begin
      capture!("plutil", "-convert", "xml1", "-o", path, json_path)
    ensure
      FileUtils.rm_f(json_path)
    end
    path
  end

  # ------------------------------------------------------------------------
  # verification

  # An App Store export must carry exactly one application bundle: a second one
  # would mean a target other than Runner was provisioned.
  def single_application!(applications_dir)
    apps = Dir[File.join(applications_dir, "*.app")]
    UI.user_error!("expected exactly one .app in the archive, found #{apps.length}") unless apps.length == 1
    apps.first
  end

  # App Attest must ship in the production environment; a development value
  # silently makes attestation fail on real devices.
  APP_ATTEST_ENTITLEMENT = "com.apple.developer.devicecheck.appattest-environment"

  def validate_ios_store_profile!(profile, app_entitlements, team_id:, bundle_id:, certificate_sha1:)
    errors = []
    allowed = profile["Entitlements"] || {}
    app_id = "#{team_id}.#{bundle_id}"
    errors << "profile is device-bound, so it is not an App Store profile" if profile.key?("ProvisionedDevices")
    if profile["ProvisionsAllDevices"] == true
      errors << "profile provisions all devices, so it is an enterprise rather than App Store profile"
    end
    errors << "profile is not an iOS profile" unless Array(profile["Platform"]).include?("iOS")
    errors << "profile team does not match" unless Array(profile["TeamIdentifier"]).include?(team_id)
    expiry = profile["ExpirationDate"]
    errors << "profile is expired or has no expiration" unless expiry.is_a?(Time) && expiry > Time.now
    unless MacOSSigning.authorizes?(allowed["application-identifier"], app_id)
      errors << "profile does not authorize app identifier #{app_id}"
    end
    errors << "app identifier claim does not match" unless app_entitlements["application-identifier"] == app_id
    errors << "app team claim does not match" unless app_entitlements["com.apple.developer.team-identifier"] == team_id

    # The default keychain group is not optional: an absent or empty array would
    # otherwise pass this check vacuously and leave the app without its own
    # keychain after install.
    groups = app_entitlements["keychain-access-groups"]
    if !groups.is_a?(Array) || groups.empty?
      errors << "app has no keychain-access-groups entitlement (its default group must be present)"
    elsif !groups.include?(app_id)
      errors << "app is missing its default keychain group #{app_id}"
    else
      groups.each do |claim|
        next if Array(allowed["keychain-access-groups"]).any? { |pattern| MacOSSigning.authorizes?(pattern, claim) }

        errors << "profile does not authorize keychain access group #{claim.inspect}"
      end
    end

    app_attest = app_entitlements[APP_ATTEST_ENTITLEMENT]
    if app_attest.to_s.strip.empty?
      errors << "app is missing the App Attest entitlement (#{APP_ATTEST_ENTITLEMENT})"
    elsif app_attest.to_s != "production"
      errors << "app Attest environment is #{app_attest.inspect}, not production"
    elsif !Array(allowed[APP_ATTEST_ENTITLEMENT]).map(&:to_s).include?("production")
      errors << "profile does not authorize the production App Attest environment"
    end
    if app_entitlements["get-task-allow"] == true || allowed["get-task-allow"] == true
      errors << "debug attachment (get-task-allow) is enabled"
    end
    fingerprints = Array(profile["DeveloperCertificates"]).map { |der| Digest::SHA1.hexdigest(der).upcase }
    unless fingerprints.include?(certificate_sha1.to_s.upcase)
      errors << "profile does not authorize the signing certificate"
    end
    raise errors.join("; ") unless errors.empty?
  end

  def verify_ios_store_ipa(ipa_path, version_name:, build_number:, bundle_id:, team_id:)
    facts = { "scheme" => "app-store-distribution", "artifact" => File.basename(ipa_path) }
    Dir.mktmpdir("prism-ios-store-verify") do |dir|
      capture!("ditto", "-x", "-k", ipa_path, dir)
      app_path = File.join(dir, "Payload", "Runner.app")
      UI.user_error!("exported IPA has no Payload/Runner.app") unless Dir.exist?(app_path)

      # Verification only; signing stays explicit elsewhere and never uses --deep.
      capture!("codesign", "--verify", "--deep", "--strict", "--verbose=2", app_path)
      authorities = codesign_authorities(app_path)
      unless authorities.any? { |authority| authority.start_with?("Apple Distribution") }
        UI.user_error!("IPA is not signed with an Apple Distribution identity (found: #{authorities.join(', ')})")
      end
      if authorities.any? { |authority| authority.start_with?("Apple Development") }
        UI.user_error!("IPA carries an Apple Development identity; a personal development certificate must not sign a release")
      end

      entitlements = entitlements(app_path)
      profile_path = File.join(app_path, "embedded.mobileprovision")
      UI.user_error!("exported IPA has no embedded provisioning profile") unless File.file?(profile_path)
      profile = provisioning_profile(profile_path)
      begin
        validate_ios_store_profile!(
          profile, entitlements,
          team_id: team_id, bundle_id: bundle_id,
          certificate_sha1: signing_certificate_sha1(app_path)
        )
      rescue RuntimeError, ArgumentError => error
        UI.user_error!("exported IPA failed distribution validation: #{error.message}")
      end

      info = plist_json(File.join(app_path, "Info.plist"))
      unless info["CFBundleShortVersionString"] == version_name
        UI.user_error!(
          "IPA version #{info['CFBundleShortVersionString'].inspect} does not match pubspec #{version_name.inspect}"
        )
      end
      unless info["CFBundleVersion"].to_s == build_number.to_s
        UI.user_error!("IPA build #{info['CFBundleVersion'].inspect} does not match pubspec #{build_number.inspect}")
      end
      unless info["CFBundleIdentifier"] == bundle_id
        UI.user_error!("IPA bundle identifier #{info['CFBundleIdentifier'].inspect} is not #{bundle_id}")
      end

      facts.merge!(
        "identity" => authorities.first,
        "authority_chain" => authorities,
        "version" => info["CFBundleShortVersionString"],
        "build" => info["CFBundleVersion"],
        "bundle_id" => info["CFBundleIdentifier"],
        "get_task_allow" => entitlements["get-task-allow"] == true,
        "app_attest_environment" => entitlements[APP_ATTEST_ENTITLEMENT],
        "keychain_access_groups" => Array(entitlements["keychain-access-groups"]),
        "entitlement_keys" => entitlements.keys.sort,
        "signing_certificate_sha1" => signing_certificate_sha1(app_path),
        "verified" => "distribution signature verified deep+strict; App Attest production, default keychain " \
                      "group, profile authorization, get-task-allow false and version/build checked"
      )
    end
    facts
  end

  # The macOS project signs with "Apple Development" + Automatic, which a
  # hosted runner has neither an account nor a personal development identity
  # for. Compilation therefore disables signing and this asserts it held, so an
  # implicitly signed payload can never be mistaken for the explicit Developer
  # ID signature that follows.
  def assert_unsigned!(app_path)
    _stdout, _stderr, status = Open3.capture3("codesign", "-dvvv", app_path.to_s)
    return true unless status.success?

    UI.user_error!(
      "#{app_path} is already signed; the compile-time signing override did not take effect, " \
      "so the Developer ID signature would not be the one we verified"
    )
  end

  def universal_archs!(app_path)
    macos_dir = File.join(app_path, "Contents", "MacOS")
    executables = Dir.children(macos_dir).sort
    UI.user_error!("macOS app has no executable in #{macos_dir}") if executables.empty?
    archs = capture!("lipo", "-archs", File.join(macos_dir, executables.first)).split
    missing = []
    missing << "arm64" unless archs.any? { |arch| arch.start_with?("arm64") }
    missing << "x86_64" unless archs.include?("x86_64")
    unless missing.empty?
      UI.user_error!("macOS payload is not universal (missing #{missing.join(', ')}; archs: #{archs.join(', ')})")
    end
    archs
  end
end
