import Testing
import Foundation
@testable import Kodema

@Suite("Snapshot Manifest Tests")
struct SnapshotManifestTests {

    // MARK: - Manifest Creation Tests

    @Test("Create manifest with single file")
    func testCreateManifestSingleFile() throws {
        let file = createFileVersion(
            path: "Documents/test.txt",
            size: 1024,
            timestamp: "2024-01-01_120000"
        )

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: [file],
            totalFiles: 1,
            totalBytes: 1024
        )

        #expect(manifest.timestamp == "2024-01-01_120000")
        #expect(manifest.files.count == 1)
        #expect(manifest.totalFiles == 1)
        #expect(manifest.totalBytes == 1024)
    }

    @Test("Create manifest with multiple files")
    func testCreateManifestMultipleFiles() throws {
        let files = [
            createFileVersion(path: "Documents/file1.txt", size: 1024, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Documents/file2.txt", size: 2048, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Documents/file3.txt", size: 4096, timestamp: "2024-01-01_120000")
        ]

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: files,
            totalFiles: 3,
            totalBytes: 7168
        )

        #expect(manifest.files.count == 3)
        #expect(manifest.totalFiles == 3)
        #expect(manifest.totalBytes == 7168)
    }

    @Test("Create empty manifest")
    func testCreateEmptyManifest() throws {
        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: [],
            totalFiles: 0,
            totalBytes: 0
        )

        #expect(manifest.files.isEmpty)
        #expect(manifest.totalFiles == 0)
        #expect(manifest.totalBytes == 0)
    }

    // MARK: - Serialization Tests

    @Test("Serialize manifest to JSON")
    func testSerializeManifest() throws {
        let file = createFileVersion(
            path: "Documents/test.txt",
            size: 1024,
            timestamp: "2024-01-01_120000"
        )

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: [file],
            totalFiles: 1,
            totalBytes: 1024
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData = try encoder.encode(manifest)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        #expect(jsonString.contains("\"timestamp\" : \"2024-01-01_120000\""))
        #expect(jsonString.contains("\"totalFiles\" : 1"))
        #expect(jsonString.contains("\"totalBytes\" : 1024"))
    }

    @Test("Deserialize manifest from JSON")
    func testDeserializeManifest() throws {
        let json = """
        {
          "timestamp": "2024-01-01_120000",
          "createdAt": "2024-01-01T12:00:00Z",
          "files": [
            {
              "path": "Documents/test.txt",
              "size": 1024,
              "modificationDate": "2024-01-01T10:00:00Z",
              "versionTimestamp": "2024-01-01_120000"
            }
          ],
          "totalFiles": 1,
          "totalBytes": 1024
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = json.data(using: .utf8)!
        let manifest = try decoder.decode(SnapshotManifest.self, from: data)

        #expect(manifest.timestamp == "2024-01-01_120000")
        #expect(manifest.files.count == 1)
        #expect(manifest.totalFiles == 1)
        #expect(manifest.totalBytes == 1024)
        #expect(manifest.files[0].path == "Documents/test.txt")
    }

    @Test("Round-trip serialization")
    func testRoundTripSerialization() throws {
        let originalFiles = [
            createFileVersion(path: "Documents/file1.txt", size: 1024, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Documents/file2.txt", size: 2048, timestamp: "2024-01-01_120000")
        ]

        let original = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: originalFiles,
            totalFiles: 2,
            totalBytes: 3072
        )

        // Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(original)

        // Decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SnapshotManifest.self, from: jsonData)

        #expect(restored.timestamp == original.timestamp)
        #expect(restored.files.count == original.files.count)
        #expect(restored.totalFiles == original.totalFiles)
        #expect(restored.totalBytes == original.totalBytes)
    }

    // MARK: - FileVersionInfo Tests

    @Test("Create file version without encryption")
    func testFileVersionWithoutEncryption() throws {
        let file = createFileVersion(
            path: "Documents/test.txt",
            size: 1024,
            timestamp: "2024-01-01_120000"
        )

        #expect(file.path == "Documents/test.txt")
        #expect(file.size == 1024)
        #expect(file.versionTimestamp == "2024-01-01_120000")
        #expect(file.encrypted == nil)
        #expect(file.encryptedPath == nil)
        #expect(file.encryptedSize == nil)
    }

    @Test("Create file version with encryption")
    func testFileVersionWithEncryption() throws {
        let file = FileVersionInfo(
            path: "Documents/test.txt",
            size: 1024,
            modificationDate: Date(),
            versionTimestamp: "2024-01-01_120000",
            encrypted: true,
            encryptedPath: "aGVsbG8=",
            encryptedSize: 1100
        )

        #expect(file.encrypted == true)
        #expect(file.encryptedPath == "aGVsbG8=")
        #expect(file.encryptedSize == 1100)
        #expect(file.size == 1024) // Original size
    }

    @Test("Serialize file version with encryption")
    func testSerializeFileVersionWithEncryption() throws {
        let file = FileVersionInfo(
            path: "Documents/test.txt",
            size: 1024,
            modificationDate: Date(),
            versionTimestamp: "2024-01-01_120000",
            encrypted: true,
            encryptedPath: "aGVsbG8=",
            encryptedSize: 1100
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(file)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        #expect(jsonString.contains("\"encrypted\""))
        #expect(jsonString.contains("\"encryptedPath\""))
        #expect(jsonString.contains("\"encryptedSize\""))
    }

    // MARK: - Manifest with Large Dataset Tests

    @Test("Handle manifest with 1000 files")
    func testManifestWith1000Files() throws {
        let files = (0..<1000).map { i in
            createFileVersion(
                path: "Documents/file\(i).txt",
                size: Int64(i * 1024),
                timestamp: "2024-01-01_120000"
            )
        }

        let totalBytes = files.reduce(0) { $0 + $1.size }

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: files,
            totalFiles: 1000,
            totalBytes: totalBytes
        )

        #expect(manifest.files.count == 1000)
        #expect(manifest.totalFiles == 1000)

        // Test serialization performance
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(manifest)

        #expect(jsonData.count > 0)
    }

    @Test("Handle manifest with mixed file types")
    func testManifestWithMixedFileTypes() throws {
        let files = [
            createFileVersion(path: "Documents/text.txt", size: 1024, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Pictures/image.jpg", size: 2048000, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Videos/video.mp4", size: 10485760, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Code/script.swift", size: 4096, timestamp: "2024-01-01_120000")
        ]

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: files,
            totalFiles: 4,
            totalBytes: files.reduce(0) { $0 + $1.size }
        )

        #expect(manifest.files.count == 4)
    }

    // MARK: - Edge Cases

    @Test("Handle very large file size")
    func testVeryLargeFileSize() throws {
        let largeSize: Int64 = 10_737_418_240 // 10 GB
        let file = createFileVersion(
            path: "Videos/large.mp4",
            size: largeSize,
            timestamp: "2024-01-01_120000"
        )

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: [file],
            totalFiles: 1,
            totalBytes: largeSize
        )

        #expect(manifest.totalBytes == largeSize)
    }

    @Test("Handle special characters in paths")
    func testSpecialCharactersInPaths() throws {
        let files = [
            createFileVersion(path: "Documents/file with spaces.txt", size: 1024, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Documents/file-with-dashes.txt", size: 1024, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Documents/file_with_underscores.txt", size: 1024, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Documents/file.with.dots.txt", size: 1024, timestamp: "2024-01-01_120000")
        ]

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: files,
            totalFiles: 4,
            totalBytes: 4096
        )

        // Serialize and deserialize
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(SnapshotManifest.self, from: jsonData)

        #expect(restored.files[0].path == "Documents/file with spaces.txt")
        #expect(restored.files[1].path == "Documents/file-with-dashes.txt")
    }

    @Test("Handle zero-byte files in manifest")
    func testZeroByteFiles() throws {
        let files = [
            createFileVersion(path: "Documents/empty.txt", size: 0, timestamp: "2024-01-01_120000"),
            createFileVersion(path: "Documents/also-empty.txt", size: 0, timestamp: "2024-01-01_120000")
        ]

        let manifest = SnapshotManifest(
            timestamp: "2024-01-01_120000",
            createdAt: Date(),
            files: files,
            totalFiles: 2,
            totalBytes: 0
        )

        #expect(manifest.totalBytes == 0)
        #expect(manifest.files.allSatisfy { $0.size == 0 })
    }

    // MARK: - Timestamp Tests

    @Test("Generate timestamp format")
    func testGenerateTimestamp() throws {
        let timestamp = generateTimestamp()

        // Format should be yyyy-MM-dd_HHmmss
        #expect(timestamp.count == 17) // "2024-01-01_120000"
        #expect(timestamp.contains("_"))
        #expect(timestamp.contains("-"))
    }

    @Test("Parse timestamp format")
    func testParseTimestamp() throws {
        let timestampString = "2024-01-15_143022"

        let date = parseTimestamp(timestampString)

        #expect(date != nil)

        // Verify round-trip
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.timeZone = TimeZone.current
        let regenerated = formatter.string(from: date!)

        #expect(regenerated == timestampString)
    }

    @Test("Parse invalid timestamp returns nil")
    func testParseInvalidTimestamp() throws {
        let invalidTimestamps = [
            "invalid",
            "not-a-date",
            "12:00:00"
        ]

        for timestamp in invalidTimestamps {
            let date = parseTimestamp(timestamp)
            #expect(date == nil, "Expected nil for: \(timestamp)")
        }
    }

    // MARK: - Helper Functions

    private func createFileVersion(path: String, size: Int64, timestamp: String) -> FileVersionInfo {
        return FileVersionInfo(
            path: path,
            size: size,
            modificationDate: Date(),
            versionTimestamp: timestamp,
            encrypted: nil,
            encryptedPath: nil,
            encryptedSize: nil
        )
    }
}
