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
  private var secureTextField: UITextField?
  private let appAttestKeychainService = "com.prism.prism_plurality.app_attest"
  private let appAttestKeychainAccount = "key_id"

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
