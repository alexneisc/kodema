import Testing
import Foundation
@testable import Kodema

@Suite("RemotePath Tests")
struct RemotePathTests {

    // MARK: - Basic Path Tests

    @Test("Build remote path from home directory file")
    func testHomeDirectoryFile() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: nil)

        #expect(remoteName == "Documents/test.txt")
    }

    @Test("Build remote path with nested directories")
    func testNestedDirectories() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/Projects/MyApp/src/main.swift")

        let remoteName = remoteFileName(for: testURL, remotePrefix: nil)

        #expect(remoteName == "Documents/Projects/MyApp/src/main.swift")
    }

    // MARK: - Remote Prefix Tests

    @Test("Build remote path with prefix")
    func testWithRemotePrefix() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: "backup")

        #expect(remoteName == "backup/Documents/test.txt")
    }

    @Test("Build remote path with nested prefix")
    func testWithNestedPrefix() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: "backup/files")

        #expect(remoteName == "backup/files/Documents/test.txt")
    }

    @Test("Handle empty remote prefix")
    func testEmptyPrefix() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: "")

        #expect(remoteName == "Documents/test.txt")
    }

    // MARK: - Non-Home Directory Tests

    @Test("Handle file outside home directory")
    func testNonHomeDirectory() throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: nil)

        // Should use lastPathComponent for non-home files
        #expect(remoteName == "test.txt")
    }

    @Test("Handle file outside home with prefix")
    func testNonHomeWithPrefix() throws {
        let testURL = URL(fileURLWithPath: "/tmp/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: "backup")

        #expect(remoteName == "backup/test.txt")
    }

    // MARK: - Special Character Tests

    @Test("Handle spaces in path")
    func testSpacesInPath() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/My Files/test document.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: nil)

        #expect(remoteName == "Documents/My Files/test document.txt")
    }

    @Test("Handle special characters in filename")
    func testSpecialCharactersInFilename() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/file-name_v2.0.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: nil)

        #expect(remoteName == "Documents/file-name_v2.0.txt")
    }

    // MARK: - Edge Cases

    @Test("Handle file directly in home directory")
    func testFileInHomeRoot() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: nil)

        #expect(remoteName == "test.txt")
    }

    @Test("Handle deep nesting")
    func testDeepNesting() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("a/b/c/d/e/f/g/file.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: nil)

        #expect(remoteName == "a/b/c/d/e/f/g/file.txt")
    }

    @Test("Handle prefix with trailing slash")
    func testPrefixWithTrailingSlash() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: "backup/")

        // Should normalize and not have double slashes
        #expect(!remoteName.contains("//"))
        #expect(remoteName == "backup/Documents/test.txt")
    }

    @Test("Handle prefix with leading slash")
    func testPrefixWithLeadingSlash() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let testURL = home.appendingPathComponent("Documents/test.txt")

        let remoteName = remoteFileName(for: testURL, remotePrefix: "/backup")

        // Should work correctly even with leading slash
        #expect(remoteName == "/backup/Documents/test.txt")
    }
}
