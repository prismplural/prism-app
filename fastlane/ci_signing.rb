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

    FastlaneCore::UI.user_error!(
      "refusing to #{action}: hosted release lanes only run inside GitHub Actions " \
      "(GITHUB_ACTIONS=true). Nothing was changed."
    )
  end

  def env!(name)
    value = ENV[name].to_s.strip
    FastlaneCore::UI.user_error!("#{name} is not set") if value.empty?
    value
  end

  # Private temp file written by scripts/release_ci.py: the beta registration
  # token reaches Flutter as a file, never as a CLI literal.
  def dart_define_flag
    path = env!("PRISM_CI_DART_DEFINES_FILE")
    FastlaneCore::UI.user_error!("dart defines file is missing: #{path}") unless File.file?(path)
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
      FastlaneCore::UI.user_error!("command failed (#{status.exitstatus}): #{argv.join(' ')}\n#{tail}")
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
    FastlaneCore::UI.user_error!("could not read entitlements from #{app_path}:\n#{stderr}") unless status.success?
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
    FastlaneCore::UI.user_error!("could not read the signature of #{app_path}:\n#{stderr}") unless status.success?
    stderr.scan(/^Authority=(.*)$/).flatten.map(&:strip)
  end

  def signing_certificate_sha1(app_path)
    Dir.mktmpdir("prism-signer") do |dir|
      prefix = File.join(dir, "signer")
      capture!("codesign", "-d", "--extract-certificates=#{prefix}", app_path)
      der = "#{prefix}0"
      FastlaneCore::UI.user_error!("could not extract the signing certificate from #{app_path}") unless File.file?(der)
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
    FastlaneCore::UI.user_error!("could not resolve PRODUCT_BUNDLE_IDENTIFIER for #{scheme} in #{configuration}") if value.to_s.empty?
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
    FastlaneCore::UI.user_error!("expected exactly one .app in the archive, found #{apps.length}") unless apps.length == 1
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

    # iOS apps that do not declare Keychain Sharing have no keychain-access-groups
    # entitlement at all; their default access group is the implicit
    # TEAM.bundle-id, which the profile authorizes through its own patterns. An
    # app that does declare groups makes the FIRST entry its default, so that
    # entry must be TEAM.bundle-id and every claim must still be authorized.
    declared_groups = app_entitlements["keychain-access-groups"]
    declared = app_entitlements.key?("keychain-access-groups")
    keychain_mode = "implicit"
    effective_default = app_id
    claimed_groups = []
    if !declared
      unless Array(allowed["keychain-access-groups"]).any? { |pattern| MacOSSigning.authorizes?(pattern, app_id) }
        errors << "profile does not authorize the implicit default keychain group #{app_id}"
      end
    elsif !declared_groups.is_a?(Array) || declared_groups.empty?
      keychain_mode = "malformed"
      errors << "app declares malformed keychain-access-groups #{declared_groups.inspect}; " \
                "it must be a non-empty array of group identifiers"
    else
      keychain_mode = "explicit"
      claimed_groups = declared_groups.map(&:to_s)
      effective_default = claimed_groups.first
      if effective_default != app_id
        errors << "app declares #{effective_default.inspect} as its effective default keychain group " \
                  "(the first entry is the default on iOS); it must be #{app_id}"
      end
      claimed_groups.each do |claim|
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

    {
      "keychain_groups" => keychain_mode,
      "keychain_access_groups" => claimed_groups,
      "effective_default_keychain_group" => effective_default,
    }
  end

  def verify_ios_store_ipa(ipa_path, version_name:, build_number:, bundle_id:, team_id:)
    facts = { "scheme" => "app-store-distribution", "artifact" => File.basename(ipa_path) }
    Dir.mktmpdir("prism-ios-store-verify") do |dir|
      capture!("ditto", "-x", "-k", ipa_path, dir)
      app_path = File.join(dir, "Payload", "Runner.app")
      FastlaneCore::UI.user_error!("exported IPA has no Payload/Runner.app") unless Dir.exist?(app_path)

      # Verification only; signing stays explicit elsewhere and never uses --deep.
      capture!("codesign", "--verify", "--deep", "--strict", "--verbose=2", app_path)
      authorities = codesign_authorities(app_path)
      unless authorities.any? { |authority| authority.start_with?("Apple Distribution") }
        FastlaneCore::UI.user_error!("IPA is not signed with an Apple Distribution identity (found: #{authorities.join(', ')})")
      end
      if authorities.any? { |authority| authority.start_with?("Apple Development") }
        FastlaneCore::UI.user_error!("IPA carries an Apple Development identity; a personal development certificate must not sign a release")
      end

      entitlements = entitlements(app_path)
      profile_path = File.join(app_path, "embedded.mobileprovision")
      FastlaneCore::UI.user_error!("exported IPA has no embedded provisioning profile") unless File.file?(profile_path)
      profile = provisioning_profile(profile_path)
      begin
        keychain = validate_ios_store_profile!(
          profile, entitlements,
          team_id: team_id, bundle_id: bundle_id,
          certificate_sha1: signing_certificate_sha1(app_path)
        )
      rescue RuntimeError, ArgumentError => error
        FastlaneCore::UI.user_error!("exported IPA failed distribution validation: #{error.message}")
      end

      info = plist_json(File.join(app_path, "Info.plist"))
      unless info["CFBundleShortVersionString"] == version_name
        FastlaneCore::UI.user_error!(
          "IPA version #{info['CFBundleShortVersionString'].inspect} does not match pubspec #{version_name.inspect}"
        )
      end
      unless info["CFBundleVersion"].to_s == build_number.to_s
        FastlaneCore::UI.user_error!("IPA build #{info['CFBundleVersion'].inspect} does not match pubspec #{build_number.inspect}")
      end
      unless info["CFBundleIdentifier"] == bundle_id
        FastlaneCore::UI.user_error!("IPA bundle identifier #{info['CFBundleIdentifier'].inspect} is not #{bundle_id}")
      end

      keychain_claim =
        if keychain["keychain_groups"] == "implicit"
          "implicit default keychain group #{keychain['effective_default_keychain_group']} authorized by the profile"
        else
          "declared keychain groups authorized (effective default " \
            "#{keychain['effective_default_keychain_group']})"
        end
      facts.merge!(
        "identity" => authorities.first,
        "authority_chain" => authorities,
        "version" => info["CFBundleShortVersionString"],
        "build" => info["CFBundleVersion"],
        "bundle_id" => info["CFBundleIdentifier"],
        "get_task_allow" => entitlements["get-task-allow"] == true,
        "app_attest_environment" => entitlements[APP_ATTEST_ENTITLEMENT],
        # Actual claims only: an app without Keychain Sharing declares none, and
        # the receipt says so rather than inventing a group it never claimed.
        "keychain_groups" => keychain["keychain_groups"],
        "keychain_access_groups" => keychain["keychain_access_groups"],
        "effective_default_keychain_group" => keychain["effective_default_keychain_group"],
        "entitlement_keys" => entitlements.keys.sort,
        "signing_certificate_sha1" => signing_certificate_sha1(app_path),
        "verified" => "distribution signature verified deep+strict; App Attest production; " \
                      "#{keychain_claim}; get-task-allow false; version/build checked"
      )
    end
    facts
  end

  # Option B for the iOS store lane: the archive is built with signing disabled,
  # so nothing carries the app's entitlements into the export. xcodebuild's
  # export only preserves custom entitlements that already exist in a signature,
  # so the archived app is seeded with an ad-hoc signature applied with the SOURCE
  # entitlements file (App Attest production included). No capability is invented,
  # nested code is signed inside-out first, and --deep is never used to sign.
  def seed_archive_adhoc_entitlements!(app_path, entitlements_path:)
    FastlaneCore::UI.user_error!("source entitlements are missing: #{entitlements_path}") unless File.file?(entitlements_path)

    entitlements = plist_json(entitlements_path)
    unless entitlements.is_a?(Hash)
      FastlaneCore::UI.user_error!("#{entitlements_path} is not an entitlements dictionary")
    end
    app_attest = entitlements[APP_ATTEST_ENTITLEMENT].to_s
    unless app_attest == "production"
      FastlaneCore::UI.user_error!(
        "source entitlements must carry #{APP_ATTEST_ENTITLEMENT}=production (found " \
        "#{entitlements[APP_ATTEST_ENTITLEMENT].inspect}); refusing to seed an archive without it"
      )
    end

    # The approved App Store profile covers the main app only. An extension needs
    # its own entitlements and provisioning entry, so refuse before signing
    # anything rather than shipping a partially signed payload.
    extensions = Dir[File.join(app_path, "PlugIns", "*.appex")].sort
    unless extensions.empty?
      FastlaneCore::UI.user_error!(
        "#{app_path} contains app extensions (#{extensions.map { |path| File.basename(path) }.join(', ')}). " \
        "The approved profile covers the main app only, so each extension needs its own " \
        "entitlements and provisioning entry. Nothing was signed."
      )
    end

    nested = nested_code_paths(app_path)
    nested[:paths].each do |nested_path|
      capture!("codesign", "--force", "--sign", "-", nested_path)
    end
    capture!("codesign", "--force", "--sign", "-", "--entitlements", entitlements_path, app_path)

    seeded = entitlements(app_path)
    unless seeded[APP_ATTEST_ENTITLEMENT].to_s == "production"
      FastlaneCore::UI.user_error!(
        "the ad-hoc seed did not carry #{APP_ATTEST_ENTITLEMENT}=production into #{app_path}"
      )
    end
    FastlaneCore::UI.important(
      "#{app_path}: seeded an ad-hoc signature with the source entitlements " \
      "(#{nested[:paths].length} nested item(s)); the only identity signing happens at export"
    )
    {
      "seeded" => true,
      "nested" => nested[:paths].length,
      "skipped_symlinks" => nested[:skipped_symlinks],
      "app_attest_environment" => app_attest,
    }
  end

  # Every nested code item under Frameworks, deepest first, then lexically, so an
  # enclosing framework is always signed after the frameworks it contains.
  # Symlinked aliases are skipped rather than signed through.
  def nested_code_paths(app_path)
    frameworks = File.join(app_path, "Frameworks")
    paths = []
    skipped_symlinks = []
    return { paths: paths, skipped_symlinks: skipped_symlinks } unless Dir.exist?(frameworks)

    Dir.glob(File.join(frameworks, "**", "*"), File::FNM_DOTMATCH).each do |path|
      next if [".", ".."].include?(File.basename(path))
      next unless File.symlink?(path) || File.exist?(path)

      if File.symlink?(path)
        skipped_symlinks << path
        next
      end
      next unless path.end_with?(".framework", ".dylib", ".so")
      next unless File.directory?(path) || File.file?(path)

      paths << path
    end
    paths.sort_by! { |path| [-path.split(File::SEPARATOR).length, path] }
    { paths: paths, skipped_symlinks: skipped_symlinks }
  end

  # The macOS project signs with "Apple Development" + Automatic, which a hosted
  # runner has neither an account nor a personal development identity for, so
  # compilation disables signing. This proves that override held — WITHOUT
  # treating the linker's ad-hoc signature as an identity: on Apple Silicon every
  # link adds one (`Signature=adhoc`, no Authority, `TeamIdentifier=not set`), so
  # "codesign returned success" says nothing on its own.
  #
  # Closed classification; there is no default-allow path:
  #   exit 0, exact Signature=adhoc, no Authority, TeamIdentifier=not set -> adhoc
  #   exit 0 with any Authority or a real TeamIdentifier                   -> identity (refuse)
  #   exit 0 with anything else                                           -> unknown (refuse)
  #   non-zero exit whose output holds the known not-signed message        -> unsigned
  #   non-zero exit with any other error                       -> inspection_error (refuse)
  NOT_SIGNED_MESSAGE = "code object is not signed at all"
  SIGNATURE_METADATA_KEYS = ["Signature", "Authority", "TeamIdentifier", "CodeDirectory"].freeze
  MAX_METADATA_BYTES = 8 * 1024

  # Parse only the metadata lines this guard needs, and record enough to notice a
  # partial or self-contradicting inspection rather than accepting it.
  def bounded_signature_metadata(text)
    bytes = text.to_s
    truncated = bytes.bytesize > MAX_METADATA_BYTES
    slice = truncated ? bytes.byteslice(0, MAX_METADATA_BYTES) : bytes
    values = {}
    authority_markers = 0
    slice.each_line do |line|
      line = line.strip
      if (code_directory = line.match(/\ACodeDirectory\b(?<rest>.*)\z/))
        (values["CodeDirectory"] ||= []) << code_directory[:rest].strip[0, 300]
        next
      end
      key, value = line.split("=", 2)
      next unless SIGNATURE_METADATA_KEYS.include?(key)

      if key == "Authority"
        # Any Authority line counts, even an empty one: its presence means an
        # identity signed this payload.
        authority_markers += 1
        (values["Authority"] ||= []) << value.to_s[0, 200] unless value.to_s.empty?
      else
        (values[key] ||= []) << value.to_s[0, 300]
      end
    end
    { "values" => values, "authority_markers" => authority_markers, "truncated" => truncated }
  end

  def signature_flags(code_directory)
    Array(code_directory).first.to_s[/flags=(\S+)/, 1]
  end

  def conflicting_metadata_keys(values)
    values.select { |key, list| key != "Authority" && list.uniq.length > 1 }.keys.sort
  end

  def classify_signed_state(inspection)
    return "truncated" if inspection["truncated"]

    values = inspection["values"]
    conflicts = conflicting_metadata_keys(values)
    return "conflicting" unless conflicts.empty?

    signature = Array(values["Signature"]).first
    team = Array(values["TeamIdentifier"]).first
    return "identity" if inspection["authority_markers"].positive?
    return "identity" if team && team != "not set"
    # The linker's signature is accepted only in its exact documented shape: the
    # explicit "not set" team is required, so a missing team is never ad-hoc.
    return "adhoc" if signature == "adhoc" && team == "not set"

    "unknown"
  end

  # A payload counts as genuinely unsigned only for the documented native
  # format: codesign exit 1 and exactly one line naming this path. A mixed or
  # unexpected error is an inspection error, never "unsigned".
  def not_signed_output?(text, status, app_path)
    return false unless status && status.exitstatus == 1

    lines = text.to_s.lines.map(&:rstrip).reject(&:empty?)
    lines.length == 1 && lines.first == "#{app_path}: #{NOT_SIGNED_MESSAGE}"
  end

  def assert_no_identity_signature!(app_path)
    stdout, stderr, status = Open3.capture3("codesign", "-dvvv", app_path.to_s)
    text = "#{stderr}#{stdout}"
    inspection = bounded_signature_metadata(text)
    state =
      if status.success?
        classify_signed_state(inspection)
      elsif not_signed_output?(text, status, app_path.to_s)
        "unsigned"
      else
        "inspection_error"
      end
    values = inspection["values"]
    classification = {
      "state" => state,
      "signature" => Array(values["Signature"]).first,
      "flags" => signature_flags(values["CodeDirectory"]),
      "authorities" => Array(values["Authority"]),
      "team_identifier" => Array(values["TeamIdentifier"]).first,
      "metadata_truncated" => inspection["truncated"],
      "conflicting_keys" => conflicting_metadata_keys(values),
    }
    case state
    when "adhoc", "unsigned"
      FastlaneCore::UI.important(
        "#{app_path}: compiled without an identity signature (state #{state}, " \
        "signature #{classification['signature'].inspect}, flags #{classification['flags'].inspect})"
      )
      classification
    when "identity"
      FastlaneCore::UI.user_error!(
        "#{app_path} is signed by an identity before our Developer ID signature: " \
        "authorities #{classification['authorities'].inspect}, " \
        "team #{classification['team_identifier'].inspect}, " \
        "signature #{classification['signature'].inspect}. " \
        "The compile-time signing override did not take effect, so the Developer ID " \
        "signature would not be the one we verified."
      )
    when "truncated"
      FastlaneCore::UI.user_error!(
        "signature inspection of #{app_path} exceeded the #{MAX_METADATA_BYTES}-byte metadata budget, " \
        "so an Authority or TeamIdentifier could be hidden after the cut-off. " \
        "Refusing to classify a partial inspection as unsigned."
      )
    when "conflicting"
      FastlaneCore::UI.user_error!(
        "#{app_path} reports conflicting signature metadata for " \
        "#{classification['conflicting_keys'].inspect} " \
        "(signature #{classification['signature'].inspect}, " \
        "team #{classification['team_identifier'].inspect}). Refusing to classify it as unsigned."
      )
    when "unknown"
      FastlaneCore::UI.user_error!(
        "#{app_path} has a signature whose metadata is not understood: " \
        "signature #{classification['signature'].inspect}, " \
        "flags #{classification['flags'].inspect}, " \
        "team #{classification['team_identifier'].inspect}. " \
        "It is neither the exact linker ad-hoc shape nor unsigned, so it is refused."
      )
    else
      FastlaneCore::UI.user_error!(
        "could not inspect the signature of #{app_path} (exit #{status.exitstatus}) and the output is " \
        "not the documented not-signed line for this path; refusing to treat an inspection error " \
        "as unsigned. Bounded output: #{text.to_s.byteslice(0, 400).inspect}"
      )
    end
  end

  def universal_archs!(app_path)
    macos_dir = File.join(app_path, "Contents", "MacOS")
    executables = Dir.children(macos_dir).sort
    FastlaneCore::UI.user_error!("macOS app has no executable in #{macos_dir}") if executables.empty?
    archs = capture!("lipo", "-archs", File.join(macos_dir, executables.first)).split
    missing = []
    missing << "arm64" unless archs.any? { |arch| arch.start_with?("arm64") }
    missing << "x86_64" unless archs.include?("x86_64")
    unless missing.empty?
      FastlaneCore::UI.user_error!("macOS payload is not universal (missing #{missing.join(', ')}; archs: #{archs.join(', ')})")
    end
    archs
  end
end
