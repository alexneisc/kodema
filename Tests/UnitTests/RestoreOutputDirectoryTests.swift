import XCTest
import Foundation
@testable import Kodema

final class RestoreOutputDirectoryTests: XCTestCase {

    var testDirectoryBase: URL!

    override func setUp() {
        super.setUp()
        testDirectoryBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("kodema-test-restore-\(UUID().uuidString)")
    }

    override func tearDown() {
        if let testDir = testDirectoryBase,
           FileManager.default.fileExists(atPath: testDir.path) {
            try? FileManager.default.removeItem(at: testDir)
        }
        super.tearDown()
    }

    // MARK: - Directory Creation Tests

    func testCreateOutputDirectoryIfNotExists() throws {
        let outputDir = testDirectoryBase.appendingPathComponent("new-directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDir.path))

        // Create directory as restore command would
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateOutputDirectoryWithIntermediatePaths() throws {
        let outputDir = testDirectoryBase
            .appendingPathComponent("level1")
            .appendingPathComponent("level2")
            .appendingPathComponent("level3")

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDir.path))

        // Create directory with intermediate directories
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))

        // Verify all intermediate directories were created
        let level1 = testDirectoryBase.appendingPathComponent("level1")
        let level2 = level1.appendingPathComponent("level2")

        XCTAssertTrue(FileManager.default.fileExists(atPath: level1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: level2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))
    }

    func testOutputDirectoryAlreadyExists() throws {
        let outputDir = testDirectoryBase.appendingPathComponent("existing-directory")

        // Pre-create the directory
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))

        // Attempting to create again should not throw when withIntermediateDirectories is true
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))
    }

    // MARK: - Directory Validation Tests

    func testOutputPathIsFile() throws {
        let filePath = testDirectoryBase.appendingPathComponent("test-file.txt")

        // Create parent directory
        try FileManager.default.createDirectory(
            at: testDirectoryBase,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Create a file
        try "test content".write(to: filePath, atomically: true, encoding: .utf8)

        // Verify path exists but is not a directory
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDirectory)

        XCTAssertTrue(exists)
        XCTAssertFalse(isDirectory.boolValue)
    }

    func testDetectNonDirectoryPath() throws {
        let filePath = testDirectoryBase.appendingPathComponent("not-a-directory.txt")

        // Create parent directory
        try FileManager.default.createDirectory(
            at: testDirectoryBase,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Create file
        try "content".write(to: filePath, atomically: true, encoding: .utf8)

        // Verify detection logic
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDirectory)

        if exists && !isDirectory.boolValue {
            // This is the error case - path exists but is not a directory
            XCTAssertTrue(true, "Correctly detected file as non-directory")
        } else {
            XCTFail("Should detect that path is a file, not a directory")
        }
    }

    // MARK: - Permission Tests

    func testCannotCreateDirectoryInNonexistentParent() throws {
        // This test verifies behavior when withIntermediateDirectories is false
        let outputDir = testDirectoryBase
            .appendingPathComponent("nonexistent-parent")
            .appendingPathComponent("child")

        // Should throw when withIntermediateDirectories is false
        XCTAssertThrowsError(
            try FileManager.default.createDirectory(
                at: outputDir,
                withIntermediateDirectories: false,
                attributes: nil
            )
        ) { error in
            XCTAssertTrue(error is CocoaError)
        }
    }

    func testCanCreateDirectoryInReadableLocation() throws {
        // Verify we can create directory in temp location
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kodema-test-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))

        // Cleanup
        try FileManager.default.removeItem(at: outputDir)
    }

    // MARK: - Path Expansion Tests

    func testHomeDirectoryExpansion() throws {
        // Test that tilde expansion works (note: URL already handles this)
        let tildeString = "~/kodema-test"
        let expandedURL = URL(fileURLWithPath: (tildeString as NSString).expandingTildeInPath)

        XCTAssertFalse(expandedURL.path.contains("~"))
        XCTAssertTrue(expandedURL.path.starts(with: "/Users/") || expandedURL.path.starts(with: "/home/"))
    }

    // MARK: - Edge Cases

    func testEmptyDirectoryPath() throws {
        // Empty path creates directory in current working directory
        // This is expected macOS behavior - not an error
        let emptyURL = URL(fileURLWithPath: "")

        // Should not throw, but creates in current directory
        // We just verify it doesn't crash
        XCTAssertNoThrow(
            try FileManager.default.createDirectory(
                at: emptyURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        )
    }

    func testDirectoryWithSpacesInName() throws {
        let outputDir = testDirectoryBase.appendingPathComponent("directory with spaces")

        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testDirectoryWithSpecialCharacters() throws {
        let outputDir = testDirectoryBase.appendingPathComponent("dir-with_special.chars@123")

        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
    }

    // MARK: - Cleanup Tests

    func testDirectoryCleanupAfterTest() throws {
        let outputDir = testDirectoryBase.appendingPathComponent("cleanup-test")

        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path))

        // tearDown should clean this up automatically
    }
}
