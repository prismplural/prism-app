import Flutter
@testable import Runner
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testBackupExclusionValidatorAllowsPathsInsideContainer() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let path = root.appendingPathComponent("Library/prism.db").path

    let validated = try BackupExclusionPathValidator.validatedURL(
      for: path,
      containerRoot: root
    )

    XCTAssertEqual(validated.path, path)
  }

  func testBackupExclusionValidatorRejectsTraversalOutsideContainer() throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = base.appendingPathComponent("Container", isDirectory: true)
    let outside = base.appendingPathComponent("outside.db").path
    let traversing = root.appendingPathComponent("../outside.db").path

    XCTAssertThrowsError(
      try BackupExclusionPathValidator.validatedURL(for: traversing, containerRoot: root)
    ) { error in
      XCTAssertEqual(error as? BackupExclusionPathError, .outsideAppContainer)
    }
    XCTAssertThrowsError(
      try BackupExclusionPathValidator.validatedURL(for: outside, containerRoot: root)
    ) { error in
      XCTAssertEqual(error as? BackupExclusionPathError, .outsideAppContainer)
    }
  }

  func testBackupExclusionValidatorRejectsSiblingPrefix() throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = base.appendingPathComponent("App", isDirectory: true)
    let sibling = base.appendingPathComponent("App-Backup/secret.db").path

    XCTAssertThrowsError(
      try BackupExclusionPathValidator.validatedURL(for: sibling, containerRoot: root)
    ) { error in
      XCTAssertEqual(error as? BackupExclusionPathError, .outsideAppContainer)
    }
  }

  func testBackupExclusionValidatorRejectsSymlinkEscape() throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = base.appendingPathComponent("Container", isDirectory: true)
    let outside = base.appendingPathComponent("Outside", isDirectory: true)
    let link = root.appendingPathComponent("LinkedOutside", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: outside,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: link,
      withDestinationURL: outside
    )

    XCTAssertThrowsError(
      try BackupExclusionPathValidator.validatedURL(
        for: link.appendingPathComponent("secret.db").path,
        containerRoot: root
      )
    ) { error in
      XCTAssertEqual(error as? BackupExclusionPathError, .outsideAppContainer)
    }
  }

  func testBackupExclusionValidatorRejectsRelativePaths() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    XCTAssertThrowsError(
      try BackupExclusionPathValidator.validatedURL(for: "Library/prism.db", containerRoot: root)
    ) { error in
      XCTAssertEqual(error as? BackupExclusionPathError, .invalidPath)
    }
  }

  func testSensitiveFileProtectionPolicyDoesNotDowngradeProtectedFiles() throws {
    XCTAssertFalse(
      SensitiveFileProtection.shouldUpgrade(.complete),
      "Complete protection must not be downgraded"
    )
    XCTAssertFalse(
      SensitiveFileProtection.shouldUpgrade(.completeUnlessOpen),
      "Complete-unless-open protection must not be downgraded"
    )
    XCTAssertFalse(
      SensitiveFileProtection.shouldUpgrade(.completeUntilFirstUserAuthentication),
      "The baseline protection class should be left unchanged"
    )
    XCTAssertTrue(SensitiveFileProtection.shouldUpgrade(.none))
    XCTAssertTrue(SensitiveFileProtection.shouldUpgrade(nil))
  }

  func testSensitiveFileProtectionAppliesBaselineToDirectory() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )

    try SensitiveFileProtection.applyMinimumProtection(to: root)

    let protection = try SensitiveFileProtection.protectionClass(for: root)
    XCTAssertTrue(
      SensitiveFileProtection.meetsMinimum(protection),
      "Expected \(root.path) to have at least baseline iOS file protection"
    )
  }

  // MARK: - PrivacyOverlay

  private func privacyOverlayView(in window: UIWindow) -> UIView? {
    return window.subviews.first { subview in
      subview.backgroundColor == .black
        && subview.isUserInteractionEnabled == true
        && subview.accessibilityElementsHidden == true
    }
  }

  // willResignActive must install before iOS snapshots — applicationState
  // is still .active then, so reconcile alone would skip the install.
  @MainActor
  func testPrivacyOverlayInstallsOnWillResignActive() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    overlay.setEnabled(true, in: window)
    XCTAssertFalse(
      overlay.isOverlayInstalled,
      "Overlay should not appear until a capture/background event"
    )

    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )

    XCTAssertTrue(overlay.isOverlayInstalled)
    let overlayView = try XCTUnwrap(
      privacyOverlayView(in: window),
      "Overlay view should be a subview of the protected window"
    )
    XCTAssertEqual(overlayView.frame, window.bounds)
  }

  @MainActor
  func testPrivacyOverlayRemovesOnDidBecomeActive() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    overlay.setEnabled(true, in: window)
    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    XCTAssertTrue(overlay.isOverlayInstalled)

    NotificationCenter.default.post(
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    XCTAssertFalse(overlay.isOverlayInstalled)
    XCTAssertNil(
      privacyOverlayView(in: window),
      "Overlay subview must be removed from the window"
    )
  }

  @MainActor
  func testPrivacyOverlayDisableRemovesOverlayAndIgnoresEvents() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    overlay.setEnabled(true, in: window)
    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    XCTAssertTrue(overlay.isOverlayInstalled)

    overlay.setEnabled(false, in: window)
    XCTAssertFalse(overlay.isOverlayInstalled)
    XCTAssertNil(privacyOverlayView(in: window))

    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    XCTAssertFalse(
      overlay.isOverlayInstalled,
      "Disabled overlay must ignore willResignActive"
    )
  }

  @MainActor
  func testPrivacyOverlayHandlesWindowChange() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let windowA = UIWindow(windowScene: scene)
    windowA.frame = UIScreen.main.bounds
    windowA.rootViewController = UIViewController()
    windowA.makeKeyAndVisible()

    let windowB = UIWindow(windowScene: scene)
    windowB.frame = UIScreen.main.bounds
    windowB.rootViewController = UIViewController()
    windowB.makeKeyAndVisible()

    defer {
      windowA.isHidden = true
      windowB.isHidden = true
    }

    let overlay = PrivacyOverlay()
    overlay.setEnabled(true, in: windowA)
    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    XCTAssertNotNil(privacyOverlayView(in: windowA))

    overlay.setEnabled(true, in: windowB)
    XCTAssertNil(
      privacyOverlayView(in: windowA),
      "Old window must not retain the overlay after migration"
    )

    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    XCTAssertNotNil(
      privacyOverlayView(in: windowB),
      "New window should receive the overlay on the next event"
    )
    XCTAssertNil(
      privacyOverlayView(in: windowA),
      "Old window must remain clean throughout"
    )
  }

  @MainActor
  func testPrivacyOverlayIsIdempotent() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    overlay.setEnabled(true, in: window)
    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )
    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )

    let overlayCount = window.subviews.filter { subview in
      subview.backgroundColor == .black
        && subview.isUserInteractionEnabled == true
        && subview.accessibilityElementsHidden == true
    }.count
    XCTAssertEqual(overlayCount, 1, "Re-firing willResignActive must not stack overlays")
  }

  // Regression: layer reparenting was the iOS 26 trait-visitor crash.
  @MainActor
  func testPrivacyOverlayDoesNotMutateLayerHierarchy() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let originalSuperlayer = window.layer.superlayer

    let overlay = PrivacyOverlay()
    overlay.setEnabled(true, in: window)
    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )

    XCTAssertEqual(
      window.layer.superlayer,
      originalSuperlayer,
      "PrivacyOverlay must not reparent window.layer (regression: Flutter #181120)"
    )
    overlay.setEnabled(false, in: window)
    XCTAssertEqual(
      window.layer.superlayer,
      originalSuperlayer,
      "Layer hierarchy must remain stable after disable"
    )
  }

  @MainActor
  func testPrivacyOverlayBlocksTouches() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    let underlying = UIView(frame: window.bounds)
    underlying.backgroundColor = .red
    let rootVC = UIViewController()
    rootVC.view.addSubview(underlying)
    window.rootViewController = rootVC
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    overlay.setEnabled(true, in: window)
    NotificationCenter.default.post(
      name: UIApplication.willResignActiveNotification,
      object: nil
    )

    let overlayView = try XCTUnwrap(privacyOverlayView(in: window))
    XCTAssertTrue(
      overlayView.isUserInteractionEnabled,
      "Overlay must intercept taps so users can't blind-mutate hidden UI"
    )
    let center = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
    let hit = window.hitTest(center, with: nil)
    XCTAssertIdentical(
      hit, overlayView,
      "Touches at the overlay's location must land on the overlay, not the underlying view"
    )
  }

  @MainActor
  func testPrivacyOverlayInstallsWhenCaptured() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    var fakeCaptured = false
    overlay.isScreenCapturedProvider = { fakeCaptured }
    overlay.setEnabled(true, in: window)
    XCTAssertFalse(
      overlay.isOverlayInstalled,
      "Overlay should not appear while not captured and app is active"
    )

    fakeCaptured = true
    NotificationCenter.default.post(
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )

    XCTAssertTrue(overlay.isOverlayInstalled)
    XCTAssertNotNil(privacyOverlayView(in: window))
  }

  @MainActor
  func testPrivacyOverlayRemovesWhenCaptureEnds() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    var fakeCaptured = true
    overlay.isScreenCapturedProvider = { fakeCaptured }
    overlay.setEnabled(true, in: window)
    XCTAssertTrue(overlay.isOverlayInstalled)

    fakeCaptured = false
    NotificationCenter.default.post(
      name: UIScreen.capturedDidChangeNotification,
      object: nil
    )

    XCTAssertFalse(overlay.isOverlayInstalled)
    XCTAssertNil(privacyOverlayView(in: window))
  }

  @MainActor
  func testPrivacyOverlayPersistsWhileCapturedDespiteDidBecomeActive() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let window = UIWindow(windowScene: scene)
    window.frame = UIScreen.main.bounds
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    defer { window.isHidden = true }

    let overlay = PrivacyOverlay()
    var fakeCaptured = true
    overlay.isScreenCapturedProvider = { fakeCaptured }
    overlay.setEnabled(true, in: window)
    XCTAssertTrue(overlay.isOverlayInstalled)

    NotificationCenter.default.post(
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )

    XCTAssertTrue(
      overlay.isOverlayInstalled,
      "Overlay must remain mounted while the screen is still captured"
    )
  }

  func testSensitiveFileProtectionUsesParentForFutureDatabaseFile() throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let futureDatabase = root.appendingPathComponent("prism.db")

    try SensitiveFileProtection.applyMinimumProtection(to: futureDatabase)

    let status = try SensitiveFileProtection.protectionStatus(for: futureDatabase)
    XCTAssertEqual(status["exists"] as? Bool, false)
    XCTAssertEqual(status["target_path"] as? String, root.path)
    XCTAssertEqual(status["meets_minimum"] as? Bool, true)
  }

}
