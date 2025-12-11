import Foundation
import OHHTTPStubsSwift
import OHHTTPStubs
@testable import Kodema

// MARK: - B2Client Test Helpers

extension B2Client {

    /// Create a B2Client for testing (uses OHHTTPStubs for mocking)
    static func createMockClient(
        keyID: String = "test-key-id",
        applicationKey: String = "test-app-key",
        bucketName: String = "test-bucket",
        bucketId: String? = "test-bucket-id",
        partSizeMB: Int? = nil,
        maxRetries: Int = 3
    ) -> B2Client {
        let config = B2Config(
            keyID: keyID,
            applicationKey: applicationKey,
            bucketName: bucketName,
            bucketId: bucketId,
            remotePrefix: nil,
            partSizeMB: partSizeMB,
            maxRetries: maxRetries,
            uploadConcurrency: nil
        )

        // No need for custom URLSession with OHHTTPStubs
        // OHHTTPStubs intercepts all URLSession requests automatically
        return B2Client(
            cfg: config,
            networkTimeout: 30,
            maxRetries: maxRetries,
            session: nil
        )
    }
}

// MARK: - Common Mock Scenarios

struct B2MockScenarios {

    /// Setup successful authorization mock
    static func setupAuthorizationMock() {
        stub(condition: isHost("api.backblazeb2.com") && pathEndsWith("b2_authorize_account")) { _ in
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
    }

    /// Setup successful bucket listing mock
    static func setupListBucketsMock(bucketName: String = "test-bucket", bucketId: String = "test-bucket-id") {
        stub(condition: isHost("api001.backblazeb2.com") && { req in
            req.url?.absoluteString.contains("b2_list_buckets") == true
        }) { _ in
            let json = """
            {
                "buckets": [
                    {
                        "accountId": "test-account-id",
                        "bucketId": "\(bucketId)",
                        "bucketName": "\(bucketName)",
                        "bucketType": "allPrivate",
                        "lifecycleRules": [],
                        "revision": 1
                    }
                ]
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Setup successful upload URL mock
    static func setupGetUploadUrlMock() {
        stub(condition: { req in req.url?.path.contains("b2_get_upload_url") == true }) { _ in
            let json = """
            {
                "bucketId": "test-bucket-id",
                "uploadUrl": "https://pod-000-1234-56.backblaze.com/b2api/v1/b2_upload_file/test-upload-token",
                "authorizationToken": "test-upload-auth-token"
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Setup successful file upload mock
    static func setupUploadFileMock(fileName: String = "test-file.txt") {
        stub(condition: { req in req.url?.path.contains("b2_upload_file") == true }) { _ in
            let json = """
            {
                "fileId": "test-file-id",
                "fileName": "\(fileName)",
                "accountId": "test-account-id",
                "bucketId": "test-bucket-id",
                "contentLength": 1024,
                "contentSha1": "da39a3ee5e6b4b0d3255bfef95601890afd80709",
                "contentType": "text/plain",
                "uploadTimestamp": 1234567890000
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Setup successful file list mock
    static func setupListFilesMock(files: [(name: String, id: String)] = []) {
        stub(condition: { req in req.url?.path.contains("b2_list_file") == true }) { _ in
            let filesJSON = files.map { file in
                """
                {
                    "fileId": "\(file.id)",
                    "fileName": "\(file.name)",
                    "contentLength": 1024,
                    "contentSha1": "da39a3ee5e6b4b0d3255bfef95601890afd80709",
                    "contentType": "application/octet-stream",
                    "uploadTimestamp": 1234567890000
                }
                """
            }.joined(separator: ",")

            let json = """
            {
                "files": [\(filesJSON)],
                "nextFileName": null
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Setup 401 Unauthorized error
    static func setupUnauthorizedError() {
        stub(condition: isHost("api.backblazeb2.com") && { req in
            req.url?.absoluteString.contains("b2_authorize_account") == true
        }) { _ in
            let json = """
            {
                "code": "unauthorized",
                "message": "Invalid credentials",
                "status": 401
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 401,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Setup 429 Rate Limited error
    static func setupRateLimitError() {
        stub(condition: { req in req.url?.path.contains("b2api") == true }) { _ in
            let json = """
            {
                "code": "too_many_requests",
                "message": "Rate limited",
                "status": 429
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 429,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Setup 503 Service Unavailable error
    static func setupServiceUnavailableError() {
        stub(condition: { req in req.url?.path.contains("b2api") == true }) { _ in
            let json = """
            {
                "code": "service_unavailable",
                "message": "Service unavailable",
                "status": 503
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 503,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Setup complete successful workflow (auth + bucket + upload)
    static func setupSuccessfulWorkflow() {
        setupAuthorizationMock()
        setupListBucketsMock()
        setupGetUploadUrlMock()
        setupUploadFileMock()
    }

    /// Setup successful file download mock
    static func setupDownloadFileMock(fileName: String = "test/file.txt", content: Data? = nil) {
        let fileContent = content ?? "Test file content".data(using: .utf8)!
        stub(condition: isHost("f001.backblazeb2.com") && { req in
            req.url?.path.contains(fileName) == true
        }) { _ in
            return HTTPStubsResponse(
                data: fileContent,
                statusCode: 200,
                headers: ["Content-Type": "application/octet-stream"]
            )
        }
    }

    /// Setup successful file delete mock
    static func setupDeleteFileMock() {
        stub(condition: { req in req.url?.path.contains("b2_delete_file_version") == true }) { _ in
            let json = """
            {
                "fileId": "test-file-id",
                "fileName": "test/file.txt"
            }
            """
            return HTTPStubsResponse(
                data: json.data(using: .utf8)!,
                statusCode: 200,
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    /// Clean up all mocks
    static func tearDown() {
        HTTPStubs.removeAllStubs()
    }
}

// MARK: - Test Data Helpers

struct B2TestData {

    static func createTempFile(content: String = "test content") -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-\(UUID().uuidString).txt"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try! content.data(using: .utf8)!.write(to: fileURL)
        return fileURL
    }

    static func createTempFile(data: Data) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-\(UUID().uuidString).bin"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try! data.write(to: fileURL)
        return fileURL
    }

    static func cleanup(fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
