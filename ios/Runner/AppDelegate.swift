import CryptoKit
import DeviceCheck
import Flutter
import Security
import UIKit

enum BackupExclusionPathError: Error, Equatable, LocalizedError {
  case invalidPath
  case outsideAppContainer

  var errorDescription: String? {
    switch self {
    case .invalidPath:
      return "Backup exclusion path must be an absolute file path"
    case .outsideAppContainer:
      return "Backup exclusion path must be inside the app container"
    }
  }
}

enum BackupExclusionPathValidator {
  private static let maxSymlinkDepth = 32

  static func validatedURL(
    for path: String,
    containerRoot: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
  ) throws -> URL {
    guard path.hasPrefix("/") else {
      throw BackupExclusionPathError.invalidPath
    }

    let candidate = try resolvedFileURL(forAbsolutePath: path)
    let root = try resolvedFileURL(forAbsolutePath: containerRoot.path)
    let rootPath = root.path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
    guard candidate.path == rootPath || candidate.path.hasPrefix(rootPrefix) else {
      throw BackupExclusionPathError.outsideAppContainer
    }

    return candidate
  }

  private static func resolvedFileURL(forAbsolutePath path: String) throws -> URL {
    try resolvedFileURL(
      pathComponents: URL(fileURLWithPath: path).pathComponents,
      symlinkDepth: 0
    )
  }

  private static func resolvedFileURL(
    pathComponents components: [String],
    symlinkDepth: Int
  ) throws -> URL {
    var current = URL(fileURLWithPath: "/", isDirectory: true)
    var index = components.first == "/" ? 1 : 0
    var depth = symlinkDepth

    while index < components.count {
      let component = components[index]
      index += 1

      switch component {
      case "", ".":
        continue
      case "..":
        current.deleteLastPathComponent()
        continue
      default:
        current.appendPathComponent(component)
      }

      guard let destination = try? FileManager.default.destinationOfSymbolicLink(
        atPath: current.path
      ) else {
        continue
      }
      depth += 1
      guard depth <= maxSymlinkDepth else {
        throw BackupExclusionPathError.invalidPath
      }

      let destinationURL = destination.hasPrefix("/")
        ? URL(fileURLWithPath: destination)
        : current.deletingLastPathComponent().appendingPathComponent(destination)
      let remainingComponents = index < components.count ? Array(components[index...]) : []
      return try resolvedFileURL(
        pathComponents: destinationURL.standardizedFileURL.pathComponents + remainingComponents,
        symlinkDepth: depth
      )
    }

    return current.standardizedFileURL
  }
}

enum SensitiveFileProtection {
  static let minimumProtection = URLFileProtection.completeUntilFirstUserAuthentication
  private static let creationProtection = FileProtectionType.completeUntilFirstUserAuthentication
  private static let databaseNames = ["prism.db", "prism_sync.db"]
  private static let sqliteSidecarSuffixes = ["", "-wal", "-shm"]

  static func applyKnownSensitiveProtection(fileManager: FileManager = .default) {
    for directory in knownSensitiveDirectories(fileManager: fileManager) {
      do {
        try createProtectedDirectoryIfNeeded(at: directory, fileManager: fileManager)
      } catch {
        print("[FILE_PROTECTION] Failed to protect directory \(directory.path): \(error)")
      }
    }

    for databaseURL in knownSensitiveDatabaseURLs(fileManager: fileManager) {
      do {
        try applyMinimumProtection(to: databaseURL, fileManager: fileManager)
      } catch {
        print("[FILE_PROTECTION] Failed to protect database path \(databaseURL.path): \(error)")
      }
    }
  }

  static func applyMinimumProtection(
    to url: URL,
    fileManager: FileManager = .default
  ) throws {
    guard let targetURL = protectionTarget(for: url, fileManager: fileManager) else {
      return
    }
    let current = try protectionClass(for: targetURL)
    guard shouldUpgrade(current) else { return }
    try (targetURL as NSURL).setResourceValue(
      minimumProtection,
      forKey: .fileProtectionKey
    )
  }

  static func protectionStatus(
    for url: URL,
    fileManager: FileManager = .default
  ) throws -> [String: Any] {
    let targetURL = protectionTarget(for: url, fileManager: fileManager)
    let protection = try targetURL.flatMap { try protectionClass(for: $0) }
    return [
      "path": url.path,
      "target_path": targetURL?.path ?? NSNull(),
      "exists": fileManager.fileExists(atPath: url.path),
      "protection": protection?.rawValue ?? NSNull(),
      "minimum_protection": minimumProtection.rawValue,
      "meets_minimum": meetsMinimum(protection),
    ]
  }

  static func protectionClass(for url: URL) throws -> URLFileProtection? {
    try url.resourceValues(forKeys: [.fileProtectionKey]).fileProtection
  }

  static func meetsMinimum(_ protection: URLFileProtection?) -> Bool {
    guard let protection else { return false }
    return protection != .none
  }

  static func shouldUpgrade(_ protection: URLFileProtection?) -> Bool {
    guard let protection else { return true }
    return protection == .none
  }

  private static func createProtectedDirectoryIfNeeded(
    at url: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(
      at: url,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: creationProtection]
    )
    try applyMinimumProtection(to: url, fileManager: fileManager)
  }

  private static func knownSensitiveDirectories(fileManager: FileManager) -> [URL] {
    var directories: [URL] = []
    if let appSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first {
      directories.append(appSupport)
      directories.append(appSupport.appendingPathComponent("prism_media", isDirectory: true))
    }
    if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
      directories.append(documents)
    }
    return directories
  }

  private static func knownSensitiveDatabaseURLs(fileManager: FileManager) -> [URL] {
    guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return []
    }
    return databaseNames.flatMap { name in
      sqliteSidecarSuffixes.map { suffix in
        documents.appendingPathComponent("\(name)\(suffix)")
      }
    }
  }

  private static func protectionTarget(for url: URL, fileManager: FileManager) -> URL? {
    if fileManager.fileExists(atPath: url.path) {
      return url
    }
    let parent = url.deletingLastPathComponent()
    return fileManager.fileExists(atPath: parent.path) ? parent : nil
  }
}

enum PlatformAttestationError: Error, LocalizedError {
  case missingAPI(String)
  case unsupported(String)
  case transientFailure(String)
  case permanentFailure(String)

  var flutterCode: String {
    switch self {
    case .missingAPI:
      return "missing_api"
    case .unsupported:
      return "unsupported"
    case .transientFailure:
      return "transient_failure"
    case .permanentFailure:
      return "permanent_failure"
    }
  }

  var errorDescription: String? {
    switch self {
    case .missingAPI(let message),
         .unsupported(let message),
         .transientFailure(let message),
         .permanentFailure(let message):
      return message
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenshotEventSink: FlutterEventSink?
  private var firstDeviceAdmissionChannel: FlutterMethodChannel?
  private var secureDisplayChannel: FlutterMethodChannel?
  private var runtimeDekWrapChannel: FlutterMethodChannel?
  private var appClipboardChannel: FlutterMethodChannel?
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
    SensitiveFileProtection.applyKnownSensitiveProtection()
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
        result(FlutterError(
          code: "transient_failure",
          message: "AppDelegate unavailable",
          details: nil
        ))
        return
      }
      let arguments = call.arguments as? [String: Any] ?? [:]
      guard
        let syncId = arguments["sync_id"] as? String,
        let deviceId = arguments["device_id"] as? String,
        let nonce = arguments["nonce"] as? String,
        let registrationKeyBundleHash = arguments["registration_key_bundle_hash"] as? String,
        !syncId.isEmpty,
        !deviceId.isEmpty,
        !nonce.isEmpty,
        !registrationKeyBundleHash.isEmpty
      else {
        result(FlutterError(
          code: "permanent_failure",
          message: "sync_id, device_id, nonce, and registration_key_bundle_hash are required",
          details: nil
        ))
        return
      }

      Task { @MainActor in
        do {
          let proof = try await self.collectFirstDeviceAdmissionProof(
            syncId: syncId,
            deviceId: deviceId,
            nonce: nonce,
            registrationKeyBundleHash: registrationKeyBundleHash
          )
          result(proof)
        } catch {
          result(self.firstDeviceAdmissionFlutterError(from: error))
        }
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
    appClipboardChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/app_clipboard",
      binaryMessenger: registrar.messenger()
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
    let fileUtilsChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/file_utils",
      binaryMessenger: registrar.messenger()
    )
    fileUtilsChannel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup" || call.method == "fileProtectionStatus" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "path required", details: nil))
        return
      }
      do {
        var url = try BackupExclusionPathValidator.validatedURL(for: path)
        try SensitiveFileProtection.applyMinimumProtection(to: url)
        switch call.method {
        case "excludeFromBackup":
          if FileManager.default.fileExists(atPath: url.path) {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
          }
          result(nil)
        case "fileProtectionStatus":
          result(try SensitiveFileProtection.protectionStatus(for: url))
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch BackupExclusionPathError.invalidPath {
        result(FlutterError(code: "INVALID_PATH", message: "path must be absolute", details: nil))
      } catch BackupExclusionPathError.outsideAppContainer {
        result(FlutterError(
          code: "OUTSIDE_APP_CONTAINER",
          message: "path must be inside the app container",
          details: nil
        ))
      } catch {
        result(FlutterError(code: "FAILED", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func readClipboardImageData() -> Data? {
    let pasteboard = UIPasteboard.general
    if let pngData = pasteboard.data(forPasteboardType: "public.png") {
      return pngData
    }
    if let jpegData = pasteboard.data(forPasteboardType: "public.jpeg") {
      return jpegData
    }
    if let image = pasteboard.image {
      return image.pngData()
    }
    return nil
  }

  private func isDefaultClipboard(_ arguments: Any?) -> Bool {
    let args = arguments as? [String: Any]
    return (args?["pasteboard"] as? String ?? "clipboard") == "clipboard"
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
    nonce: String,
    registrationKeyBundleHash: String
  ) async throws -> [String: Any] {
    guard #available(iOS 14.0, *) else {
      throw PlatformAttestationError.missingAPI(
        "App Attest requires iOS 14.0 or newer"
      )
    }
    let service = DCAppAttestService.shared
    guard service.isSupported else {
      throw PlatformAttestationError.unsupported(
        "App Attest is not supported on this device"
      )
    }

    guard let clientDataHash = buildAppAttestClientDataHash(
      syncId: syncId,
      deviceId: deviceId,
      nonce: nonce,
      registrationKeyBundleHash: registrationKeyBundleHash
    ) else {
      throw PlatformAttestationError.permanentFailure(
        "registration_key_bundle_hash must be a 32-byte hex value"
      )
    }

    for attempt in 0..<2 {
      let keyId = try await loadOrCreateAppAttestKeyID(recreate: attempt > 0)
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
        if attempt == 0 && isInvalidAppAttestKey(error) {
          clearAppAttestKeyID()
          continue
        }
        throw classifyAppAttestError(error, operation: "App Attest attestation")
      }
    }

    throw PlatformAttestationError.permanentFailure("App Attest key was rejected")
  }

  private func loadOrCreateAppAttestKeyID(recreate: Bool = false) async throws -> String {
    if !recreate, let storedKeyID = readKeychainString() {
      return storedKeyID
    }

    do {
      let keyID = try await generateAppAttestKey()
      guard storeKeychainString(keyID) else {
        throw PlatformAttestationError.transientFailure(
          "Failed to store App Attest key ID in Keychain"
        )
      }
      return keyID
    } catch {
      throw classifyAppAttestError(error, operation: "App Attest key generation")
    }
  }

  private func firstDeviceAdmissionFlutterError(from error: Error) -> FlutterError {
    if let platformError = error as? PlatformAttestationError {
      return FlutterError(
        code: platformError.flutterCode,
        message: platformError.localizedDescription,
        details: nil
      )
    }
    return FlutterError(
      code: "transient_failure",
      message: error.localizedDescription,
      details: nil
    )
  }

  private func classifyAppAttestError(
    _ error: Error,
    operation: String
  ) -> PlatformAttestationError {
    if let platformError = error as? PlatformAttestationError {
      return platformError
    }

    let nsError = error as NSError
    if nsError.domain == DCErrorDomain,
       let code = DCError.Code(rawValue: nsError.code) {
      switch code {
      case .featureUnsupported:
        return .unsupported("\(operation) is unsupported on this device")
      case .serverUnavailable, .unknownSystemFailure:
        return .transientFailure("\(operation) failed transiently: \(nsError.localizedDescription)")
      case .invalidInput, .invalidKey:
        return .permanentFailure("\(operation) failed verification: \(nsError.localizedDescription)")
      @unknown default:
        return .transientFailure("\(operation) failed: \(nsError.localizedDescription)")
      }
    }

    return .transientFailure("\(operation) failed: \(error.localizedDescription)")
  }

  private func isInvalidAppAttestKey(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == DCErrorDomain,
          let code = DCError.Code(rawValue: nsError.code) else {
      return false
    }
    return code == .invalidKey
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
    nonce: String,
    registrationKeyBundleHash: String
  ) -> Data? {
    guard let registrationKeyBundleHashData = hexData(registrationKeyBundleHash),
          registrationKeyBundleHashData.count == 32 else {
      return nil
    }

    var input = Data("PRISM_SYNC_APPLE_APP_ATTEST_V2".utf8)
    input.append(0)
    input.append(Data(syncId.utf8))
    input.append(0)
    input.append(Data(deviceId.utf8))
    input.append(0)
    input.append(Data(nonce.utf8))
    input.append(0)
    input.append(registrationKeyBundleHashData)
    return Data(SHA256.hash(data: input))
  }

  private func hexData(_ hex: String) -> Data? {
    guard hex.count.isMultiple(of: 2) else { return nil }

    var data = Data()
    data.reserveCapacity(hex.count / 2)

    var index = hex.startIndex
    while index < hex.endIndex {
      let nextIndex = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
        return nil
      }
      data.append(byte)
      index = nextIndex
    }

    return data
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
