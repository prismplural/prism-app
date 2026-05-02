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
