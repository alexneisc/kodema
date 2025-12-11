import Testing
import Foundation
@testable import Kodema

@Suite("SHA1 Tests")
struct SHA1Tests {

    // MARK: - Known Hash Tests

    @Test("Compute SHA1 of empty file")
    func testEmptyFile() throws {
        let tempURL = createTempFile(content: Data())

        let hash = try sha1HexStream(fileURL: tempURL)

        // SHA1 of empty data
        #expect(hash == "da39a3ee5e6b4b0d3255bfef95601890afd80709")

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Compute SHA1 of simple text")
    func testSimpleText() throws {
        let content = "Hello, World!".data(using: .utf8)!
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        // SHA1 of "Hello, World!"
        #expect(hash == "0a0a9f2a6772942557ab5355d76af442f8f65e01")

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Compute SHA1 of known test vector")
    func testKnownVector() throws {
        let content = "The quick brown fox jumps over the lazy dog".data(using: .utf8)!
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        // Well-known SHA1 hash
        #expect(hash == "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Compute SHA1 with different content")
    func testDifferentContent() throws {
        let content1 = "test1".data(using: .utf8)!
        let content2 = "test2".data(using: .utf8)!

        let tempURL1 = createTempFile(content: content1)
        let tempURL2 = createTempFile(content: content2)

        let hash1 = try sha1HexStream(fileURL: tempURL1)
        let hash2 = try sha1HexStream(fileURL: tempURL2)

        // Different content should produce different hashes
        #expect(hash1 != hash2)

        try FileManager.default.removeItem(at: tempURL1)
        try FileManager.default.removeItem(at: tempURL2)
    }

    @Test("Same content produces same hash")
    func testSameContent() throws {
        let content = "identical content".data(using: .utf8)!

        let tempURL1 = createTempFile(content: content)
        let tempURL2 = createTempFile(content: content)

        let hash1 = try sha1HexStream(fileURL: tempURL1)
        let hash2 = try sha1HexStream(fileURL: tempURL2)

        #expect(hash1 == hash2)

        try FileManager.default.removeItem(at: tempURL1)
        try FileManager.default.removeItem(at: tempURL2)
    }

    // MARK: - Large File Tests

    @Test("Compute SHA1 of 1MB file")
    func testLargeFile1MB() throws {
        let size = 1024 * 1024 // 1 MB
        let content = Data(repeating: 0x42, count: size)
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        // Hash should be consistent for same content
        #expect(hash.count == 40) // SHA1 is 160 bits = 40 hex chars
        #expect(!hash.isEmpty)

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Compute SHA1 of 10MB file")
    func testLargeFile10MB() throws {
        let size = 10 * 1024 * 1024 // 10 MB
        let content = Data(repeating: 0x5A, count: size)
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        #expect(hash.count == 40)
        #expect(!hash.isEmpty)

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Compute SHA1 of file larger than buffer")
    func testFileLargerThanBuffer() throws {
        // Default buffer is 8MB, create 16MB file
        let size = 16 * 1024 * 1024
        let content = Data(repeating: 0xAB, count: size)
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        #expect(hash.count == 40)

        // Verify consistency by computing again
        let hash2 = try sha1HexStream(fileURL: tempURL)
        #expect(hash == hash2)

        try FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Custom Buffer Size Tests

    @Test("Compute SHA1 with small buffer size")
    func testSmallBufferSize() throws {
        let content = "Test content for small buffer".data(using: .utf8)!
        let tempURL = createTempFile(content: content)

        let hashDefault = try sha1HexStream(fileURL: tempURL)
        let hashSmallBuffer = try sha1HexStream(fileURL: tempURL, bufferSize: 16)

        // Should produce same hash regardless of buffer size
        #expect(hashDefault == hashSmallBuffer)

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Compute SHA1 with large buffer size")
    func testLargeBufferSize() throws {
        let content = Data(repeating: 0xFF, count: 1024 * 1024) // 1 MB
        let tempURL = createTempFile(content: content)

        let hashDefault = try sha1HexStream(fileURL: tempURL)
        let hashLargeBuffer = try sha1HexStream(fileURL: tempURL, bufferSize: 32 * 1024 * 1024)

        #expect(hashDefault == hashLargeBuffer)

        try FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Binary Data Tests

    @Test("Compute SHA1 of binary data")
    func testBinaryData() throws {
        var content = Data()
        for i in 0..<256 {
            content.append(UInt8(i))
        }

        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        #expect(hash.count == 40)
        #expect(!hash.isEmpty)

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Compute SHA1 of mixed binary data")
    func testMixedBinaryData() throws {
        let content = Data([0x00, 0xFF, 0xAA, 0x55, 0x12, 0x34, 0x56, 0x78])
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        #expect(hash.count == 40)

        try FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - Edge Cases

    @Test("Hash format is lowercase hex")
    func testHashFormatLowercase() throws {
        let content = "test".data(using: .utf8)!
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        // Verify all characters are lowercase hex
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        let hashCharacters = CharacterSet(charactersIn: hash)
        #expect(hexCharacters.isSuperset(of: hashCharacters))

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Hash is exactly 40 characters")
    func testHashLength() throws {
        let testCases = [
            Data(),
            "a".data(using: .utf8)!,
            "short".data(using: .utf8)!,
            String(repeating: "long", count: 100).data(using: .utf8)!,
            Data(repeating: 0xFF, count: 1024 * 1024)
        ]

        for content in testCases {
            let tempURL = createTempFile(content: content)
            let hash = try sha1HexStream(fileURL: tempURL)

            #expect(hash.count == 40, "Hash length should be 40 for all inputs")

            try FileManager.default.removeItem(at: tempURL)
        }
    }

    @Test("Handle file with newlines")
    func testFileWithNewlines() throws {
        let content = "Line 1\nLine 2\nLine 3\n".data(using: .utf8)!
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        #expect(hash.count == 40)
        #expect(!hash.isEmpty)

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Handle file with unicode content")
    func testUnicodeContent() throws {
        let content = "Hello 世界 🌍".data(using: .utf8)!
        let tempURL = createTempFile(content: content)

        let hash = try sha1HexStream(fileURL: tempURL)

        #expect(hash.count == 40)

        try FileManager.default.removeItem(at: tempURL)
    }

    @Test("Single byte changes produce different hash")
    func testSingleByteChange() throws {
        let content1 = "test content".data(using: .utf8)!
        let content2 = "test_content".data(using: .utf8)! // One char different

        let tempURL1 = createTempFile(content: content1)
        let tempURL2 = createTempFile(content: content2)

        let hash1 = try sha1HexStream(fileURL: tempURL1)
        let hash2 = try sha1HexStream(fileURL: tempURL2)

        // Even single byte change should produce completely different hash
        #expect(hash1 != hash2)

        try FileManager.default.removeItem(at: tempURL1)
        try FileManager.default.removeItem(at: tempURL2)
    }

    // MARK: - Error Cases

    @Test("Throw error for non-existent file")
    func testNonExistentFile() throws {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-file-\(UUID().uuidString).txt")

        #expect(throws: Error.self) {
            try sha1HexStream(fileURL: nonExistentURL)
        }
    }

    // MARK: - Helper Functions

    private func createTempFile(content: Data) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-\(UUID().uuidString).tmp"
        let fileURL = tempDir.appendingPathComponent(fileName)

        try! content.write(to: fileURL)

        return fileURL
    }
}
