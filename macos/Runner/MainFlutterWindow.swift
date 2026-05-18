import Cocoa
import CryptoKit
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  private var runtimeDekWrapChannel: FlutterMethodChannel?
  private var appClipboardChannel: FlutterMethodChannel?
  private let runtimeDekPrivateKeyTag = Data(
    "com.prism.prism_plurality.runtime_dek_wrap.private.v1".utf8
  )

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.title = "Prism"
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    runtimeDekWrapChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/runtime_dek_wrap",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    runtimeDekWrapChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Window unavailable", details: nil))
        return
      }
      do {
        switch call.method {
        case "wrapRuntimeDek":
          let arguments = call.arguments as? [String: Any] ?? [:]
          guard
            let typedData = arguments["dek"] as? FlutterStandardTypedData,
            let aad = arguments["aad"] as? String,
            !aad.isEmpty
          else {
            result(FlutterError(code: "INVALID_ARGS", message: "dek and aad are required", details: nil))
            return
          }
          result(try self.wrapRuntimeDek(typedData.data, aad: Data(aad.utf8)))
        case "unwrapRuntimeDek":
          guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "wrapped blob is required", details: nil))
            return
          }
          guard let aad = arguments["aad"] as? String, !aad.isEmpty else {
            result(FlutterError(code: "INVALID_ARGS", message: "aad is required", details: nil))
            return
          }
          result(FlutterStandardTypedData(
            bytes: try self.unwrapRuntimeDek(arguments, aad: Data(aad.utf8))
          ))
        case "deleteRuntimeDekWrappingKey":
          self.deleteRuntimeDekWrappingKey()
          result(nil)
        case "deleteAllPrismResetKeys":
          self.deleteAllPrismResetKeys()
          result(nil)
        case "hasPrismResetKeys":
          result(self.collectPrismResetKeyPresence())
        case "getRuntimeDekDiagnostics":
          result(self.collectRuntimeDekDiagnostics())
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        let code: String
        if call.method == "unwrapRuntimeDek" {
          code = self.classifyRuntimeDekUnwrapFailure(error)
        } else {
          code = "RUNTIME_DEK_WRAP_FAILED"
        }
        result(FlutterError(code: code, message: error.localizedDescription, details: nil))
      }
    }

    appClipboardChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/app_clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    appClipboardChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "readImage":
        guard self?.isDefaultClipboard(call.arguments) == true else {
          result(nil)
          return
        }
        result(self?.readClipboardImageData().map { FlutterStandardTypedData(bytes: $0) })
      case "readImageUri":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func readClipboardImageData() -> Data? {
    let pasteboard = NSPasteboard.general
    if let pngData = pasteboard.data(forType: .png) {
      return pngData
    }
    if let jpegData = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
      return jpegData
    }
    if let tiffData = pasteboard.data(forType: .tiff),
       let image = NSImage(data: tiffData) {
      return pngData(from: image)
    }
    if let image = NSImage(pasteboard: pasteboard) {
      return pngData(from: image)
    }
    return nil
  }

  private func isDefaultClipboard(_ arguments: Any?) -> Bool {
    let args = arguments as? [String: Any]
    return (args?["pasteboard"] as? String ?? "clipboard") == "clipboard"
  }

  private func wrapRuntimeDek(_ dek: Data, aad: Data) throws -> [String: Any] {
    guard dek.count == 32 else {
      throw runtimeDekError("Runtime DEK plaintext length invalid")
    }
    let recipientPrivateKey = try loadOrCreateRuntimeDekPrivateKey()
    guard let recipientPublicKey = SecKeyCopyPublicKey(recipientPrivateKey) else {
      throw runtimeDekError("Failed to load runtime DEK public wrapping key")
    }
    let recipientPublicKeyData = try externalRepresentation(recipientPublicKey)
    let ephemeralPrivateKey = try createEphemeralRuntimeDekPrivateKey()
    guard let ephemeralPublicKey = SecKeyCopyPublicKey(ephemeralPrivateKey) else {
      throw runtimeDekError("Failed to create ephemeral runtime DEK public key")
    }
    let ephemeralPublicKeyData = try externalRepresentation(ephemeralPublicKey)
    let key = try deriveRuntimeDekAesKey(
      privateKey: ephemeralPrivateKey,
      peerPublicKeyData: recipientPublicKeyData,
      aad: aad
    )
    let sealed = try AES.GCM.seal(dek, using: key, authenticating: aad)
    guard let combined = sealed.combined else {
      throw runtimeDekError("AES-GCM combined box unavailable")
    }
    return [
      "version": 1,
      "platform": "macos_keychain_ecdh_p256_aes_gcm",
      "ephemeral_public": ephemeralPublicKeyData.base64EncodedString(),
      "combined": combined.base64EncodedString(),
    ]
  }

  private func unwrapRuntimeDek(_ blob: [String: Any], aad: Data) throws -> Data {
    guard
      let version = blob["version"] as? Int,
      version == 1,
      let platform = blob["platform"] as? String,
      platform == "macos_keychain_ecdh_p256_aes_gcm",
      let ephemeralPublicB64 = blob["ephemeral_public"] as? String,
      let ephemeralPublicKeyData = Data(base64Encoded: ephemeralPublicB64),
      let combinedB64 = blob["combined"] as? String,
      let combined = Data(base64Encoded: combinedB64)
    else {
      throw runtimeDekError("Invalid wrapped runtime DEK blob")
    }
    guard let privateKey = try readRuntimeDekPrivateKey() else {
      throw runtimeDekError("Runtime DEK private key not present in Keychain")
    }
    let key = try deriveRuntimeDekAesKey(
      privateKey: privateKey,
      peerPublicKeyData: ephemeralPublicKeyData,
      aad: aad
    )
    let sealed = try AES.GCM.SealedBox(combined: combined)
    let dek = try AES.GCM.open(sealed, using: key, authenticating: aad)
    guard dek.count == 32 else {
      throw runtimeDekError("Runtime DEK plaintext length invalid")
    }
    return dek
  }

  private func loadOrCreateRuntimeDekPrivateKey() throws -> SecKey {
    if let key = try readRuntimeDekPrivateKey() {
      return key
    }
    return try createRuntimeDekPrivateKey()
  }

  private func readRuntimeDekPrivateKey() throws -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
      kSecUseDataProtectionKeychain as String: true,
      kSecReturnRef as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess, let item else {
      throw runtimeDekSecError(status, "Runtime DEK private-key lookup failed")
    }
    return (item as! SecKey)
  }

  private func createRuntimeDekPrivateKey() throws -> SecKey {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecUseDataProtectionKeychain as String: true,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        kSecAttrIsExtractable as String: false,
      ],
    ]

    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw error?.takeRetainedValue() ?? runtimeDekError(
        "Failed to create runtime DEK wrapping key"
      )
    }
    return key
  }

  private func createEphemeralRuntimeDekPrivateKey() throws -> SecKey {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
    ]

    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw error?.takeRetainedValue() ?? runtimeDekError(
        "Failed to create ephemeral runtime DEK key"
      )
    }
    return key
  }

  private func deriveRuntimeDekAesKey(
    privateKey: SecKey,
    peerPublicKeyData: Data,
    aad: Data
  ) throws -> SymmetricKey {
    let peerPublicKey = try publicKey(from: peerPublicKeyData)
    let algorithm = SecKeyAlgorithm.ecdhKeyExchangeStandardX963SHA256
    guard SecKeyIsAlgorithmSupported(privateKey, .keyExchange, algorithm) else {
      throw runtimeDekError("Runtime DEK key exchange is not supported")
    }
    let parameters: [String: Any] = [
      SecKeyKeyExchangeParameter.requestedSize.rawValue as String: 32,
      SecKeyKeyExchangeParameter.sharedInfo.rawValue as String: aad,
    ]
    var error: Unmanaged<CFError>?
    guard let secret = SecKeyCopyKeyExchangeResult(
      privateKey,
      algorithm,
      peerPublicKey,
      parameters as CFDictionary,
      &error
    ) as Data? else {
      throw error?.takeRetainedValue() ?? runtimeDekError(
        "Runtime DEK key exchange failed"
      )
    }
    return SymmetricKey(data: secret)
  }

  private func publicKey(from data: Data) throws -> SecKey {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
      kSecAttrKeySizeInBits as String: 256,
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
      throw error?.takeRetainedValue() ?? runtimeDekError(
        "Invalid runtime DEK public wrapping key"
      )
    }
    return key
  }

  private func externalRepresentation(_ key: SecKey) throws -> Data {
    var error: Unmanaged<CFError>?
    guard let data = SecKeyCopyExternalRepresentation(key, &error) as Data? else {
      throw error?.takeRetainedValue() ?? runtimeDekError(
        "Failed to export runtime DEK public wrapping key"
      )
    }
    return data
  }

  private func runtimeDekError(_ message: String) -> NSError {
    NSError(
      domain: "com.prism.prism_plurality.runtime_dek_wrap",
      code: -1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private func runtimeDekSecError(_ status: OSStatus, _ message: String) -> NSError {
    NSError(
      domain: NSOSStatusErrorDomain,
      code: Int(status),
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  private func collectRuntimeDekDiagnostics() -> [String: Any] {
    var out: [String: Any] = [:]
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
      kSecUseDataProtectionKeychain as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnAttributes as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    out["alias_present"] = (status == errSecSuccess)
    if status != errSecSuccess && status != errSecItemNotFound {
      out["keychain_introspection_status"] = Int(status)
    }
    if status == errSecSuccess, let attrs = item as? [String: Any] {
      var keySecurity: [String: Any] = [:]
      if let accessible = attrs[kSecAttrAccessible as String] as? String {
        keySecurity["accessible"] = accessible
      }
      if let synchronizable = attrs[kSecAttrSynchronizable as String] as? Bool {
        keySecurity["synchronizable"] = synchronizable
      }
      if let isExtractable = attrs[kSecAttrIsExtractable as String] as? Bool {
        keySecurity["is_extractable"] = isExtractable
      }
      out["key_security"] = keySecurity
    }

    out["device_state"] = ["protected_data_available": true]
    out["build"] = [
      "manufacturer": "Apple",
      "model": Host.current().localizedName ?? "Mac",
      "system_name": "macOS",
      "system_version": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    return out
  }

  private func classifyRuntimeDekUnwrapFailure(_ error: Error) -> String {
    if error is CryptoKitError {
      return "RUNTIME_DEK_WRAP_TERMINAL"
    }
    let nsError = error as NSError
    if nsError.domain == "com.prism.prism_plurality.runtime_dek_wrap" {
      return "RUNTIME_DEK_WRAP_TERMINAL"
    }
    if nsError.domain == NSOSStatusErrorDomain {
      let status = OSStatus(nsError.code)
      switch status {
      case errSecInteractionNotAllowed:
        return "RUNTIME_DEK_WRAP_TRANSIENT"
      case errSecAuthFailed,
           errSecItemNotFound,
           errSecParam,
           errSecDecode,
           errSecMissingEntitlement:
        return "RUNTIME_DEK_WRAP_TERMINAL"
      default:
        return "RUNTIME_DEK_WRAP_FAILED"
      }
    }
    return "RUNTIME_DEK_WRAP_FAILED"
  }

  private func deleteRuntimeDekWrappingKey() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
      kSecUseDataProtectionKeychain as String: true,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func deleteAllPrismResetKeys() {
    deleteRuntimeDekWrappingKey()
  }

  private func collectPrismResetKeyPresence() -> [String: Any] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
      kSecUseDataProtectionKeychain as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecReturnAttributes as String: true,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    let present = status == errSecSuccess
    return [
      "runtime_dek_key": present,
      "runtime_dek_key_status": Int(status),
      "residue_count": present ? 1 : 0,
      "summary": present ? "present" : "clear",
    ]
  }

  private func pngData(from image: NSImage) -> Data? {
    guard
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff)
    else {
      return nil
    }
    return bitmap.representation(using: .png, properties: [:])
  }
}
