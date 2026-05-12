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

  // MARK: - SecureDisplayOverlay

  /// The empty-secure-text-field variant (no layer swap) leaves window.layer
  /// untouched, which is why the old implementation silently did nothing
  /// when toggled. This test pins the fix: enabling MUST move window.layer
  /// into the field's secure sublayer, and disabling MUST put it back.
  @MainActor
  func testSecureDisplayOverlayRelocatesWindowLayer() throws {
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

    let originalParent = window.layer.superlayer
    XCTAssertNotNil(originalParent, "Visible window should have a superlayer")

    let overlay = SecureDisplayOverlay()
    overlay.setEnabled(true, in: window)

    XCTAssertTrue(overlay.isInstalled, "Overlay should be installed")
    let secureSuperlayer = window.layer.superlayer
    XCTAssertNotNil(secureSuperlayer)
    XCTAssertNotEqual(
      secureSuperlayer,
      originalParent,
      "window.layer must be re-parented into the secure sublayer"
    )
    XCTAssertEqual(
      secureSuperlayer?.superlayer?.superlayer,
      originalParent,
      "Expected hierarchy: originalParent > field.layer > secureSublayer > window.layer"
    )

    overlay.setEnabled(false, in: window)

    XCTAssertFalse(overlay.isInstalled)
    XCTAssertEqual(
      window.layer.superlayer,
      originalParent,
      "Disabling must restore window.layer's original superlayer"
    )
  }

  @MainActor
  func testSecureDisplayOverlayIsIdempotent() throws {
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

    let overlay = SecureDisplayOverlay()
    overlay.setEnabled(true, in: window)
    let firstSecureSuperlayer = window.layer.superlayer
    overlay.setEnabled(true, in: window)
    XCTAssertEqual(
      window.layer.superlayer,
      firstSecureSuperlayer,
      "Re-enabling should not create a second overlay"
    )

    overlay.setEnabled(false, in: window)
    overlay.setEnabled(false, in: window) // No-op
    XCTAssertFalse(overlay.isInstalled)
  }

  /// Regression: a window swap between install and remove must NOT pull
  /// the new window into the old window's layer hierarchy. The overlay
  /// captures the install-time window and restores exactly that mapping,
  /// then migrates to the new window when re-enabled.
  @MainActor
  func testSecureDisplayOverlayHandlesWindowChange() throws {
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
    let originalParentA = windowA.layer.superlayer

    let windowB = UIWindow(windowScene: scene)
    windowB.frame = UIScreen.main.bounds
    windowB.rootViewController = UIViewController()
    windowB.makeKeyAndVisible()
    let originalParentB = windowB.layer.superlayer

    defer {
      windowA.isHidden = true
      windowB.isHidden = true
    }

    let overlay = SecureDisplayOverlay()
    overlay.setEnabled(true, in: windowA)
    XCTAssertNotEqual(
      windowA.layer.superlayer,
      originalParentA,
      "windowA must be re-parented into the secure sublayer"
    )

    // Re-enable on a DIFFERENT window. The overlay must migrate: A goes
    // back to its original parent, B becomes the protected window.
    overlay.setEnabled(true, in: windowB)
    XCTAssertEqual(
      windowA.layer.superlayer,
      originalParentA,
      "windowA must be restored when overlay migrates away"
    )
    XCTAssertNotEqual(
      windowB.layer.superlayer,
      originalParentB,
      "windowB must now be protected"
    )

    // Disable while the helper is bound to B. windowB must be restored,
    // and windowA must not be touched a second time.
    overlay.setEnabled(false, in: windowB)
    XCTAssertEqual(
      windowB.layer.superlayer,
      originalParentB,
      "windowB must be restored on disable"
    )
    XCTAssertEqual(
      windowA.layer.superlayer,
      originalParentA,
      "windowA must remain at its original parent throughout"
    )
    XCTAssertFalse(overlay.isInstalled)
  }

  /// Calling disable with a different window than the one we installed on
  /// must restore the INSTALLED window, not the passed-in window. This
  /// pins the P1 finding from the Codex review.
  @MainActor
  func testSecureDisplayOverlayDisableIgnoresPassedWindow() throws {
    let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first
    guard let scene else {
      throw XCTSkip("Test host has no UIWindowScene")
    }
    let installed = UIWindow(windowScene: scene)
    installed.frame = UIScreen.main.bounds
    installed.rootViewController = UIViewController()
    installed.makeKeyAndVisible()
    let originalInstalledParent = installed.layer.superlayer

    let bystander = UIWindow(windowScene: scene)
    bystander.frame = UIScreen.main.bounds
    bystander.rootViewController = UIViewController()
    bystander.makeKeyAndVisible()
    let originalBystanderParent = bystander.layer.superlayer

    defer {
      installed.isHidden = true
      bystander.isHidden = true
    }

    let overlay = SecureDisplayOverlay()
    overlay.setEnabled(true, in: installed)
    overlay.setEnabled(false, in: bystander)

    XCTAssertEqual(
      installed.layer.superlayer,
      originalInstalledParent,
      "Installed window must be restored even when disable is called with a different window"
    )
    XCTAssertEqual(
      bystander.layer.superlayer,
      originalBystanderParent,
      "Bystander window must not be touched by an unrelated disable"
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
