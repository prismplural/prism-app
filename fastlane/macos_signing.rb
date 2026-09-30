require "base64"
require "digest"
require "rexml/document"
require "time"

# Restricted Keychain claims require a matching Developer ID distribution
# profile. Signature/notarization success alone does not establish this.
module MacOSSigning
  def self.parse_plist(xml)
    decode(REXML::Document.new(xml).root.elements[1])
  end

  def self.decode(node)
    case node.name
    when "dict"
      node.elements.to_a.each_slice(2).to_h { |key, value| [key.text, decode(value)] }
    when "array" then node.elements.to_a.map { |value| decode(value) }
    when "true" then true
    when "false" then false
    when "date" then Time.iso8601(node.text)
    when "data" then Base64.decode64(node.text.to_s)
    when "integer" then Integer(node.text)
    when "string" then node.text.to_s
    else raise ArgumentError, "Unsupported plist value: #{node.name}"
    end
  end

  def self.plist(values)
    document = REXML::Document.new
    document.add(REXML::XMLDecl.new("1.0", "UTF-8"))
    root = document.add_element("plist", "version" => "1.0")
    dict = root.add_element("dict")
    values.each do |key, value|
      dict.add_element("key").text = key
      case value
      when true, false then dict.add_element(value.to_s)
      when String then dict.add_element("string").text = value
      when Array
        array = dict.add_element("array")
        value.each { |item| array.add_element("string").text = item }
      else raise ArgumentError, "Unsupported entitlement value: #{value.inspect}"
      end
    end
    document.to_s
  end

  def self.authorizes?(pattern, claim)
    return false unless pattern.is_a?(String) && claim.is_a?(String)
    return false if claim.empty? || claim.include?("*") || claim.include?("$(")
    pattern == claim || (pattern.end_with?("*") && claim.start_with?(pattern[0...-1]))
  end

  def self.validate!(profile, entitlements, bundle_id:, team_id:, certificate_sha1: nil, now: Time.now)
    errors = []
    allowed = profile.fetch("Entitlements", {})
    app_id = "#{team_id}.#{bundle_id}"
    errors << "profile is not all-device Developer ID distribution" unless profile["ProvisionsAllDevices"] == true
    errors << "profile is device-bound" if profile.key?("ProvisionedDevices")
    errors << "profile is not macOS" unless Array(profile["Platform"]).include?("OSX")
    errors << "profile team does not match" unless Array(profile["TeamIdentifier"]).include?(team_id)
    expiry = profile["ExpirationDate"]
    errors << "profile is expired or has no expiration" unless expiry.is_a?(Time) && expiry > now
    errors << "profile does not authorize app identifier" unless authorizes?(allowed["com.apple.application-identifier"], app_id)
    errors << "profile entitlement team does not match" unless allowed["com.apple.developer.team-identifier"] == team_id
    errors << "app identifier claim does not match" unless entitlements["com.apple.application-identifier"] == app_id
    errors << "app team claim does not match" unless entitlements["com.apple.developer.team-identifier"] == team_id
    groups = entitlements["keychain-access-groups"]
    if !groups.is_a?(Array) || !groups.include?(app_id)
      errors << "app has no resolved default keychain access group"
    else
      groups.each do |claim|
        unless Array(allowed["keychain-access-groups"]).any? { |pattern| authorizes?(pattern, claim) }
          errors << "profile does not authorize keychain access group #{claim.inspect}"
        end
      end
    end
    if entitlements["com.apple.security.get-task-allow"] == true || allowed["com.apple.security.get-task-allow"] == true
      errors << "debug attachment is enabled"
    end
    if certificate_sha1
      fingerprints = Array(profile["DeveloperCertificates"]).map { |der| Digest::SHA1.hexdigest(der).upcase }
      errors << "profile does not authorize signing certificate" unless fingerprints.include?(certificate_sha1.upcase)
    end
    raise ArgumentError, errors.join("; ") unless errors.empty?
    true
  end
end
