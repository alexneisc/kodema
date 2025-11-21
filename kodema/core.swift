import Foundation
import Yams
import CommonCrypto
import Darwin

// MARK: - Models: Config

struct B2Config: Decodable {
    let keyID: String
    let applicationKey: String
    let bucketName: String
    let bucketId: String?
    let remotePrefix: String?
    let partSizeMB: Int?
    let maxRetries: Int?
    let uploadConcurrency: Int?
}

struct TimeoutsConfig: Decodable {
    let icloudDownloadSeconds: Int?
    let networkSeconds: Int?
    let overallUploadSeconds: Int?
}

struct IncludeConfig: Decodable {
    let folders: [String]?
}

struct FiltersConfig: Decodable {
    let excludeHidden: Bool?
    let minSizeBytes: Int64?
    let maxSizeBytes: Int64?
    let excludeGlobs: [String]?
}

struct AppConfig: Decodable {
    let b2: B2Config
    let timeouts: TimeoutsConfig?
    let include: IncludeConfig?
    let filters: FiltersConfig?
}

// MARK: - FileItem

struct FileItem {
    let url: URL
    let status: String   // "Local" | "Cloud" | "Error"
    let size: Int64?
}

// MARK: - Constants / ANSI colors

let localColor = "\u{001B}[32m"
let cloudColor = "\u{001B}[33;1m"
let errorColor = "\u{001B}[31;1m"
let resetColor = "\u{001B}[0m"

// MARK: - Helpers

extension URL {
    func expandedTilde() -> URL {
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let expanded = path.replacingOccurrences(of: "~", with: home)
            return URL(fileURLWithPath: expanded)
        }
        return self
    }
}

func readConfigURL(from arguments: [String]) -> URL {
    if arguments.count > 1 {
        return URL(fileURLWithPath: arguments[1]).expandedTilde()
    } else {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("kodema")
            .appendingPathComponent("config.yml")
        return defaultPath
    }
}

func loadConfig(from url: URL) throws -> AppConfig {
    let data = try Data(contentsOf: url)
    guard let yamlString = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 in config"])
    }
    let decoder = YAMLDecoder()
    return try decoder.decode(AppConfig.self, from: yamlString)
}

// MARK: - Timeout helpers (safe under strict concurrency)

enum TimeoutError: Error {
    case timedOut
}

// У цих обгортках не створюємо конкурентних тасків, щоб не вимагати Sendable для захоплених об’єктів.
func withTimeoutVoid(_ seconds: TimeInterval, _ operation: () async throws -> Void) async throws {
    try await operation()
}

func withTimeoutDataResponse(_ seconds: TimeInterval, _ operation: () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
    try await operation()
}

func withTimeoutBool(_ seconds: TimeInterval, _ operation: () async -> Bool) async throws -> Bool {
    await operation()
}

// MARK: - iCloud status and control (no isDownloadedKey)

func checkFileStatus(url: URL) -> String {
    do {
        let resourceValues = try url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ])
        guard let isUbiquitous = resourceValues.isUbiquitousItem, isUbiquitous else {
            return "Local"
        }
        if let status = resourceValues.ubiquitousItemDownloadingStatus,
           status == URLUbiquitousItemDownloadingStatus.current {
            return "Local"
        } else {
            return "Cloud"
        }
    } catch {
        return "Error"
    }
}

func waitForICloudDownload(url: URL, timeoutSeconds: Int) async -> Bool {
    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
    while Date() < deadline {
        do {
            let values = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            let isUbiquitous = values.isUbiquitousItem ?? false
            let status = values.ubiquitousItemDownloadingStatus
            if !isUbiquitous {
                return true
            }
            if status == URLUbiquitousItemDownloadingStatus.current {
                return true
            }
        } catch {
            // ignore and retry
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        if Task.isCancelled { return false }
    }
    return false
}

func startDownloadIfNeeded(url: URL) {
    do {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        if values.isUbiquitousItem == true {
            if values.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
    } catch {
        // ignore
    }
}

func evictIfUbiquitous(url: URL) {
    do {
        let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
        if values.isUbiquitousItem == true {
            try FileManager.default.evictUbiquitousItem(at: url)
        }
    } catch {
        // non-fatal
    }
}

func fileSize(url: URL) -> Int64? {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? NSNumber {
            return size.int64Value
        }
        return nil
    } catch {
        return nil
    }
}

// MARK: - Scanning

func buildFoldersToScan(from config: AppConfig) -> [URL] {
    if let custom = config.include?.folders, !custom.isEmpty {
        return custom.map { URL(fileURLWithPath: $0).expandedTilde() }
    } else {
        return [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        ]
    }
}

func scanFolder(url: URL, excludeHidden: Bool) -> [FileItem] {
    var files: [FileItem] = []
    let fileManager = FileManager.default
    let options: FileManager.DirectoryEnumerationOptions = excludeHidden ? [.skipsHiddenFiles] : []
    guard let enumerator = fileManager.enumerator(at: url,
                                                  includingPropertiesForKeys: [
                                                    .isRegularFileKey,
                                                    .isUbiquitousItemKey,
                                                    .ubiquitousItemDownloadingStatusKey,
                                                    .fileSizeKey
                                                  ],
                                                  options: options) else {
        return []
    }
    for case let fileURL as URL in enumerator {
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                let status = checkFileStatus(url: fileURL)
                let size = fileSize(url: fileURL)
                files.append(FileItem(url: fileURL, status: status, size: size))
            }
        } catch {
            continue
        }
    }
    return files
}

// MARK: - Glob helpers (exclude patterns)

private func expandTilde(in pattern: String) -> String {
    guard pattern.hasPrefix("~") else { return pattern }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return pattern.replacingOccurrences(of: "~", with: home)
}

private func containsGlobMeta(_ s: String) -> Bool {
    // Basic glob meta detection: *, ?, [abc]
    return s.contains("*") || s.contains("?") || s.contains("[")
}

private func shouldExclude(url: URL, patterns: [String]) -> Bool {
    let path = url.path

    for raw in patterns {
        // 1) Expand ~
        var pattern = expandTilde(in: raw)

        // Normalize repeated slashes, etc. (but do not remove wildcard characters)
        // Using NSString to avoid touching wildcard syntax.
        pattern = (pattern as NSString).standardizingPath

        // 2) Directory shorthands
        //   - ends with "/**" => treat as "exclude everything under this prefix"
        if pattern.hasSuffix("/**") {
            let base = String(pattern.dropLast(3)) // remove "/**"
            if path.hasPrefix(base.hasSuffix("/") ? base : base + "/") {
                return true
            }
            continue
        }
        //   - ends with "/" => same as "exclude everything under this prefix"
        if pattern.hasSuffix("/") {
            let base = pattern
            if path.hasPrefix(base) {
                return true
            }
            continue
        }

        // 3) If no glob meta => treat as exact file or directory prefix
        if !containsGlobMeta(pattern) {
            // exact file
            if path == pattern { return true }
            // directory prefix
            if path.hasPrefix(pattern + "/") { return true }
            continue
        }

        // 4) Fallback to fnmatch for real globs
        let matched: Bool = pattern.withCString { pat in
            path.withCString { str in
                // FNM_CASEFOLD for case-insensitive match on typical macOS filesystems.
                // Not using FNM_PATHNAME so that '*' may match '/' (more flexible for "**" style).
                fnmatch(pat, str, FNM_CASEFOLD) == 0
            }
        }
        if matched { return true }
    }
    return false
}

func applyFilters(_ items: [FileItem], filters: FiltersConfig?) -> [FileItem] {
    var result = items
    if let minSize = filters?.minSizeBytes {
        result = result.filter { ($0.size ?? 0) >= minSize }
    }
    if let maxSize = filters?.maxSizeBytes {
        result = result.filter { ($0.size ?? 0) <= maxSize }
    }
    if let patterns = filters?.excludeGlobs, !patterns.isEmpty {
        result = result.filter { !shouldExclude(url: $0.url, patterns: patterns) }
    }
    return result
}

// MARK: - URLSession async helpers

enum HTTPError: Error, CustomStringConvertible {
    case invalidURL
    case unexpectedResponse(String)
    case status(Int, String)

    var description: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unexpectedResponse(let s): return "Unexpected response: \(s)"
        case .status(let code, let body): return "HTTP \(code): \(body)"
        }
    }
}

extension URLSession {
    func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        // Розраховуємо на timeouts із конфігурації сесії; тут без додаткових конкурентних обгорток.
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.unexpectedResponse("No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw HTTPError.status(http.statusCode, text)
        }
        return (data, http)
    }
}

// MARK: - SHA1 (streamed)

func sha1HexStream(fileURL: URL, bufferSize: Int = 8 * 1024 * 1024) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var ctx = CC_SHA1_CTX()
    CC_SHA1_Init(&ctx)
    while true {
        let data = try handle.read(upToCount: bufferSize) ?? Data()
        if !data.isEmpty {
            data.withUnsafeBytes { buf in
                _ = CC_SHA1_Update(&ctx, buf.baseAddress, CC_LONG(data.count))
            }
        } else {
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1_Final(&digest, &ctx)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }
}

// MARK: - B2 Errors and retry policy

enum B2Error: Error, CustomStringConvertible {
    case unauthorized(String)
    case expiredUploadUrl(String)
    case temporary(Int, String)
    case client(Int, String)
    case invalidResponse(String)
    case underlying(Error)

    var description: String {
        switch self {
        case .unauthorized(let m): return "Unauthorized: \(m)"
        case .expiredUploadUrl(let m): return "Expired Upload URL: \(m)"
        case .temporary(let code, let m): return "Temporary \(code): \(m)"
        case .client(let code, let m): return "Client \(code): \(m)"
        case .invalidResponse(let m): return "Invalid Response: \(m)"
        case .underlying(let e): return "Underlying: \(e)"
        }
    }
}

func mapHTTPErrorToB2(_ error: Error) -> B2Error {
    if case let HTTPError.status(code, body) = error {
        if code == 401 {
            if body.localizedCaseInsensitiveContains("expired") ||
               body.localizedCaseInsensitiveContains("token") ||
               body.localizedCaseInsensitiveContains("unauthorized") {
                return .expiredUploadUrl(body)
            } else {
                return .unauthorized(body)
            }
        } else if (500...599).contains(code) {
            return .temporary(code, body)
        } else if (400...499).contains(code) {
            return .client(code, body)
        }
    }
    return .underlying(error)
}

// MARK: - B2 API Models

struct B2AuthorizeResponse: Decodable {
    let absoluteMinimumPartSize: Int
    let accountId: String
    let apiUrl: String
    let authorizationToken: String
    let downloadUrl: String
    let recommendedPartSize: Int
}

struct B2Bucket: Decodable {
    let accountId: String
    let bucketId: String
    let bucketName: String
    let bucketType: String
}

struct B2ListBucketsResponse: Decodable {
    let buckets: [B2Bucket]
}

struct B2GetUploadUrlResponse: Decodable {
    let bucketId: String
    let uploadUrl: String
    let authorizationToken: String
}

struct B2StartLargeFileResponse: Decodable {
    let fileId: String
}

struct B2GetUploadPartUrlResponse: Decodable {
    let fileId: String
    let uploadUrl: String
    let authorizationToken: String
}

struct B2FinishLargeFileResponse: Decodable {
    let fileId: String
    let fileName: String
}

// MARK: - B2 Client (async)

final class B2Client {
    private let cfg: B2Config
    private let networkTimeout: TimeInterval
    private let maxRetries: Int
    private let session: URLSession

    private var authorize: B2AuthorizeResponse?
    private var bucketId: String?

    init(cfg: B2Config, networkTimeout: TimeInterval, maxRetries: Int) {
        self.cfg = cfg
        self.networkTimeout = networkTimeout
        self.maxRetries = max(0, maxRetries)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = networkTimeout
        config.timeoutIntervalForResource = networkTimeout
        self.session = URLSession(configuration: config)
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
                    break
                case .temporary:
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
                        break
                    case .temporary:
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
}

// MARK: - Remote path building

func remoteFileName(for localURL: URL, remotePrefix: String?) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let localPath = localURL.path
    var relative = localPath
    if localPath.hasPrefix(home.path) {
        relative = String(localPath.dropFirst(home.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    } else {
        relative = localURL.lastPathComponent
    }
    if let prefix = remotePrefix, !prefix.isEmpty {
        return "\(prefix)/\(relative)".replacingOccurrences(of: "//", with: "/")
    } else {
        return relative
    }
}

// MARK: - Content-Type utility (very basic)

func guessContentType(for url: URL) -> String? {
    return nil // use b2/x-auto
}

// MARK: - Main flow (async)

@main
struct Runner {
    static func main() async {
        do {
            // Load config
            let configURL = readConfigURL(from: CommandLine.arguments)
            let config = try loadConfig(from: configURL)

            let excludeHidden = config.filters?.excludeHidden ?? true
            let folders = buildFoldersToScan(from: config)

            // Scan
            var allFiles: [FileItem] = []
            for folder in folders {
                allFiles.append(contentsOf: scanFolder(url: folder, excludeHidden: excludeHidden))
            }
            allFiles = applyFilters(allFiles, filters: config.filters)

            // Sort: Local first, then Cloud
            let sortedFiles = allFiles.sorted {
                if $0.status == $1.status {
                    return $0.url.lastPathComponent.lowercased() < $1.url.lastPathComponent.lowercased()
                }
                return $0.status == "Local"
            }

            // Prepare B2 client
            let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
            let overallUploadTimeout = TimeInterval(config.timeouts?.overallUploadSeconds ?? 7200)
            let icloudTimeout = config.timeouts?.icloudDownloadSeconds ?? 1800
            let maxRetries = config.b2.maxRetries ?? 3
            let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)

            // Decide part size
            let recommendedPartSize = (try? await client.recommendedPartSizeBytes()) ?? (100 * 1024 * 1024)
            let configuredPartSizeMB = config.b2.partSizeMB
            let partSizeBytes = max((configuredPartSizeMB ?? (recommendedPartSize / (1024*1024))), (try? await client.absoluteMinimumPartSizeBytes()) ?? (5 * 1024 * 1024)) * 1024 * 1024
            let uploadConcurrency = max(1, config.b2.uploadConcurrency ?? 1)

            // Upload loop
            for file in sortedFiles {
                do {
                    let url = file.url
                    let status = file.status

                    if status == "Cloud" {
                        print("\(cloudColor)Downloading from iCloud:\(resetColor) \(url.path)")
                        startDownloadIfNeeded(url: url)
                        let ok = try await withTimeoutBool(TimeInterval(icloudTimeout)) {
                            await waitForICloudDownload(url: url, timeoutSeconds: icloudTimeout)
                        }
                        if !ok {
                            print("\(errorColor)Timeout downloading iCloud file:\(resetColor) \(url.path)")
                            continue
                        }
                    } else if status == "Error" {
                        print("\(errorColor)Skipping due to error status:\(resetColor) \(url.path)")
                        continue
                    }

                    let remoteName = remoteFileName(for: url, remotePrefix: config.b2.remotePrefix)
                    let contentType = guessContentType(for: url)

                    let size = file.size ?? (fileSize(url: url) ?? 0)
                    let smallFileThreshold: Int64 = 5 * 1024 * 1024 * 1024 // 5 GB

                    print("⬆️  Uploading to B2: \(remoteName) (\(size) bytes)")

                    let start = Date()
                    if size <= smallFileThreshold {
                        let sha1 = try sha1HexStream(fileURL: url)
                        try await withTimeoutVoid(overallUploadTimeout) {
                            try await client.uploadSmallFile(fileURL: url, fileName: remoteName, contentType: contentType, sha1Hex: sha1)
                        }
                    } else {
                        try await withTimeoutVoid(overallUploadTimeout) {
                            try await client.uploadLargeFile(fileURL: url, fileName: remoteName, contentType: contentType, partSize: partSizeBytes, concurrency: uploadConcurrency)
                        }
                    }
                    let elapsed = Date().timeIntervalSince(start)
                    if elapsed > overallUploadTimeout {
                        print("\(errorColor)Warning: upload exceeded overall timeout threshold\(resetColor)")
                    } else {
                        print("\(localColor)✅ Uploaded:\(resetColor) \(remoteName)")
                    }

                    if status == "Cloud" {
                        print("🧹 Evicting local copy for iCloud file: \(url.lastPathComponent)")
                        evictIfUbiquitous(url: url)
                    }
                } catch TimeoutError.timedOut {
                    print("\(errorColor)Timed out:\(resetColor) \(file.url.path)")
                } catch {
                    print("\(errorColor)Upload failed:\(resetColor) \(file.url.path) — \(error)")
                }
            }
        } catch {
            print("\(errorColor)Fatal error:\(resetColor) \(error)")
            exit(1)
        }
    }
}
