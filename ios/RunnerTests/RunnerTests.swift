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

}
