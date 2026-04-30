import CryptoKit
import DeviceCheck
import Flutter
import Security
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenshotEventSink: FlutterEventSink?
  private var firstDeviceAdmissionChannel: FlutterMethodChannel?
  private var secureDisplayChannel: FlutterMethodChannel?
  private var runtimeDekWrapChannel: FlutterMethodChannel?
  private var secureTextField: UITextField?
  private let appAttestKeychainService = "com.prism.prism_plurality.app_attest"
  private let appAttestKeychainAccount = "key_id"
  private let runtimeDekPrivateKeyTag = Data(
    "com.prism.prism_plurality.runtime_dek_wrap.private.v1".utf8
  )

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(screenshotDetected),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ScreenshotDetector") else { return }
    FlutterEventChannel(
      name: "com.prism.prism_plurality/screenshot_events",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(self)
    secureDisplayChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/secure_display",
      binaryMessenger: registrar.messenger()
    )
    secureDisplayChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setSecureDisplay" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      let enabled = arguments["enabled"] as? Bool ?? false
      DispatchQueue.main.async {
        self?.setSecureDisplay(enabled: enabled)
        result(nil)
      }
    }
    firstDeviceAdmissionChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/first_device_admission",
      binaryMessenger: registrar.messenger()
    )
    firstDeviceAdmissionChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "collectFirstDeviceAdmissionProof" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(nil)
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      guard
        let syncId = arguments["sync_id"] as? String,
        let deviceId = arguments["device_id"] as? String,
        let nonce = arguments["nonce"] as? String,
        !syncId.isEmpty,
        !deviceId.isEmpty,
        !nonce.isEmpty
      else {
        result(nil)
        return
      }

      Task { @MainActor in
        let proof = await self.collectFirstDeviceAdmissionProof(
          syncId: syncId,
          deviceId: deviceId,
          nonce: nonce
        )
        result(proof)
      }
    }
    runtimeDekWrapChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/runtime_dek_wrap",
      binaryMessenger: registrar.messenger()
    )
    runtimeDekWrapChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate unavailable", details: nil))
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
            result(FlutterError(code: "INVALID_ARGS", message: "dek is required", details: nil))
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
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(
          code: "RUNTIME_DEK_WRAP_FAILED",
          message: error.localizedDescription,
          details: nil
        ))
      }
    }
    let fileUtilsChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/file_utils",
      binaryMessenger: registrar.messenger()
    )
    fileUtilsChannel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "path required", details: nil))
        return
      }
      do {
        var url = URL(fileURLWithPath: path)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try url.setResourceValues(resourceValues)
        result(nil)
      } catch {
        result(FlutterError(code: "FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func wrapRuntimeDek(_ dek: Data, aad: Data) throws -> [String: Any] {
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
      "platform": "ios_keychain_ecdh_p256_aes_gcm",
      "ephemeral_public": ephemeralPublicKeyData.base64EncodedString(),
      "combined": combined.base64EncodedString(),
    ]
  }

  private func unwrapRuntimeDek(_ blob: [String: Any], aad: Data) throws -> Data {
    guard
      let ephemeralPublicB64 = blob["ephemeral_public"] as? String,
      let ephemeralPublicKeyData = Data(base64Encoded: ephemeralPublicB64),
      let combinedB64 = blob["combined"] as? String,
      let combined = Data(base64Encoded: combinedB64)
    else {
      throw runtimeDekError("Invalid wrapped runtime DEK blob")
    }
    let key = try deriveRuntimeDekAesKey(
      privateKey: try loadOrCreateRuntimeDekPrivateKey(),
      peerPublicKeyData: ephemeralPublicKeyData,
      aad: aad
    )
    let sealed = try AES.GCM.SealedBox(combined: combined)
    return try AES.GCM.open(sealed, using: key, authenticating: aad)
  }

  private func loadOrCreateRuntimeDekPrivateKey() throws -> SecKey {
    if let key = readRuntimeDekPrivateKey() {
      return key
    }
    return try createRuntimeDekPrivateKey()
  }

  private func readRuntimeDekPrivateKey() -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
      kSecReturnRef as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let item else { return nil }
    return (item as! SecKey)
  }

  private func createRuntimeDekPrivateKey() throws -> SecKey {
    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
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

  private func deleteRuntimeDekWrappingKey() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
    ]
    SecItemDelete(query as CFDictionary)
  }

  /// Toggle secure display using the iOS secure text field trick.
  ///
  /// iOS has no public FLAG_SECURE equivalent, but a UITextField with
  /// `isSecureTextEntry = true` causes the system to hide its superview's
  /// content from screen recording and the app-switcher snapshot.
  private func setSecureDisplay(enabled: Bool) {
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap({ $0.windows })
      .first
    else { return }

    if enabled {
      if secureTextField == nil {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        window.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 0).isActive = true
        field.heightAnchor.constraint(equalToConstant: 0).isActive = true
        secureTextField = field
      }
    } else {
      secureTextField?.removeFromSuperview()
      secureTextField = nil
    }
  }

  @objc private func screenshotDetected() {
    screenshotEventSink?(nil)
  }

  @MainActor
  private func collectFirstDeviceAdmissionProof(
    syncId: String,
    deviceId: String,
    nonce: String
  ) async -> [String: Any]? {
    guard #available(iOS 14.0, *) else { return nil }
    let service = DCAppAttestService.shared
    guard service.isSupported else { return nil }

    let clientDataHash = buildAppAttestClientDataHash(
      syncId: syncId,
      deviceId: deviceId,
      nonce: nonce
    )

    for attempt in 0..<2 {
      guard let keyId = await loadOrCreateAppAttestKeyID(recreate: attempt > 0) else {
        return nil
      }
      do {
        let attestationObject = try await attestAppAttestKey(
          keyId: keyId,
          clientDataHash: clientDataHash
        )
        return [
          "kind": "apple_app_attest",
          "key_id": keyId,
          "attestation_object": attestationObject.base64EncodedString(),
        ]
      } catch {
        if attempt == 0 {
          clearAppAttestKeyID()
          continue
        }
        return nil
      }
    }

    return nil
  }

  private func loadOrCreateAppAttestKeyID(recreate: Bool = false) async -> String? {
    if !recreate, let storedKeyID = readKeychainString() {
      return storedKeyID
    }

    do {
      let keyID = try await generateAppAttestKey()
      guard storeKeychainString(keyID) else { return nil }
      return keyID
    } catch {
      return nil
    }
  }

  private func generateAppAttestKey() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      DCAppAttestService.shared.generateKey { keyID, error in
        if let keyID, !keyID.isEmpty {
          continuation.resume(returning: keyID)
          return
        }
        continuation.resume(
          throwing: error ?? NSError(
            domain: "com.prism.prism_plurality.app_attest",
            code: -1,
            userInfo: [
              NSLocalizedDescriptionKey: "Failed to generate App Attest key",
            ]
          )
        )
      }
    }
  }

  private func attestAppAttestKey(keyId: String, clientDataHash: Data) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash) {
        attestationObject, error in
        if let attestationObject {
          continuation.resume(returning: attestationObject)
          return
        }
        continuation.resume(
          throwing: error ?? NSError(
            domain: "com.prism.prism_plurality.app_attest",
            code: -1,
            userInfo: [
              NSLocalizedDescriptionKey: "Failed to attest App Attest key",
            ]
          )
        )
      }
    }
  }

  private func buildAppAttestClientDataHash(
    syncId: String,
    deviceId: String,
    nonce: String
  ) -> Data {
    var input = Data("PRISM_SYNC_APPLE_APP_ATTEST_V1".utf8)
    input.append(0)
    input.append(Data(syncId.utf8))
    input.append(0)
    input.append(Data(deviceId.utf8))
    input.append(0)
    input.append(Data(nonce.utf8))
    return Data(SHA256.hash(data: input))
  }

  private func readKeychainString() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: appAttestKeychainService,
      kSecAttrAccount as String: appAttestKeychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func storeKeychainString(_ value: String) -> Bool {
    let data = Data(value.utf8)
    let baseQuery = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: appAttestKeychainService,
      kSecAttrAccount as String: appAttestKeychainAccount,
    ] as [String: Any]

    let addQuery = baseQuery.merging([
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: data,
    ]) { _, new in new }

    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecSuccess {
      return true
    }
    if addStatus != errSecDuplicateItem {
      return false
    }

    let updateStatus = SecItemUpdate(
      baseQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    return updateStatus == errSecSuccess
  }

  private func clearAppAttestKeyID() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: appAttestKeychainService,
      kSecAttrAccount as String: appAttestKeychainAccount,
    ]
    SecItemDelete(query as CFDictionary)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    screenshotEventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    screenshotEventSink = nil
    return nil
  }
}
