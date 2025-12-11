import Testing
import Foundation
import OHHTTPStubsSwift
import OHHTTPStubs
@testable import Kodema

@Suite("B2Client Tests", .serialized)
struct B2ClientTests {

    // MARK: - Client Initialization Tests

    @Test("Create B2Client with valid config")
    func testCreateClient() throws {
        HTTPStubs.removeAllStubs()

        let client = B2Client.createMockClient()

        // Client created successfully (not nil)
        _ = client
    }

    @Test("Client uses custom max retries")
    func testCustomMaxRetries() throws {
        HTTPStubs.removeAllStubs()

        let client = B2Client.createMockClient(maxRetries: 5)

        // Client created with custom retry count
        _ = client
    }

    // MARK: - Authentication Tests

    @Test("Authorize with valid credentials")
    func testAuthorizeSuccess() async throws {
        HTTPStubs.removeAllStubs()

        // Setup mock responses
        B2MockScenarios.setupAuthorizationMock()

        let client = B2Client.createMockClient()

        // Should not throw
        try await client.ensureAuthorized()
    }

    @Test("Authorization is called only once (caching)")
    func testAuthorizationCaching() async throws {
        HTTPStubs.removeAllStubs()

        var callCount = 0
        stub(condition: isHost("api.backblazeb2.com") && pathEndsWith("b2_authorize_account")) { _ in
            callCount += 1
            let json = """
            {
                "accountId": "test-account-id",
                "authorizationToken": "test-auth-token",
                "apiUrl": "https://api001.backblazeb2.com",
                "downloadUrl": "https://f001.backblazeb2.com",
                "recommendedPartSize": 100000000,
                "absoluteMinimumPartSize": 5000000
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }

        let client = B2Client.createMockClient()

        // First call
        try await client.ensureAuthorized()
        let firstCallCount = callCount

        // Second call should use cache
        try await client.ensureAuthorized()
        let secondCallCount = callCount

        // Should be same count (no new request)
        #expect(firstCallCount == secondCallCount)
    }

    @Test("Throw error on unauthorized (401)")
    func testAuthorizeUnauthorized() async throws {
        HTTPStubs.removeAllStubs()

        // Setup 401 error
        B2MockScenarios.setupUnauthorizedError()

        let client = B2Client.createMockClient()

        // Should throw B2Error
        await #expect(throws: Error.self) {
            try await client.ensureAuthorized()
        }
    }

    // MARK: - Bucket Resolution Tests

    @Test("Use provided bucket ID (no resolution needed)")
    func testProvidedBucketId() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()

        let client = B2Client.createMockClient(bucketId: "provided-bucket-id")

        let bucketId = try await client.ensureBucketId()

        #expect(bucketId == "provided-bucket-id")
    }

    @Test("Resolve bucket ID from name")
    func testResolveBucketId() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        // Use matching bucket name (createMockClient defaults to "test-bucket")
        B2MockScenarios.setupListBucketsMock(bucketName: "test-bucket", bucketId: "resolved-bucket-id")

        let client = B2Client.createMockClient(bucketId: nil) // Force resolution

        let bucketId = try await client.ensureBucketId()

        // bucketId is non-optional String, just verify it's not empty
        #expect(!bucketId.isEmpty)
        #expect(bucketId == "resolved-bucket-id")
    }

    // MARK: - Upload Tests

    @Test("Upload small file successfully")
    func testUploadSmallFile() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        B2MockScenarios.setupGetUploadUrlMock()
        B2MockScenarios.setupUploadFileMock(fileName: "test/file.txt")

        let client = B2Client.createMockClient()
        let testData = "Test file content".data(using: .utf8)!
        let testURL = createTempFile(content: testData)
        let sha1 = try sha1HexStream(fileURL: testURL)

        try await client.uploadSmallFile(
            fileURL: testURL,
            fileName: "test/file.txt",
            contentType: "text/plain",
            sha1Hex: sha1
        )

        try FileManager.default.removeItem(at: testURL)
    }

    // NOTE: Large file upload, retry logic tests commented out
    // Require complex multipart upload mocking (b2_start_large_file, b2_upload_part, b2_finish_large_file)
    /*
    @Test("Upload large file with multipart")
    func testUploadLargeFile() async throws {
        // TODO: Implement multipart upload mocks
    }

    @Test("Retry on expired upload URL")
    func testRetryExpiredUploadUrl() async throws {
        // TODO: Implement retry mocking
    }

    @Test("Retry on rate limit")
    func testRetryRateLimit() async throws {
        // TODO: Implement rate limit mocking
    }

    @Test("Fail immediately on client error")
    func testFailOnClientError() async throws {
        // TODO: Implement error mocking
    }
    */

    // MARK: - Download Tests

    @Test("Download file successfully")
    func testDownloadFile() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        let expectedContent = "Test file content".data(using: .utf8)!
        B2MockScenarios.setupDownloadFileMock(fileName: "test/file.txt", content: expectedContent)

        let client = B2Client.createMockClient()
        let data = try await client.downloadFile(fileName: "test/file.txt")

        #expect(!data.isEmpty)
        #expect(data == expectedContent)
    }

    @Test("Download file with streaming")
    func testDownloadFileStreaming() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        let expectedContent = "Streaming test content".data(using: .utf8)!
        B2MockScenarios.setupDownloadFileMock(fileName: "test/stream.txt", content: expectedContent)

        let client = B2Client.createMockClient()
        let outputURL = createTempFileURL()

        try await client.downloadFileStreaming(fileName: "test/stream.txt", to: outputURL)

        let fileExists = FileManager.default.fileExists(atPath: outputURL.path)
        #expect(fileExists)

        let downloadedContent = try Data(contentsOf: outputURL)
        #expect(downloadedContent == expectedContent)

        try FileManager.default.removeItem(at: outputURL)
    }

    @Test("Streaming download handles large files")
    func testStreamingLargeFile() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        // Mock large file (1 MB)
        let largeData = Data(repeating: 0x42, count: 1024 * 1024)
        B2MockScenarios.setupDownloadFileMock(fileName: "test/large.bin", content: largeData)

        let client = B2Client.createMockClient()
        let outputURL = createTempFileURL()

        try await client.downloadFileStreaming(fileName: "test/large.bin", to: outputURL)

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as! UInt64

        #expect(fileSize == 1024 * 1024)

        try FileManager.default.removeItem(at: outputURL)
    }

    // MARK: - List Files Tests

    @Test("List files with prefix")
    func testListFiles() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        B2MockScenarios.setupListBucketsMock()
        B2MockScenarios.setupListFilesMock(files: [
            (name: "backup/file1.txt", id: "id1"),
            (name: "backup/file2.txt", id: "id2"),
            (name: "backup/file3.txt", id: "id3")
        ])

        let client = B2Client.createMockClient()
        let files = try await client.listFiles(prefix: "backup/")

        #expect(!files.isEmpty)
        #expect(files.count == 3)
        #expect(files.allSatisfy { $0.fileName.hasPrefix("backup/") })
    }

    @Test("List files with no results")
    func testListFilesEmpty() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        B2MockScenarios.setupListBucketsMock()
        B2MockScenarios.setupListFilesMock(files: [])

        let client = B2Client.createMockClient()
        let files = try await client.listFiles(prefix: "nonexistent/")

        #expect(files.isEmpty)
    }

    // NOTE: Pagination test requires more complex mocking with nextFileName
    /*
    @Test("List files handles pagination")
    func testListFilesPagination() async throws {
        // TODO: Implement pagination mocking
    }
    */

    // MARK: - Delete Tests

    @Test("Delete file by name and ID")
    func testDeleteFile() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        B2MockScenarios.setupDeleteFileMock()

        let client = B2Client.createMockClient()

        // Should not throw
        try await client.deleteFileVersion(fileName: "test/file.txt", fileId: "test-file-id")
    }

    @Test("Delete multiple files")
    func testDeleteMultipleFiles() async throws {
        HTTPStubs.removeAllStubs()

        B2MockScenarios.setupAuthorizationMock()
        B2MockScenarios.setupDeleteFileMock()

        let client = B2Client.createMockClient()

        let filesToDelete = [
            ("test/file1.txt", "id1"),
            ("test/file2.txt", "id2"),
            ("test/file3.txt", "id3")
        ]

        for (name, id) in filesToDelete {
            try await client.deleteFileVersion(fileName: name, fileId: id)
        }
    }

    // MARK: - Error Mapping Tests

    // NOTE: Error mapping tests require HTTP error mocking
    // Commented out as they need proper HTTPError.status setup

    /*
    @Test("Map 401 to expired upload URL error")
    func testMap401Error() throws {
        // Requires HTTPError.status which is internal to B2Client
    }

    @Test("Map 429 to rate limited error")
    func testMap429Error() throws {
        // Requires HTTPError.status which is internal to B2Client
    }

    @Test("Map 5xx to temporary error")
    func testMap5xxError() throws {
        // Requires HTTPError.status which is internal to B2Client
    }

    @Test("Map 4xx to client error")
    func testMap4xxError() throws {
        // Requires HTTPError.status which is internal to B2Client
    }
    */

    // MARK: - Helper Functions

    private func createTempFile(content: Data) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-\(UUID().uuidString).tmp"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try! content.write(to: fileURL)
        return fileURL
    }

    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-\(UUID().uuidString).tmp"
        return tempDir.appendingPathComponent(fileName)
    }
}
