import Foundation
import CommonCrypto

// MARK: - B2 Client (async)

final class B2Client {
    private let cfg: B2Config
    private let networkTimeout: TimeInterval
    private let maxRetries: Int
    private let session: URLSession

    private var authorize: B2AuthorizeResponse?
    private var bucketId: String?

    init(cfg: B2Config, networkTimeout: TimeInterval, maxRetries: Int, session: URLSession? = nil) {
        self.cfg = cfg
        self.networkTimeout = networkTimeout
        self.maxRetries = max(0, maxRetries)

        if let customSession = session {
            self.session = customSession
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = networkTimeout
            config.timeoutIntervalForResource = networkTimeout
            self.session = URLSession(configuration: config)
        }
    }

    func ensureAuthorized() async throws {
        if authorize != nil { return }
        guard let url = URL(string: "https://api.backblazeb2.com/b2api/v2/b2_authorize_account") else {
            throw HTTPError.invalidURL
        }
        let credentials = "\(cfg.keyID):\(cfg.applicationKey)"
        guard let basic = credentials.data(using: .utf8)?.base64EncodedString() else {
            throw HTTPError.unexpectedResponse("Failed to base64 credentials")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue("Basic \(basic)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await session.data(for: req, timeout: networkTimeout)
            authorize = try JSONDecoder().decode(B2AuthorizeResponse.self, from: data)
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    func ensureBucketId() async throws -> String {
        if let b = cfg.bucketId { return b }
        if let cached = bucketId { return cached }
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        guard let url = URL(string: "\(auth.apiUrl)/b2api/v2/b2_list_buckets") else {
            throw HTTPError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["accountId": auth.accountId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, _) = try await session.data(for: req, timeout: networkTimeout)
            let list = try JSONDecoder().decode(B2ListBucketsResponse.self, from: data)
            guard let bucket = list.buckets.first(where: { $0.bucketName == cfg.bucketName }) else {
                throw B2Error.invalidResponse("Bucket \(cfg.bucketName) not found")
            }
            bucketId = bucket.bucketId
            return bucket.bucketId
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    func getUploadUrl() async throws -> B2GetUploadUrlResponse {
        try await ensureAuthorized()
        let bid = try await ensureBucketId()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        guard let url = URL(string: "\(auth.apiUrl)/b2api/v2/b2_get_upload_url") else {
            throw HTTPError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["bucketId": bid]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, _) = try await session.data(for: req, timeout: networkTimeout)
            return try JSONDecoder().decode(B2GetUploadUrlResponse.self, from: data)
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    func startLargeFile(fileName: String, contentType: String?) async throws -> String {
        try await ensureAuthorized()
        let bid = try await ensureBucketId()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        guard let url = URL(string: "\(auth.apiUrl)/b2api/v2/b2_start_large_file") else {
            throw HTTPError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "bucketId": bid,
            "fileName": fileName
        ]
        if let contentType = contentType {
            body["contentType"] = contentType
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, _) = try await session.data(for: req, timeout: networkTimeout)
            let resp = try JSONDecoder().decode(B2StartLargeFileResponse.self, from: data)
            return resp.fileId
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    func getUploadPartUrl(fileId: String) async throws -> B2GetUploadPartUrlResponse {
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        guard let url = URL(string: "\(auth.apiUrl)/b2api/v2/b2_get_upload_part_url") else {
            throw HTTPError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["fileId": fileId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (data, _) = try await session.data(for: req, timeout: networkTimeout)
            return try JSONDecoder().decode(B2GetUploadPartUrlResponse.self, from: data)
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    func finishLargeFile(fileId: String, partSha1Array: [String]) async throws {
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        guard let url = URL(string: "\(auth.apiUrl)/b2api/v2/b2_finish_large_file") else {
            throw HTTPError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["fileId": fileId, "partSha1Array": partSha1Array]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            _ = try await session.data(for: req, timeout: networkTimeout)
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    // Small file upload with precomputed SHA1 and HTTPBodyStream (no full RAM load)
    func uploadSmallFile(fileURL: URL, fileName: String, contentType: String?, sha1Hex: String) async throws {
        var lastError: Error?
        for attempt in 0...maxRetries {
            do {
                let upload = try await getUploadUrl()
                var req = URLRequest(url: URL(string: upload.uploadUrl)!)
                req.httpMethod = "POST"
                req.addValue(upload.authorizationToken, forHTTPHeaderField: "Authorization")
                req.addValue(fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName, forHTTPHeaderField: "X-Bz-File-Name")
                req.addValue(sha1Hex, forHTTPHeaderField: "X-Bz-Content-Sha1")
                req.addValue(contentType ?? "b2/x-auto", forHTTPHeaderField: "Content-Type")

                let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                let size = (attr[.size] as? NSNumber)?.int64Value ?? 0
                req.addValue(String(size), forHTTPHeaderField: "Content-Length")
                req.httpBodyStream = InputStream(url: fileURL)

                _ = try await session.data(for: req, timeout: networkTimeout)
                return
            } catch {
                let mapped = mapHTTPErrorToB2(error)
                lastError = mapped
                switch mapped {
                case .expiredUploadUrl:
                    // Expired upload URL - retry immediately with new URL
                    break
                case .rateLimited(let retryAfter, _):
                    // Rate limit hit - wait with exponential backoff
                    let waitSeconds = retryAfter ?? Int(pow(2.0, Double(attempt)))
                    print("  \(errorColor)⚠️  Rate limit reached, waiting \(waitSeconds)s before retry...\(resetColor)")
                    try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                case .temporary:
                    // Temporary server error - exponential backoff
                    try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * pow(2.0, Double(attempt))))
                default:
                    if attempt == maxRetries { throw mapped }
                }
                if attempt == maxRetries { throw mapped }
            }
        }
        if let err = lastError { throw err }
    }

    // Large file upload (parts)
    func uploadLargeFile(fileURL: URL, fileName: String, contentType: String?, partSize: Int, concurrency: Int) async throws {
        let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let totalSize = (attr[.size] as? NSNumber)?.int64Value ?? 0

        let fileId = try await startLargeFile(fileName: fileName, contentType: contentType)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var partNumber = 1
        var partSha1Array: [String] = []
        var offset: Int64 = 0

        while offset < totalSize {
            let remaining = totalSize - offset
            let chunkSize = Int(min(Int64(partSize), remaining))

            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: chunkSize) ?? Data()
            let sha1 = data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> String in
                var ctx = CC_SHA1_CTX()
                CC_SHA1_Init(&ctx)
                _ = CC_SHA1_Update(&ctx, buf.baseAddress, CC_LONG(data.count))
                var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
                CC_SHA1_Final(&digest, &ctx)
                return digest.map { String(format: "%02x", $0) }.joined()
            }

            var lastError: Error?
            for attempt in 0...maxRetries {
                do {
                    let up = try await getUploadPartUrl(fileId: fileId)
                    var req = URLRequest(url: URL(string: up.uploadUrl)!)
                    req.httpMethod = "POST"
                    req.addValue(up.authorizationToken, forHTTPHeaderField: "Authorization")
                    req.addValue("\(partNumber)", forHTTPHeaderField: "X-Bz-Part-Number")
                    req.addValue(sha1, forHTTPHeaderField: "X-Bz-Content-Sha1")
                    req.addValue(String(data.count), forHTTPHeaderField: "Content-Length")
                    req.httpBody = data

                    _ = try await session.data(for: req, timeout: networkTimeout)
                    partSha1Array.append(sha1)
                    break
                } catch {
                    let mapped = mapHTTPErrorToB2(error)
                    lastError = mapped
                    switch mapped {
                    case .expiredUploadUrl:
                        // Expired upload URL - retry immediately with new URL
                        break
                    case .rateLimited(let retryAfter, _):
                        // Rate limit hit - wait with exponential backoff
                        let waitSeconds = retryAfter ?? Int(pow(2.0, Double(attempt)))
                        print("  \(errorColor)⚠️  Rate limit reached, waiting \(waitSeconds)s before retry (part \(partNumber))...\(resetColor)")
                        try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
                    case .temporary:
                        // Temporary server error - exponential backoff
                        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * pow(2.0, Double(attempt))))
                    default:
                        if attempt == maxRetries { throw mapped }
                    }
                    if attempt == maxRetries { throw mapped }
                }
            }

            offset += Int64(chunkSize)
            partNumber += 1
        }

        try await finishLargeFile(fileId: fileId, partSha1Array: partSha1Array)
    }

    func recommendedPartSizeBytes() async throws -> Int {
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        return auth.recommendedPartSize
    }

    func absoluteMinimumPartSizeBytes() async throws -> Int {
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        return auth.absoluteMinimumPartSize
    }

    // List files with prefix
    func listFiles(prefix: String, maxFileCount: Int = 10000) async throws -> [B2FileInfo] {
        try await ensureAuthorized()
        let bid = try await ensureBucketId()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }

        var allFiles: [B2FileInfo] = []
        var startFileName: String? = nil

        repeat {
            guard let url = URL(string: "\(auth.apiUrl)/b2api/v2/b2_list_file_names") else {
                throw HTTPError.invalidURL
            }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
            req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

            var body: [String: Any] = [
                "bucketId": bid,
                "maxFileCount": maxFileCount,
                "prefix": prefix
            ]
            if let start = startFileName {
                body["startFileName"] = start
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

            do {
                let (data, _) = try await session.data(for: req, timeout: networkTimeout)
                let response = try JSONDecoder().decode(B2ListFileNamesResponse.self, from: data)
                allFiles.append(contentsOf: response.files)
                startFileName = response.nextFileName
            } catch {
                throw mapHTTPErrorToB2(error)
            }
        } while startFileName != nil

        return allFiles
    }

    // Delete file version
    func deleteFileVersion(fileName: String, fileId: String) async throws {
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }
        guard let url = URL(string: "\(auth.apiUrl)/b2api/v2/b2_delete_file_version") else {
            throw HTTPError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")
        req.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["fileName": fileName, "fileId": fileId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            _ = try await session.data(for: req, timeout: networkTimeout)
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    // Download file by name (loads into RAM - use for small files like manifests)
    func downloadFile(fileName: String) async throws -> Data {
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }

        // B2 download URL format: {downloadUrl}/file/{bucketName}/{fileName}
        let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        guard let url = URL(string: "\(auth.downloadUrl)/file/\(cfg.bucketName)/\(encodedFileName)") else {
            throw HTTPError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await session.data(for: req, timeout: networkTimeout)
            return data
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }

    // Download file directly to disk (streaming - efficient for large files)
    func downloadFileStreaming(fileName: String, to localURL: URL) async throws {
        try await ensureAuthorized()
        guard let auth = authorize else { throw B2Error.invalidResponse("No authorize data") }

        // B2 download URL format: {downloadUrl}/file/{bucketName}/{fileName}
        let encodedFileName = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName
        guard let url = URL(string: "\(auth.downloadUrl)/file/\(cfg.bucketName)/\(encodedFileName)") else {
            throw HTTPError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.addValue(auth.authorizationToken, forHTTPHeaderField: "Authorization")

        do {
            // Download to temporary location
            let (tempURL, _) = try await session.download(for: req)

            // Move to final destination
            // Remove existing file if present (for overwrite case)
            if FileManager.default.fileExists(atPath: localURL.path) {
                try FileManager.default.removeItem(at: localURL)
            }

            try FileManager.default.moveItem(at: tempURL, to: localURL)
        } catch {
            throw mapHTTPErrorToB2(error)
        }
    }
}
