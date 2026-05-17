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

/// Overlays the host window with an opaque view during screen capture or
/// app backgrounding. Replaces a layer-reparenting trick that crashed
/// iOS 26 on trait changes (Flutter #181120 / `screen_protector` pattern).
/// Does NOT block active screenshots — iOS provides no app-level API for
/// that; the previous trick blocked them as a side effect, this one
/// doesn't. Screenshot detection still goes through
/// `userDidTakeScreenshotNotification`.
final class PrivacyOverlay {
  private weak var protectedWindow: UIWindow?
  private var overlay: UIView?
  private var enabled = false
  private var observerTokens: [NSObjectProtocol] = []

  /// Test seam for the captured branch of `reconcile()`.
  var isScreenCapturedProvider: () -> Bool = { UIScreen.main.isCaptured }

  var isOverlayInstalled: Bool { overlay?.superview != nil }

  @discardableResult
  func setEnabled(_ newValue: Bool, in window: UIWindow) -> Bool {
    let windowChanged = protectedWindow !== window
    if windowChanged {
      removeOverlay()
    }
    enabled = newValue
    protectedWindow = newValue ? window : nil
    if newValue {
      installObserversIfNeeded()
      reconcile()
    } else {
      removeOverlay()
    }
    return true
  }

  func reconcile() {
    guard enabled, let window = protectedWindow else {
      removeOverlay()
      return
    }
    let captured = isScreenCapturedProvider()
    let inactive = UIApplication.shared.applicationState != .active
    if captured || inactive {
      installOverlayIfNeeded(in: window)
    } else {
      removeOverlay()
    }
  }

  private func installObserversIfNeeded() {
    guard observerTokens.isEmpty else { return }
    let center = NotificationCenter.default
    // queue: nil — UIKit posts these on main, so sync dispatch is safe
    // and lets tests assert without an XCTestExpectation dance.
    observerTokens.append(
      center.addObserver(
        forName: UIScreen.capturedDidChangeNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.reconcile() }
    )
    observerTokens.append(
      center.addObserver(
        forName: UIApplication.willResignActiveNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.installOverlayForBackground() }
    )
    observerTokens.append(
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil,
        queue: nil
      ) { [weak self] _ in self?.reconcile() }
    )
  }

  // willResignActive fires while applicationState is still .active, so a
  // generic reconcile would skip — force the install for the snapshot.
  private func installOverlayForBackground() {
    guard enabled, let window = protectedWindow else { return }
    installOverlayIfNeeded(in: window)
  }

  private func installOverlayIfNeeded(in window: UIWindow) {
    if let existing = overlay, existing.superview === window {
      window.bringSubviewToFront(existing)
      existing.frame = window.bounds
      return
    }
    overlay?.removeFromSuperview()
    let view = UIView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.backgroundColor = .black
    // Swallow taps so users can't blind-interact with the hidden UI.
    view.isUserInteractionEnabled = true
    view.accessibilityElementsHidden = true
    window.addSubview(view)
    overlay = view
  }

  private func removeOverlay() {
    overlay?.removeFromSuperview()
    overlay = nil
  }

  deinit {
    for token in observerTokens {
      NotificationCenter.default.removeObserver(token)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private var screenshotEventSink: FlutterEventSink?
  private var firstDeviceAdmissionChannel: FlutterMethodChannel?
  private var secureDisplayChannel: FlutterMethodChannel?
  private var runtimeDekWrapChannel: FlutterMethodChannel?
  private var appClipboardChannel: FlutterMethodChannel?
  private var fileHandoffsChannel: FlutterMethodChannel?
  private let privacyOverlay = PrivacyOverlay()
  private let appAttestKeychainService = "com.prism.prism_plurality.app_attest"
  private let appAttestKeychainAccount = "key_id"
  private let runtimeDekPrivateKeyTag = Data(
    "com.prism.prism_plurality.runtime_dek_wrap.private.v1".utf8
  )
  private var pendingFileHandoff: PendingFileHandoff?

  private struct PendingFileHandoff {
    let result: FlutterResult
    let exportedURL: URL
    let stagingURL: URL?
    let bytesCopied: Int64?
  }

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
        let ok = self?.setSecureDisplay(enabled: enabled) ?? false
        if ok {
          result(nil)
        } else {
          // Propagate failure so ScreenSecurityService does not cache
          // _platformStateOn = true and skip retries. Treated by the
          // Dart side as PlatformException → returns false → retry on
          // next reconcile.
          result(FlutterError(
            code: "SECURE_DISPLAY_FAILED",
            message: "Could not apply secure display change",
            details: nil
          ))
        }
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
        case "getRuntimeDekDiagnostics":
          result(self.collectRuntimeDekDiagnostics())
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        // Classify only on the unwrap path; the Dart cache logic uses the
        // returned code to decide whether the wrapped runtime DEK blob
        // should be discarded. iOS Keychain (AfterFirstUnlockThisDeviceOnly)
        // is much more durable than Android Keystore so transient failures
        // are rare here, but the same code surface is plumbed through for
        // symmetry with Android.
        let code: String
        if call.method == "unwrapRuntimeDek" {
          code = self.classifyRuntimeDekUnwrapFailure(error)
        } else {
          code = "RUNTIME_DEK_WRAP_FAILED"
        }
        result(FlutterError(
          code: code,
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
    fileHandoffsChannel = FlutterMethodChannel(
      name: "com.prism.prism_plurality/file_handoffs",
      binaryMessenger: registrar.messenger()
    )
    fileHandoffsChannel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveExistingFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard let self else {
          result(["status": "failed", "error": "AppDelegate unavailable"])
          return
        }
        self.saveExistingFile(call.arguments, result: result)
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

  private func saveExistingFile(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pendingFileHandoff == nil else {
      result(["status": "alreadyActive"])
      return
    }

    let args = arguments as? [String: Any] ?? [:]
    guard let sourcePath = args["sourcePath"] as? String, !sourcePath.isEmpty else {
      result(["status": "failed", "error": "sourcePath is required"])
      return
    }

    let sourceURL = URL(fileURLWithPath: sourcePath)
    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
      result(["status": "failed", "error": "sourcePath does not exist"])
      return
    }

    let suggestedName = sanitizedFileName(
      args["suggestedName"] as? String,
      fallback: sourceURL.lastPathComponent
    )
    let sourceIsDurable = args["sourceIsDurable"] as? Bool ?? true

    do {
      let bytesCopied = try fileSize(sourceURL)
      let prepared = try preparedExportURL(
        sourceURL: sourceURL,
        suggestedName: suggestedName,
        sourceIsDurable: sourceIsDurable
      )
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(forExporting: [prepared.exportURL], asCopy: true)
      } else {
        picker = UIDocumentPickerViewController(url: prepared.exportURL, in: .exportToService)
      }
      picker.delegate = self
      picker.presentationController?.delegate = self
      pendingFileHandoff = PendingFileHandoff(
        result: result,
        exportedURL: prepared.exportURL,
        stagingURL: prepared.stagingURL,
        bytesCopied: bytesCopied
      )

      guard let presenter = topViewController() else {
        finishFileHandoff([
          "status": "failed",
          "error": "No view controller available to present document picker",
        ])
        return
      }
      presenter.present(picker, animated: true)
    } catch {
      result(["status": "failed", "error": error.localizedDescription])
    }
  }

  private func sanitizedFileName(_ suggestedName: String?, fallback: String) -> String {
    let rawName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let chosenName = rawName?.isEmpty == false ? rawName! : fallback
    let lastComponent = (chosenName as NSString).lastPathComponent
    return lastComponent.isEmpty ? fallback : lastComponent
  }

  private func preparedExportURL(
    sourceURL: URL,
    suggestedName: String,
    sourceIsDurable: Bool
  ) throws -> (exportURL: URL, stagingURL: URL?) {
    guard suggestedName != sourceURL.lastPathComponent else {
      return (sourceURL, nil)
    }

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("prism_file_handoffs", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let stagedURL = directory.appendingPathComponent(suggestedName, isDirectory: false)

    if sourceIsDurable {
      do {
        try FileManager.default.linkItem(at: sourceURL, to: stagedURL)
      } catch {
        try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
      }
    } else {
      do {
        try FileManager.default.moveItem(at: sourceURL, to: stagedURL)
      } catch {
        try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
      }
    }

    return (stagedURL, directory)
  }

  private func fileSize(_ url: URL) throws -> Int64? {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let root = scenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController ?? window?.rootViewController

    var top = root
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func finishFileHandoff(_ response: [String: Any]) {
    guard let pending = pendingFileHandoff else { return }
    pendingFileHandoff = nil
    if let stagingURL = pending.stagingURL {
      try? FileManager.default.removeItem(at: stagingURL)
    }
    pending.result(response)
  }

  func documentPicker(
    _ controller: UIDocumentPickerViewController,
    didPickDocumentsAt urls: [URL]
  ) {
    guard let pending = pendingFileHandoff else { return }
    let savedURL = urls.first
    var response: [String: Any] = [
      "status": "saved",
      "savedDisplayName": savedURL?.lastPathComponent ?? pending.exportedURL.lastPathComponent,
    ]
    if let savedURL {
      response["pathOrUri"] = savedURL.absoluteString
    }
    if let bytesCopied = pending.bytesCopied {
      response["bytesCopied"] = bytesCopied
    }
    finishFileHandoff(response)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishFileHandoff(["status": "cancelled"])
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finishFileHandoff(["status": "cancelled"])
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
    // Use the existing-only path: never auto-generate during unwrap, so a
    // transient Keychain lookup failure can't silently mint a fresh key
    // and orphan the existing wrapped blob. Mirrors the Kotlin
    // getExistingRuntimeDekWrappingKey split.
    guard let privateKey = readRuntimeDekPrivateKey() else {
      throw runtimeDekError(
        "Runtime DEK private key not present in Keychain"
      )
    }
    let key = try deriveRuntimeDekAesKey(
      privateKey: privateKey,
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

  /// Returns a snapshot of runtime-DEK-relevant Keychain + device state
  /// for the Crypto storage debug screen. Read-only — must not mutate the
  /// Keychain (no SecItemAdd, no test-unwrap). Mirrors the Kotlin twin in
  /// MainActivity.kt.
  private func collectRuntimeDekDiagnostics() -> [String: Any] {
    var out: [String: Any] = [:]

    // Alias presence — try to read without copying material.
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: runtimeDekPrivateKeyTag,
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

    out["device_state"] = [
      "is_protected_data_available": UIApplication.shared.isProtectedDataAvailable,
    ]

    let device = UIDevice.current
    out["build"] = [
      "manufacturer": "Apple",
      "model": device.model,
      "system_name": device.systemName,
      "system_version": device.systemVersion,
    ]

    return out
  }

  /// Maps an unwrap failure into one of three Dart-facing codes — see the
  /// Kotlin twin in MainActivity.kt for the full contract.
  ///
  /// Terminal: AES.GCM authentication failure (blob no longer valid for
  /// the held key — happened after a Keychain wipe / restore mismatch),
  /// or a malformed blob shape.
  ///
  /// Transient: the only iOS Keychain status that genuinely transient is
  /// `errSecInteractionNotAllowed` (-25308 — accessed before first unlock
  /// after boot). All other Keychain failures imply an unrecoverable
  /// state for the held key.
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
    ]
    SecItemDelete(query as CFDictionary)
  }

  // Returns false when no window — Dart side retries on next reconcile.
  private func setSecureDisplay(enabled: Bool) -> Bool {
    guard let window = activeWindow() else { return false }
    return privacyOverlay.setEnabled(enabled, in: window)
  }

  /// Pick the window to attach the overlay to: prefer the key window of a
  /// foreground-active scene, then any key window, then the first window of
  /// the first foreground-active scene, then any first window. The overlay
  /// only protects the window it's installed on, so picking the right one
  /// matters when scenes are mid-transition.
  private func activeWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    let active = scenes.filter { $0.activationState == .foregroundActive }
    for scene in active {
      if let key = scene.windows.first(where: { $0.isKeyWindow }) {
        return key
      }
    }
    for scene in scenes {
      if let key = scene.windows.first(where: { $0.isKeyWindow }) {
        return key
      }
    }
    return active.first?.windows.first ?? scenes.first?.windows.first
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
