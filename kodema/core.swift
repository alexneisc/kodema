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

struct RetentionConfig: Decodable {
    let hourly: Int?    // keep all versions for last N hours
    let daily: Int?     // keep daily versions for last N days
    let weekly: Int?    // keep weekly versions for last N weeks
    let monthly: Int?   // keep monthly versions for last N months
}

struct BackupConfig: Decodable {
    let remotePrefix: String?
    let retention: RetentionConfig?
    let manifestUpdateInterval: Int?  // Update manifest every N files
}

struct MirrorConfig: Decodable {
    let remotePrefix: String?
}

struct AppConfig: Decodable {
    let b2: B2Config
    let timeouts: TimeoutsConfig?
    let include: IncludeConfig?
    let filters: FiltersConfig?
    let backup: BackupConfig?
    let mirror: MirrorConfig?
}

// MARK: - FileItem

struct FileItem {
    let url: URL
    let status: String   // "Local" | "Cloud" | "Error"
    let size: Int64?
    let modificationDate: Date?
}

// MARK: - Snapshot & Versioning

struct FileVersionInfo: Codable {
    let path: String           // relative path from scan root
    let size: Int64
    let modificationDate: Date
    let versionTimestamp: String  // "2024-11-27_143022"
}

struct SnapshotManifest: Codable {
    let timestamp: String      // "2024-11-27_143022"
    let createdAt: Date
    let files: [FileVersionInfo]
    let totalFiles: Int
    let totalBytes: Int64
}

// MARK: - Restore Models

struct RestoreOptions {
    var snapshotTimestamp: String?
    var paths: [String]               // File/folder filters
    var outputDirectory: URL?
    var force: Bool
    var listSnapshots: Bool
}

struct FileConflict {
    let relativePath: String
    let existingURL: URL
    let existingSize: Int64?
    let existingMtime: Date?
    let restoreSize: Int64
    let restoreMtime: Date
}

// MARK: - Constants / ANSI colors

let localColor = "\u{001B}[32m"
let cloudColor = "\u{001B}[33;1m"
let errorColor = "\u{001B}[31;1m"
let resetColor = "\u{001B}[0m"
let boldColor = "\u{001B}[1m"
let dimColor = "\u{001B}[2m"

// MARK: - Progress Tracker

actor ProgressTracker {
    private(set) var totalFiles: Int = 0
    private(set) var completedFiles: Int = 0
    private(set) var failedFiles: Int = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var uploadedBytes: Int64 = 0
    private var currentFileName: String = ""
    private let startTime: Date = Date()
    private var cursorHidden: Bool = false

    func initialize(totalFiles: Int, totalBytes: Int64) {
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        // Hide cursor at start
        print("\u{001B}[?25l", terminator: "")
        fflush(stdout)
        cursorHidden = true
    }

    func startFile(name: String) {
        currentFileName = name
    }

    func fileCompleted(bytes: Int64) {
        completedFiles += 1
        uploadedBytes += bytes
        currentFileName = ""
    }

    func fileFailed() {
        failedFiles += 1
        currentFileName = ""
    }

    func currentProgress() -> (completed: Int, failed: Int, total: Int, uploadedBytes: Int64, totalBytes: Int64, currentFile: String, elapsed: TimeInterval) {
        return (completedFiles, failedFiles, totalFiles, uploadedBytes, totalBytes, currentFileName, Date().timeIntervalSince(startTime))
    }

    func printProgress() {
        let (completed, failed, total, uploaded, totalSize, currentFile, elapsed) = currentProgress()
        let remaining = total - completed - failed
        let percentage = totalSize > 0 ? Double(uploaded) / Double(totalSize) * 100 : 0

        // Progress bar
        let barWidth = 30
        let filledWidth = Int(Double(barWidth) * percentage / 100.0)
        let bar = String(repeating: "█", count: filledWidth) + String(repeating: "░", count: barWidth - filledWidth)

        // Format bytes
        let uploadedStr = formatBytes(uploaded)
        let totalStr = formatBytes(totalSize)

        // Calculate speed
        let speed = elapsed > 0 ? Double(uploaded) / elapsed : 0
        let speedStr = formatBytes(Int64(speed)) + "/s"

        // ETA
        let remainingBytes = totalSize - uploaded
        let eta = speed > 0 ? Double(remainingBytes) / speed : 0
        let etaStr = formatDuration(eta)

        // Clear line and print progress bar
        print("\r\u{001B}[K", terminator: "")
        print("\(boldColor)[\(bar)] \(String(format: "%.1f", percentage))%\(resetColor) | " +
              "\(localColor)\(completed) ✅\(resetColor) " +
              "\(errorColor)\(failed) ❌\(resetColor) " +
              "\(dimColor)\(remaining) ⏳\(resetColor) | " +
              "\(uploadedStr)/\(totalStr) | " +
              "\(speedStr) | " +
              "ETA: \(etaStr)", terminator: "")

        // Show current file on next line if exists
        if !currentFile.isEmpty {
            print("\n\u{001B}[K\(dimColor)⬆️  \(currentFile)\(resetColor)", terminator: "")
            print("\u{001B}[1A", terminator: "") // Move cursor back up to progress bar line
        } else {
            // Clear the line below if no current file
            print("\n\u{001B}[K", terminator: "")
            print("\u{001B}[1A", terminator: "")
        }

        fflush(stdout)
    }

    func printFinal() {
        let (completed, failed, total, uploaded, totalSize, _, elapsed) = currentProgress()

        // Show cursor again
        if cursorHidden {
            print("\n\n\u{001B}[?25h", terminator: "")
            fflush(stdout)
        }

        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("\(boldColor)Upload Complete!\(resetColor)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("  \(localColor)✅ Successful:\(resetColor) \(completed) files")
        print("  \(errorColor)❌ Failed:\(resetColor) \(failed) files")
        print("  📦 Uploaded: \(formatBytes(uploaded)) of \(formatBytes(totalSize))")
        print("  ⏱️ Time: \(formatDuration(elapsed))")
        if elapsed > 0 {
            let avgSpeed = Double(uploaded) / elapsed
            print("  🚀 Average speed: \(formatBytes(Int64(avgSpeed)))/s")
        }
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
    }
}

func formatBytes(_ bytes: Int64) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unitIndex = 0

    while value >= 1024 && unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }

    if unitIndex == 0 {
        return "\(Int(value)) \(units[unitIndex])"
    } else {
        return String(format: "%.2f %@", value, units[unitIndex])
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds.isInfinite || seconds.isNaN {
        return "∞"
    }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60

    if hours > 0 {
        return String(format: "%dh %dm %ds", hours, minutes, secs)
    } else if minutes > 0 {
        return String(format: "%dm %ds", minutes, secs)
    } else {
        return String(format: "%ds", secs)
    }
}

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
    // Look for --config or -c flag
    for i in 0..<arguments.count {
        if (arguments[i] == "--config" || arguments[i] == "-c") && i + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[i + 1]).expandedTilde()
        }
    }

    // Default config path
    let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config")
        .appendingPathComponent("kodema")
        .appendingPathComponent("config.yml")
    return defaultPath
}

func hasDryRunFlag(from arguments: [String]) -> Bool {
    return arguments.contains("--dry-run") || arguments.contains("-n")
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

enum ConfigError: Error, CustomStringConvertible {
    case missingFolders
    case noFoldersConfigured
    case validationFailed

    var description: String {
        switch self {
        case .missingFolders:
            return "No folders configured. Please specify folders to backup in config.yml under 'include.folders'"
        case .noFoldersConfigured:
            return "No folders configured in include.folders"
        case .validationFailed:
            return "Configuration validation failed"
        }
    }
}

// These wrappers don't create concurrent tasks to avoid requiring Sendable for captured objects.
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

func getAvailableDiskSpace(for path: String = NSHomeDirectory()) -> Int64? {
    do {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        // Fallback to regular available capacity
        let fallbackValues = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        if let capacity = fallbackValues.volumeAvailableCapacity {
            return Int64(capacity)
        }
        return nil
    } catch {
        return nil
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

func fileModificationDate(url: URL) -> Date? {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.modificationDate] as? Date
    } catch {
        return nil
    }
}

// MARK: - Scanning

func buildFoldersToScan(from config: AppConfig) throws -> [URL] {
    guard let custom = config.include?.folders, !custom.isEmpty else {
        throw ConfigError.missingFolders
    }
    return custom.map { URL(fileURLWithPath: $0).expandedTilde() }
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
                                                    .fileSizeKey,
                                                    .contentModificationDateKey
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
                let mtime = fileModificationDate(url: fileURL)
                files.append(FileItem(url: fileURL, status: status, size: size, modificationDate: mtime))
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
        // Relies on timeouts from session configuration; no additional concurrent wrappers here.
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

// MARK: - Restore Errors

enum RestoreError: Error, CustomStringConvertible {
    case noSnapshotsFound
    case invalidSnapshot(String)
    case invalidSelection
    case pathNotFound(String)
    case cancelled
    case downloadFailed(String, Error)
    case writeFailed(String, Error)
    case destinationNotWritable(String)
    case insufficientDiskSpace(Int64)
    case integrityCheckFailed(String)

    var description: String {
        switch self {
        case .noSnapshotsFound: return "No snapshots found in backup"
        case .invalidSnapshot(let ts): return "Invalid snapshot: \(ts)"
        case .invalidSelection: return "Invalid selection"
        case .pathNotFound(let p): return "Path not found in snapshot: \(p)"
        case .cancelled: return "Restore cancelled by user"
        case .downloadFailed(let f, let e): return "Failed to download \(f): \(e)"
        case .writeFailed(let f, let e): return "Failed to write \(f): \(e)"
        case .destinationNotWritable(let p): return "Destination not writable: \(p)"
        case .insufficientDiskSpace(let needed): return "Insufficient disk space (need \(formatBytes(needed)))"
        case .integrityCheckFailed(let f): return "Integrity check failed: \(f)"
        }
    }
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

struct B2FileInfo: Decodable {
    let fileId: String
    let fileName: String
    let contentLength: Int64
    let uploadTimestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case fileId
        case fileName
        case contentLength
        case uploadTimestamp
    }
}

struct B2ListFileNamesResponse: Decodable {
    let files: [B2FileInfo]
    let nextFileName: String?
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

// MARK: - Snapshot helpers

func generateTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HHmmss"
    formatter.timeZone = TimeZone.current
    return formatter.string(from: Date())
}

func parseTimestamp(_ timestamp: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd_HHmmss"
    formatter.timeZone = TimeZone.current
    return formatter.date(from: timestamp)
}

// Fetch latest snapshot manifest from B2
func fetchLatestManifest(client: B2Client, remotePrefix: String) async throws -> SnapshotManifest? {
    // List all snapshot manifests
    let manifestFiles = try await client.listFiles(prefix: "\(remotePrefix)/snapshots/")

    // Filter to only manifest.json files
    let manifests = manifestFiles.filter { $0.fileName.hasSuffix("/manifest.json") }

    if manifests.isEmpty {
        return nil
    }

    // Sort by timestamp (latest first)
    let sorted = manifests.sorted { file1, file2 in
        // Extract timestamp from path: backup/snapshots/{timestamp}/manifest.json
        let components1 = file1.fileName.split(separator: "/")
        let components2 = file2.fileName.split(separator: "/")

        guard components1.count >= 3, components2.count >= 3 else {
            return false
        }

        let timestamp1 = String(components1[components1.count - 2])
        let timestamp2 = String(components2[components2.count - 2])

        return timestamp1 > timestamp2
    }

    // Download and parse the latest manifest
    guard let latest = sorted.first else {
        return nil
    }

    let data = try await client.downloadFile(fileName: latest.fileName)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SnapshotManifest.self, from: data)
}

// Upload manifest to B2
func uploadManifest(client: B2Client, manifestFiles: [FileVersionInfo], timestamp: String, remotePrefix: String) async throws {
    let manifest = SnapshotManifest(
        timestamp: timestamp,
        createdAt: Date(),
        files: manifestFiles,
        totalFiles: manifestFiles.count,
        totalBytes: manifestFiles.reduce(0) { $0 + $1.size }
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let manifestData = try encoder.encode(manifest)

    let manifestPath = "\(remotePrefix)/snapshots/\(timestamp)/manifest.json"
    let manifestTempURL = FileManager.default.temporaryDirectory.appendingPathComponent("manifest_\(timestamp).json")
    try manifestData.write(to: manifestTempURL)
    defer { try? FileManager.default.removeItem(at: manifestTempURL) }

    let manifestSha1 = try sha1HexStream(fileURL: manifestTempURL)
    try await client.uploadSmallFile(fileURL: manifestTempURL, fileName: manifestPath, contentType: "application/json", sha1Hex: manifestSha1)
}

// Upload success marker to indicate completed backup
func uploadSuccessMarker(client: B2Client, timestamp: String, remotePrefix: String) async throws {
    let markerPath = "\(remotePrefix)/.success-markers/\(timestamp)"
    let markerContent = "completed"
    let markerData = markerContent.data(using: .utf8)!

    let markerTempURL = FileManager.default.temporaryDirectory.appendingPathComponent("success_\(timestamp).txt")
    try markerData.write(to: markerTempURL)
    defer { try? FileManager.default.removeItem(at: markerTempURL) }

    let markerSha1 = try sha1HexStream(fileURL: markerTempURL)
    try await client.uploadSmallFile(fileURL: markerTempURL, fileName: markerPath, contentType: "text/plain", sha1Hex: markerSha1)
}

// Build relative path from home or scan root
func buildRelativePath(for localURL: URL, from scanRoots: [URL]) -> String {
    let localPath = localURL.path

    // Try to find matching scan root
    for root in scanRoots {
        if localPath.hasPrefix(root.path) {
            let relative = String(localPath.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative
        }
    }

    // Fallback to home-relative
    let home = FileManager.default.homeDirectoryForCurrentUser
    if localPath.hasPrefix(home.path) {
        return String(localPath.dropFirst(home.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    return localURL.lastPathComponent
}

// Check if file needs backup based on size + mtime comparison with latest snapshot
func fileNeedsBackup(file: FileItem, latestManifest: SnapshotManifest?, relativePath: String) -> Bool {
    guard let localSize = file.size, let localMtime = file.modificationDate else {
        return true // If we can't get info, assume it needs backup
    }

    // If no previous manifest exists, this is the first backup
    guard let manifest = latestManifest else {
        return true
    }

    // Find the file in the previous manifest
    guard let previousVersion = manifest.files.first(where: { $0.path == relativePath }) else {
        return true // File didn't exist in previous backup
    }

    // Compare size and modification time (with 1 second tolerance for filesystem precision)
    let sizeMatch = previousVersion.size == localSize
    let mtimeMatch = abs(previousVersion.modificationDate.timeIntervalSince(localMtime)) < 1.0

    // File needs backup only if it has changed
    return !(sizeMatch && mtimeMatch)
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

// MARK: - Signal handling

// Global flag for graceful shutdown
// Access is protected by shutdownLock - safe to disable concurrency checking
private nonisolated(unsafe) var shutdownRequested: Bool = false
private let shutdownLock = NSLock()

func setShutdownRequested() {
    shutdownLock.lock()
    shutdownRequested = true
    shutdownLock.unlock()
}

func isShutdownRequested() -> Bool {
    shutdownLock.lock()
    defer { shutdownLock.unlock() }
    return shutdownRequested
}

func setupSignalHandlers() {
    // Handle SIGINT (Control+C)
    signal(SIGINT) { _ in
        print("\n\n\(errorColor)⚠️  Shutdown requested... finishing current file\(resetColor)")
        fflush(stdout)
        setShutdownRequested()
    }

    // Handle SIGTERM
    signal(SIGTERM) { _ in
        print("\n\n\(errorColor)⚠️  Shutdown requested... finishing current file\(resetColor)")
        fflush(stdout)
        setShutdownRequested()
    }
}

// MARK: - Main flow (async)

// MARK: - Help message

func printVersion() {
    print("Kodema v\(KODEMA_VERSION)")
}

func printHelp() {
    print("\n\(boldColor)Kodema v\(KODEMA_VERSION) - iCloud to Backblaze B2 Backup Tool\(resetColor)")
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
    print("\nUsage:")
    print("  kodema <command> [options]")
    print("\nCommands:")
    print("  \(boldColor)backup\(resetColor)       Incremental backup with snapshots and versioning")
    print("  \(boldColor)mirror\(resetColor)       Simple mirroring (uploads all files)")
    print("  \(boldColor)cleanup\(resetColor)      Clean up old backup versions per retention policy")
    print("  \(boldColor)restore\(resetColor)      Restore files from backup snapshots")
    print("  \(boldColor)test-config\(resetColor)  Validate configuration without uploading")
    print("  \(boldColor)list\(resetColor)         List all folders in iCloud Drive")
    print("  \(boldColor)version\(resetColor)      Show version information")
    print("  \(boldColor)help\(resetColor)         Show this help message")
    print("\nOptions:")
    print("  \(boldColor)--config\(resetColor), \(boldColor)-c\(resetColor) <path>         Specify custom config file path")
    print("  \(boldColor)--dry-run\(resetColor), \(boldColor)-n\(resetColor)               Preview changes without making them")
    print("  \(boldColor)--snapshot\(resetColor) <timestamp>   Restore specific snapshot (for restore)")
    print("  \(boldColor)--path\(resetColor) <path>           Restore specific file/folder (for restore)")
    print("  \(boldColor)--output\(resetColor) <path>         Custom restore location (for restore)")
    print("  \(boldColor)--force\(resetColor)                  Skip overwrite confirmation (for restore)")
    print("  \(boldColor)--list-snapshots\(resetColor)        List available snapshots (for restore)")
    print("\nExamples:")
    print("  kodema test-config                         Validate config and test B2 connection")
    print("  kodema backup                              Incremental backup with default config")
    print("  kodema backup --dry-run                    Preview what would be backed up")
    print("  kodema mirror --config ~/my-config.yml     Simple mirror with custom config")
    print("  kodema cleanup -c ~/my-config.yml          Clean up with custom config")
    print("  kodema cleanup --dry-run                   Preview what would be deleted")
    print("  kodema restore                             Interactive snapshot selection and restore")
    print("  kodema restore --snapshot 2024-11-27_143022    Restore specific snapshot")
    print("  kodema restore --path Documents/file.txt   Restore specific file from latest")
    print("  kodema restore --dry-run --snapshot 2024-11-27_143022    Preview restore")
    print("  kodema restore --list-snapshots            List available snapshots")
    print("  kodema list                                Discover iCloud folders")
    print("\n\(boldColor)Backup vs Mirror:\(resetColor)")
    print("  • \(boldColor)backup\(resetColor) - Creates versioned snapshots, only uploads changed files")
    print("  • \(boldColor)mirror\(resetColor) - Uploads all files every time, no versioning")
    print("\n\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
}

// MARK: - iCloud Discovery

func findICloudDrive() -> URL? {
    // Try the standard iCloud Drive location
    let home = FileManager.default.homeDirectoryForCurrentUser
    let icloudDrive = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Mobile Documents")
        .appendingPathComponent("com~apple~CloudDocs")

    if FileManager.default.fileExists(atPath: icloudDrive.path) {
        return icloudDrive
    }
    return nil
}

func listICloudFolders() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let mobileDocsRoot = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Mobile Documents")

    guard FileManager.default.fileExists(atPath: mobileDocsRoot.path) else {
        print("\(errorColor)❌ iCloud not found\(resetColor)")
        print("Make sure iCloud Drive is enabled in System Settings.")
        return
    }

    print("\n\(boldColor)☁️  iCloud Folders with Files:\(resetColor)")
    print("   \(dimColor)\(mobileDocsRoot.path)\(resetColor)")
    print("")

    let fileManager = FileManager.default

    // Apple system containers to skip
    let appleContainers = Set([
        "com~apple~CloudDocs",
        "com~apple~iCloudDrive",
        "com~apple~mail",
        "com~apple~Notes",
        "com~apple~Keynote",
        "com~apple~Pages",
        "com~apple~Numbers",
        "com~apple~TextEdit",
        "com~apple~Preview",
        "com~apple~ScriptEditor2",
        "com~apple~automator",
        "com~apple~shoebox",
        "com~apple~shortcuts"
    ])

    do {
        // Get all container directories
        let containers = try fileManager.contentsOfDirectory(
            at: mobileDocsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ).filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let name = url.lastPathComponent
            // Skip Apple containers
            return isDir && !appleContainers.contains(name)
        }.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }

        if containers.isEmpty {
            print("\(dimColor)No third-party iCloud containers found\(resetColor)")
            print("\(dimColor)(Apple system folders are hidden)\(resetColor)")
            return
        }

        print("\(boldColor)📦 Your Apps:\(resetColor)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")

        var totalContainersShown = 0

        for container in containers {
            let containerName = container.lastPathComponent

            // List folders in this container
            do {
                let folders = try fileManager.contentsOfDirectory(
                    at: container,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ).filter { url in
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }

                // Count files in each folder to filter empty ones
                var foldersWithFiles: [(url: URL, fileCount: Int, totalSize: Int64)] = []

                for folder in folders {
                    var fileCount = 0
                    var totalSize: Int64 = 0

                    if let enumerator = fileManager.enumerator(
                        at: folder,
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        var counted = 0
                        for case let fileURL as URL in enumerator {
                            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                                fileCount += 1
                                if let size = fileSize(url: fileURL) {
                                    totalSize += size
                                }
                                counted += 1
                                if counted > 1000 { break } // Don't scan too deep
                            }
                        }
                    }

                    // Only include folders with files
                    if fileCount > 0 {
                        foldersWithFiles.append((url: folder, fileCount: fileCount, totalSize: totalSize))
                    }
                }

                // Skip this container if no folders with files
                if foldersWithFiles.isEmpty {
                    continue
                }

                totalContainersShown += 1

                // Decode app name from container ID (e.g., "iCloud~md~obsidian" -> "Obsidian")
                let displayName: String
                if containerName.hasPrefix("iCloud~") {
                    let appPart = containerName.replacingOccurrences(of: "iCloud~", with: "")
                        .replacingOccurrences(of: "~", with: ".")
                    displayName = "📱 \(appPart.capitalized)"
                } else {
                    displayName = containerName
                }

                print("  \(cloudColor)▶\(resetColor) \(boldColor)\(displayName)\(resetColor)")
                print("    \(dimColor)\(container.path)\(resetColor)")

                for (folder, fileCount, totalSize) in foldersWithFiles.prefix(10) {
                    let name = folder.lastPathComponent
                    print("    \(localColor)  •\(resetColor) \(name)")
                    print("      \(dimColor)Files: \(fileCount)\(fileCount >= 1000 ? "+" : "") | Size: \(formatBytes(totalSize))\(resetColor)")
                }

                if foldersWithFiles.count > 10 {
                    print("    \(dimColor)  ... and \(foldersWithFiles.count - 10) more folders\(resetColor)")
                }

                print("")

            } catch {
                // Skip containers we can't read
                continue
            }
        }

        if totalContainersShown == 0 {
            print("\(dimColor)No folders with files found\(resetColor)")
            print("\(dimColor)(Empty folders and Apple system apps are hidden)\(resetColor)\n")
            return
        }

        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("\n\(boldColor)💡 Tip:\(resetColor) Add folders to your config.yml:")
        print("\(dimColor)include:")
        print("  folders:")
        print("    # Example for Obsidian:")
        print("    - ~/Library/Mobile Documents/iCloud~md~obsidian/Documents")
        print("    # Or scan entire app container:")
        print("    - ~/Library/Mobile Documents/iCloud~md~obsidian")
        print("\n    # You can also add local folders:")
        print("    - ~/Documents")
        print("    - ~/Desktop\(resetColor)\n")

    } catch {
        print("\(errorColor)❌ Error reading iCloud:\(resetColor) \(error)")
    }
}

// MARK: - Retention & Cleanup Logic

struct SnapshotInfo {
    let timestamp: String
    let date: Date
    let manifestPath: String
}

enum RetentionBucket {
    case hourly
    case daily
    case weekly
    case monthly
    case tooOld
}

func classifySnapshot(date: Date, now: Date, retention: RetentionConfig) -> RetentionBucket {
    let interval = now.timeIntervalSince(date)
    let hours = interval / 3600
    let days = interval / 86400
    let weeks = interval / (86400 * 7)
    let months = interval / (86400 * 30.44) // Average month length

    if let hourlyLimit = retention.hourly, hours < Double(hourlyLimit) {
        return .hourly
    }
    if let dailyLimit = retention.daily, days < Double(dailyLimit) {
        return .daily
    }
    if let weeklyLimit = retention.weekly, weeks < Double(weeklyLimit) {
        return .weekly
    }
    if let monthlyLimit = retention.monthly, months < Double(monthlyLimit) {
        return .monthly
    }

    return .tooOld
}

func selectSnapshotsToKeep(snapshots: [SnapshotInfo], retention: RetentionConfig) -> Set<String> {
    var toKeep = Set<String>()
    let now = Date()

    // Group snapshots by bucket
    var hourlySnapshots: [SnapshotInfo] = []
    var dailySnapshots: [SnapshotInfo] = []
    var weeklySnapshots: [SnapshotInfo] = []
    var monthlySnapshots: [SnapshotInfo] = []

    for snapshot in snapshots {
        let bucket = classifySnapshot(date: snapshot.date, now: now, retention: retention)
        switch bucket {
        case .hourly:
            hourlySnapshots.append(snapshot)
        case .daily:
            dailySnapshots.append(snapshot)
        case .weekly:
            weeklySnapshots.append(snapshot)
        case .monthly:
            monthlySnapshots.append(snapshot)
        case .tooOld:
            break // Will be deleted
        }
    }

    // Hourly: keep all
    for snapshot in hourlySnapshots {
        toKeep.insert(snapshot.timestamp)
    }

    // Daily: keep one per day (the latest one each day)
    let dailyGroups = Dictionary(grouping: dailySnapshots) { snapshot -> String in
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: snapshot.date)
    }
    for (_, group) in dailyGroups {
        if let latest = group.max(by: { $0.date < $1.date }) {
            toKeep.insert(latest.timestamp)
        }
    }

    // Weekly: keep one per week (the latest one each week)
    let calendar = Calendar.current
    let weeklyGroups = Dictionary(grouping: weeklySnapshots) { snapshot -> String in
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: snapshot.date)
        return "\(components.yearForWeekOfYear ?? 0)-W\(components.weekOfYear ?? 0)"
    }
    for (_, group) in weeklyGroups {
        if let latest = group.max(by: { $0.date < $1.date }) {
            toKeep.insert(latest.timestamp)
        }
    }

    // Monthly: keep one per month (the latest one each month)
    let monthlyGroups = Dictionary(grouping: monthlySnapshots) { snapshot -> String in
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: snapshot.date)
    }
    for (_, group) in monthlyGroups {
        if let latest = group.max(by: { $0.date < $1.date }) {
            toKeep.insert(latest.timestamp)
        }
    }

    return toKeep
}

// MARK: - Cleanup command

func runCleanup(config: AppConfig, dryRun: Bool = false) async throws {
    guard let retention = config.backup?.retention else {
        print("\(errorColor)❌ No retention policy configured\(resetColor)")
        print("Add a retention policy to your config.yml under backup.retention")
        return
    }

    if dryRun {
        print("\n\(boldColor)Starting cleanup (DRY RUN - no changes will be made)\(resetColor)")
    } else {
        print("\n\(boldColor)Starting cleanup\(resetColor)")
    }
    print("  🧹 Retention policy:")
    if let h = retention.hourly { print("     Hourly: \(h) hours") }
    if let d = retention.daily { print("     Daily: \(d) days") }
    if let w = retention.weekly { print("     Weekly: \(w) weeks") }
    if let m = retention.monthly { print("     Monthly: \(m) months") }
    print("")

    // Prepare B2 client
    let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
    let maxRetries = config.b2.maxRetries ?? 3
    let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)

    let remotePrefix = config.backup?.remotePrefix ?? "backup"

    // Fetch all snapshots
    print("  ☁️  Fetching snapshots from B2...")
    let snapshotFiles = try await client.listFiles(prefix: "\(remotePrefix)/snapshots/")

    // Parse snapshot list
    var snapshots: [SnapshotInfo] = []
    for file in snapshotFiles {
        // Expected format: backup/snapshots/2024-11-27_143022/manifest.json
        let components = file.fileName.split(separator: "/")
        guard components.count >= 3,
              let timestampStr = components[components.count - 2] as? Substring,
              let date = parseTimestamp(String(timestampStr)) else {
            continue
        }
        snapshots.append(SnapshotInfo(
            timestamp: String(timestampStr),
            date: date,
            manifestPath: file.fileName
        ))
    }

    print("  ✓ Found \(snapshots.count) snapshots")

    if snapshots.isEmpty {
        print("  ℹ️  No snapshots to clean up")
        return
    }

    // Select snapshots to keep
    let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)
    let toDelete = snapshots.filter { !toKeep.contains($0.timestamp) }

    print("  📊 Analysis:")
    print("     Keep: \(toKeep.count) snapshots")
    print("     Delete: \(toDelete.count) snapshots")

    if toDelete.isEmpty {
        print("  ✅ Nothing to clean up")
        return
    }

    print("\n  \(boldColor)Snapshots to delete:\(resetColor)")
    for snapshot in toDelete.prefix(10).sorted(by: { $0.date < $1.date }) {
        print("     \(dimColor)• \(snapshot.timestamp)\(resetColor)")
    }
    if toDelete.count > 10 {
        print("     \(dimColor)... and \(toDelete.count - 10) more\(resetColor)")
    }

    if dryRun {
        print("\n  \(dimColor)ℹ️  Dry run - skipping actual deletion\(resetColor)")
    } else {
        // Confirm deletion
        print("\n  \(errorColor)⚠️  This will permanently delete \(toDelete.count) snapshots!\(resetColor)")
        print("  Type 'yes' to continue: ", terminator: "")
        fflush(stdout)

        guard let response = readLine(), response.lowercased() == "yes" else {
            print("  ℹ️  Cleanup cancelled")
            return
        }
    }

    print("\n  🗑️  \(dryRun ? "Would delete" : "Deleting") snapshots...")

    // Delete snapshot manifests
    var deletedSnapshots = 0
    for snapshot in toDelete {
        if dryRun {
            // In dry run, just count and report
            deletedSnapshots += 1
            print("     \(dimColor)✓ Would delete \(snapshot.timestamp)\(resetColor)")
        } else {
            do {
                // Find manifest file
                let manifestFiles = snapshotFiles.filter { $0.fileName.contains(snapshot.timestamp) }
                for file in manifestFiles {
                    try await client.deleteFileVersion(fileName: file.fileName, fileId: file.fileId)
                }
                deletedSnapshots += 1
                print("     \(dimColor)✓ Deleted \(snapshot.timestamp)\(resetColor)")
            } catch {
                print("     \(errorColor)✗ Failed to delete \(snapshot.timestamp): \(error)\(resetColor)")
            }
        }
    }

    print("\n  🧹 Cleaning up orphaned file versions...")

    // Fetch success markers to identify completed backups
    print("  📋 Checking backup completion status...")
    let allSuccessMarkers = try await client.listFiles(prefix: "\(remotePrefix)/.success-markers/")

    // Delete success markers for deleted snapshots
    var deletedMarkers = 0
    for marker in allSuccessMarkers {
        let timestamp = marker.fileName.split(separator: "/").last.map(String.init) ?? ""
        if toDelete.contains(where: { $0.timestamp == timestamp }) {
            if dryRun {
                deletedMarkers += 1
            } else {
                do {
                    try await client.deleteFileVersion(fileName: marker.fileName, fileId: marker.fileId)
                    deletedMarkers += 1
                } catch {
                    print("     \(errorColor)✗ Failed to delete marker for \(timestamp): \(error)\(resetColor)")
                }
            }
        }
    }
    if deletedMarkers > 0 {
        print("     ✓ \(dryRun ? "Would delete" : "Deleted") \(deletedMarkers) success markers")
    }

    // Build set of completed backups (excluding deleted ones)
    let completedBackups = Set(allSuccessMarkers.compactMap { marker -> String? in
        let timestamp = marker.fileName.split(separator: "/").last.map(String.init) ?? ""
        // Exclude if this snapshot is being deleted
        return toDelete.contains(where: { $0.timestamp == timestamp }) ? nil : timestamp
    }.filter { !$0.isEmpty })

    // Fetch all file versions
    let allFileVersions = try await client.listFiles(prefix: "\(remotePrefix)/files/")

    // Build set of referenced files: (timestamp, relativePath)
    // For completed backups: all files with that timestamp are valid
    // For incomplete backups: only files in manifest are valid
    var referencedFiles = Set<String>()  // Set of "timestamp:relativePath"

    for snapshot in snapshots where toKeep.contains(snapshot.timestamp) {
        if completedBackups.contains(snapshot.timestamp) {
            // ✅ Completed backup - mark all files with this timestamp as referenced
            // We'll verify against this timestamp in the loop below
            referencedFiles.insert(snapshot.timestamp)  // Special marker for "all files valid"
        } else {
            // ⚠️ Incomplete backup - only files in manifest are valid
            print("     ⚠️  Incomplete backup detected: \(snapshot.timestamp) - checking manifest...")
            do {
                let manifestData = try await client.downloadFile(fileName: snapshot.manifestPath)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let manifest = try decoder.decode(SnapshotManifest.self, from: manifestData)

                // Add only files from this specific snapshot version
                for fileInfo in manifest.files where fileInfo.versionTimestamp == snapshot.timestamp {
                    referencedFiles.insert("\(snapshot.timestamp):\(fileInfo.path)")
                }
            } catch {
                print("     \(errorColor)✗ Failed to fetch manifest for \(snapshot.timestamp): \(error)\(resetColor)")
                // Conservative: treat as completed to avoid deleting files
                referencedFiles.insert(snapshot.timestamp)
            }
        }
    }

    // Find orphaned versions
    var orphanedVersions: [(file: B2FileInfo, versionTimestamp: String)] = []
    for file in allFileVersions {
        // Expected format: backup/files/Documents/myfile.txt/2024-11-27_143022
        let components = file.fileName.split(separator: "/")
        guard components.count >= 4 else { continue }

        let versionTimestamp = components.last.map(String.init) ?? ""
        // Extract relative path: everything between "files/" and timestamp
        let pathComponents = components.dropFirst(2).dropLast(1)
        let relativePath = pathComponents.joined(separator: "/")

        // Check if file is referenced
        let isCompleted = referencedFiles.contains(versionTimestamp)
        let isInManifest = referencedFiles.contains("\(versionTimestamp):\(relativePath)")

        if !isCompleted && !isInManifest {
            orphanedVersions.append((file, versionTimestamp))
        }
    }

    print("     Found \(orphanedVersions.count) orphaned file versions")

    if orphanedVersions.isEmpty {
        print("     ✓ No orphaned versions to delete")
    } else {
        var deletedVersions = 0
        for (file, _) in orphanedVersions {
            if dryRun {
                deletedVersions += 1
                if deletedVersions % 100 == 0 {
                    print("     \(dimColor)Would delete \(deletedVersions)/\(orphanedVersions.count) versions...\(resetColor)")
                }
            } else {
                do {
                    try await client.deleteFileVersion(fileName: file.fileName, fileId: file.fileId)
                    deletedVersions += 1
                    if deletedVersions % 100 == 0 {
                        print("     \(dimColor)Deleted \(deletedVersions)/\(orphanedVersions.count) versions...\(resetColor)")
                    }
                } catch {
                    print("     \(errorColor)✗ Failed to delete \(file.fileName): \(error)\(resetColor)")
                }
            }
        }
        print("     ✓ \(dryRun ? "Would delete" : "Deleted") \(deletedVersions) orphaned versions")
    }

    print("\n\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
    if dryRun {
        print("\(boldColor)Dry Run Complete!\(resetColor)")
    } else {
        print("\(boldColor)Cleanup Complete!\(resetColor)")
    }
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
    print("  🗑️  \(dryRun ? "Would delete" : "Deleted") \(deletedSnapshots) snapshots")
    print("  🧹 \(dryRun ? "Would clean up" : "Cleaned up") orphaned file versions")
    print("  ✅ Retained \(toKeep.count) snapshots")
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
}

// MARK: - Config validation and testing

func testConfig(config: AppConfig, configURL: URL) async throws {
    print("\n\(boldColor)Testing Kodema Configuration\(resetColor)")
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")

    var hasErrors = false
    var hasWarnings = false

    // 1. Config file validation
    print("\(boldColor)Configuration File:\(resetColor)")
    print("  \(localColor)✓\(resetColor) Config loaded: \(configURL.path)")

    // 2. B2 Connection Test
    print("\n\(boldColor)B2 Connection:\(resetColor)")
    do {
        let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
        let maxRetries = config.b2.maxRetries ?? 3
        let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)

        // Test authentication
        do {
            try await client.ensureAuthorized()
            let maskedKey = String(config.b2.keyID.suffix(4))
            print("  \(localColor)✓\(resetColor) Authentication successful (key: ***\(maskedKey))")
        } catch {
            print("  \(errorColor)✗ Authentication failed: \(error)\(resetColor)")
            hasErrors = true
        }

        // Test bucket access
        do {
            let bucketId = try await client.ensureBucketId()
            print("  \(localColor)✓\(resetColor) Bucket found: \(config.b2.bucketName) (id: \(bucketId))")

            // Test API access with a simple list operation
            _ = try await client.listFiles(prefix: "", maxFileCount: 1)
            print("  \(localColor)✓\(resetColor) API access verified")
        } catch {
            print("  \(errorColor)✗ Bucket access failed: \(error)\(resetColor)")
            hasErrors = true
        }
    }

    // 3. Folders validation
    print("\n\(boldColor)Folders to Backup:\(resetColor)")

    guard let folders = config.include?.folders, !folders.isEmpty else {
        print("  \(errorColor)✗ No folders configured\(resetColor)")
        print("    Add folders to config under 'include.folders'")
        hasErrors = true

        print("\n\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("\(errorColor)Configuration has errors - please fix them before running backup\(resetColor)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
        throw ConfigError.noFoldersConfigured
    }

    let fm = FileManager.default
    var totalFiles = 0
    var totalBytes: Int64 = 0
    var icloudNotDownloaded = 0

    for folder in folders {
        let expandedPath = NSString(string: folder).expandingTildeInPath
        let folderURL = URL(fileURLWithPath: expandedPath)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: folderURL.path, isDirectory: &isDir) && isDir.boolValue {
            // Quick scan to get file count and size
            var folderFiles = 0
            var folderBytes: Int64 = 0
            var folderICloudNotDownloaded = 0

            // Use a synchronous approach for file enumeration
            let scanResult: (Int, Int64, Int) = {
                var files = 0
                var bytes: Int64 = 0
                var notDownloaded = 0

                guard let enumerator = fm.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return (0, 0, 0)
                }

                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
                       let isFile = resourceValues.isRegularFile,
                       isFile {
                        files += 1
                        if let size = resourceValues.fileSize {
                            bytes += Int64(size)
                        }

                        // Check iCloud status
                        if let isUbiquitous = resourceValues.isUbiquitousItem, isUbiquitous {
                            if let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus {
                                if downloadStatus != URLUbiquitousItemDownloadingStatus.current {
                                    notDownloaded += 1
                                }
                            }
                        }
                    }
                }

                return (files, bytes, notDownloaded)
            }()

            folderFiles = scanResult.0
            folderBytes = scanResult.1
            folderICloudNotDownloaded = scanResult.2

            totalFiles += folderFiles
            totalBytes += folderBytes
            icloudNotDownloaded += folderICloudNotDownloaded

            print("  \(localColor)✓\(resetColor) \(folder) (\(folderFiles) files, \(formatBytes(folderBytes)))")
        } else {
            print("  \(errorColor)✗ \(folder) - folder does not exist\(resetColor)")
            print("    Remove this folder from config or create it")
            hasErrors = true
        }
    }

    if icloudNotDownloaded > 0 {
        print("  \(errorColor)⚠\(resetColor)  iCloud: \(icloudNotDownloaded) files not yet downloaded locally")
        print("    These will be downloaded automatically during backup")
        hasWarnings = true
    }

    // 4. Filters validation
    if let filters = config.filters {
        print("\n\(boldColor)Filters:\(resetColor)")

        if let excludeHidden = filters.excludeHidden, excludeHidden {
            print("  \(localColor)✓\(resetColor) Exclude hidden files: enabled")
        }

        if let minSize = filters.minSizeBytes, minSize > 0 {
            print("  \(localColor)✓\(resetColor) Minimum file size: \(formatBytes(Int64(minSize)))")
        }

        if let maxSize = filters.maxSizeBytes, maxSize > 0 {
            print("  \(localColor)✓\(resetColor) Maximum file size: \(formatBytes(Int64(maxSize)))")
        }

        if let globs = filters.excludeGlobs, !globs.isEmpty {
            print("  \(localColor)✓\(resetColor) Exclude patterns: \(globs.count) patterns")
            print("    Examples: \(globs.prefix(3).joined(separator: ", "))")
        }
    }

    // 5. Retention policy
    if let retention = config.backup?.retention {
        print("\n\(boldColor)Retention Policy:\(resetColor)")
        print("  \(localColor)✓\(resetColor) Hourly: \(retention.hourly ?? 24) snapshots")
        print("  \(localColor)✓\(resetColor) Daily: \(retention.daily ?? 30) snapshots")
        print("  \(localColor)✓\(resetColor) Weekly: \(retention.weekly ?? 12) snapshots")
        print("  \(localColor)✓\(resetColor) Monthly: \(retention.monthly ?? 12) snapshots")
    }

    // 6. Performance settings
    print("\n\(boldColor)Performance Settings:\(resetColor)")
    let partSizeMB = config.b2.partSizeMB ?? 100
    print("  \(localColor)✓\(resetColor) Part size: \(partSizeMB) MB")

    let uploadConcurrency = config.b2.uploadConcurrency ?? 1
    print("  \(localColor)✓\(resetColor) Upload concurrency: \(uploadConcurrency)")

    let manifestInterval = config.backup?.manifestUpdateInterval ?? 50
    print("  \(localColor)✓\(resetColor) Manifest update interval: \(manifestInterval) files")

    // 7. Timeouts
    if let timeouts = config.timeouts {
        print("\n\(boldColor)Timeouts:\(resetColor)")
        if let icloudTimeout = timeouts.icloudDownloadSeconds {
            print("  \(localColor)✓\(resetColor) iCloud download: \(icloudTimeout)s")
        }
        if let networkTimeout = timeouts.networkSeconds {
            print("  \(localColor)✓\(resetColor) Network requests: \(networkTimeout)s")
        }
        if let uploadTimeout = timeouts.overallUploadSeconds {
            print("  \(localColor)✓\(resetColor) Overall upload: \(uploadTimeout)s")
        }
    }

    // 8. Disk Space
    print("\n\(boldColor)Disk Space:\(resetColor)")
    if let availableSpace = getAvailableDiskSpace() {
        print("  \(localColor)✓\(resetColor) Available: \(formatBytes(availableSpace))")

        // Check if enough space for iCloud files
        if icloudNotDownloaded > 0 {
            // Calculate space needed for largest iCloud files (estimate)
            let estimatedNeededSpace = Int64(Double(totalBytes) * 0.3) // Assume 30% are iCloud files not yet downloaded
            let requiredSpace = Int64(Double(estimatedNeededSpace) * 1.2) // Add 20% buffer

            if availableSpace < requiredSpace {
                print("  \(errorColor)⚠\(resetColor)  Warning: May not have enough space for iCloud downloads")
                print("    Estimated need: \(formatBytes(requiredSpace)) (with buffer)")
                print("    Consider freeing up disk space before backup")
                hasWarnings = true
            }
        }
    } else {
        print("  \(errorColor)⚠\(resetColor)  Could not determine available disk space")
        hasWarnings = true
    }

    // Final summary
    print("\n\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
    if hasErrors {
        print("\(errorColor)Configuration has errors - please fix them before running backup\(resetColor)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
        throw ConfigError.validationFailed
    } else if hasWarnings {
        print("\(errorColor)⚠\(resetColor)  \(boldColor)Configuration is valid with warnings\(resetColor)")
    } else {
        print("\(localColor)✓ Configuration is valid and ready for backup!\(resetColor)")
    }
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")

    print("\n\(boldColor)Summary:\(resetColor)")
    print("  • Total files to scan: ~\(totalFiles) files")
    print("  • Estimated size: ~\(formatBytes(totalBytes))")
    if icloudNotDownloaded > 0 {
        print("  • iCloud files may need download during backup")
    }
    print("")
}

// MARK: - Main backup logic (incremental with snapshots)

func runIncrementalBackup(config: AppConfig, dryRun: Bool = false) async throws {
    let progress = ProgressTracker()

    let excludeHidden = config.filters?.excludeHidden ?? true
    let folders = try buildFoldersToScan(from: config)

    // Scan local files
    var allFiles: [FileItem] = []
    for folder in folders {
        allFiles.append(contentsOf: scanFolder(url: folder, excludeHidden: excludeHidden))
    }
    allFiles = applyFilters(allFiles, filters: config.filters)

    // Prepare B2 client
    let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
    let overallUploadTimeout = TimeInterval(config.timeouts?.overallUploadSeconds ?? 7200)
    let icloudTimeout = config.timeouts?.icloudDownloadSeconds ?? 1800
    let maxRetries = config.b2.maxRetries ?? 3
    let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)

    // Generate snapshot timestamp
    let timestamp = generateTimestamp()
    let remotePrefix = config.backup?.remotePrefix ?? "backup"

    if dryRun {
        print("\n\(boldColor)Starting incremental backup (DRY RUN - no changes will be made)\(resetColor)")
    } else {
        print("\n\(boldColor)Starting incremental backup\(resetColor)")
    }
    print("  📸 Snapshot: \(timestamp)")
    print("  📂 Scanned files: \(allFiles.count)")

    // Fetch latest snapshot manifest from B2
    print("  ☁️ Fetching latest snapshot from B2...")
    let latestManifest = try await fetchLatestManifest(client: client, remotePrefix: remotePrefix)
    if let manifest = latestManifest {
        print("  ✓ Found previous snapshot: \(manifest.timestamp) with \(manifest.totalFiles) files")
    } else {
        print("  ℹ️ No previous snapshots found - this is the first backup")
    }

    // Determine which files need backup
    var filesToBackup: [(file: FileItem, relativePath: String)] = []
    for file in allFiles {
        let relativePath = buildRelativePath(for: file.url, from: folders)
        if fileNeedsBackup(file: file, latestManifest: latestManifest, relativePath: relativePath) {
            filesToBackup.append((file, relativePath))
        }
    }

    print("  📤 Files to upload: \(filesToBackup.count) (skipping \(allFiles.count - filesToBackup.count) unchanged)")

    let totalBytes = filesToBackup.reduce(Int64(0)) { $0 + ($1.file.size ?? 0) }
    print("  💾 Total size: \(formatBytes(totalBytes))")

    if dryRun {
        print("\n  \(dimColor)ℹ️  Dry run - no files will be uploaded\(resetColor)")
        print("\n\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("\(boldColor)Dry Run Complete!\(resetColor)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("  📤 Would upload: \(filesToBackup.count) files")
        print("  💾 Total size: \(formatBytes(totalBytes))")
        print("  📸 Snapshot: \(timestamp)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
        return
    }

    // Sort: Local first
    filesToBackup.sort {
        if $0.file.status == $1.file.status {
            return $0.file.url.lastPathComponent.lowercased() < $1.file.url.lastPathComponent.lowercased()
        }
        return $0.file.status == "Local"
    }

    // Decide part size
    let recommendedPartSize = (try? await client.recommendedPartSizeBytes()) ?? (100 * 1024 * 1024)
    let configuredPartSizeMB = config.b2.partSizeMB
    let partSizeBytes = max((configuredPartSizeMB ?? (recommendedPartSize / (1024*1024))), (try? await client.absoluteMinimumPartSizeBytes()) ?? (5 * 1024 * 1024)) * 1024 * 1024
    let uploadConcurrency = max(1, config.b2.uploadConcurrency ?? 1)

    // Initialize progress
    await progress.initialize(totalFiles: filesToBackup.count, totalBytes: totalBytes)
    print("")

    // Upload files & build manifest
    var manifestFiles: [FileVersionInfo] = []

    // Start with files from previous snapshot
    if let prevManifest = latestManifest {
        manifestFiles = prevManifest.files
    }

    // Get manifest update interval from config (default: 50 files)
    let manifestUpdateInterval = config.backup?.manifestUpdateInterval ?? 50
    var filesUploadedSinceLastManifest = 0

    // Upload initial manifest (empty or with previous files) to establish snapshot
    do {
        try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix)
        print("  📸 Initial manifest created")
    } catch {
        print("  \(errorColor)⚠️  Failed to create initial manifest: \(error)\(resetColor)")
        throw error  // Critical: cannot proceed without manifest
    }

    for (file, relativePath) in filesToBackup {
        // Check for graceful shutdown request
        if isShutdownRequested() {
            print("\n\(errorColor)⚠️  Shutdown in progress - saving partial manifest...\(resetColor)")
            break  // Exit loop, will save manifest below
        }

        await progress.printProgress()

        do {
            let url = file.url
            let status = file.status

            // Handle iCloud downloads
            if status == "Cloud" {
                await progress.startFile(name: "☁️  \(url.lastPathComponent)")
                await progress.printProgress()

                // Check if enough disk space before downloading
                let fileSize = file.size ?? 0
                if let availableSpace = getAvailableDiskSpace(), fileSize > 0 {
                    // Require 20% buffer for safety
                    let requiredSpace = Int64(Double(fileSize) * 1.2)
                    if availableSpace < requiredSpace {
                        print("  \(errorColor)⚠️  Not enough disk space to download \(url.lastPathComponent)\(resetColor)")
                        print("  \(errorColor)   Need: \(formatBytes(requiredSpace)) (file + 20% buffer), Available: \(formatBytes(availableSpace))\(resetColor)")
                        await progress.fileFailed()
                        continue
                    }
                }

                startDownloadIfNeeded(url: url)
                let ok = try await withTimeoutBool(TimeInterval(icloudTimeout)) {
                    await waitForICloudDownload(url: url, timeoutSeconds: icloudTimeout)
                }
                if !ok {
                    await progress.fileFailed()
                    continue
                }
            } else if status == "Error" {
                await progress.fileFailed()
                continue
            }

            // Upload to versioned path
            let versionPath = "\(remotePrefix)/files/\(relativePath)/\(timestamp)"
            let contentType = guessContentType(for: url)
            let size = file.size ?? (fileSize(url: url) ?? 0)
            let mtime = file.modificationDate ?? Date()

            await progress.startFile(name: "\(url.lastPathComponent) (\(formatBytes(size)))")
            await progress.printProgress()

            let smallFileThreshold: Int64 = 5 * 1024 * 1024 * 1024 // 5 GB

            if size <= smallFileThreshold {
                let sha1 = try sha1HexStream(fileURL: url)
                try await withTimeoutVoid(overallUploadTimeout) {
                    try await client.uploadSmallFile(fileURL: url, fileName: versionPath, contentType: contentType, sha1Hex: sha1)
                }
            } else {
                try await withTimeoutVoid(overallUploadTimeout) {
                    try await client.uploadLargeFile(fileURL: url, fileName: versionPath, contentType: contentType, partSize: partSizeBytes, concurrency: uploadConcurrency)
                }
            }

            await progress.fileCompleted(bytes: size)

            // Update manifest: replace old version or add new
            if let existingIndex = manifestFiles.firstIndex(where: { $0.path == relativePath }) {
                manifestFiles[existingIndex] = FileVersionInfo(
                    path: relativePath,
                    size: size,
                    modificationDate: mtime,
                    versionTimestamp: timestamp
                )
            } else {
                manifestFiles.append(FileVersionInfo(
                    path: relativePath,
                    size: size,
                    modificationDate: mtime,
                    versionTimestamp: timestamp
                ))
            }

            if status == "Cloud" {
                evictIfUbiquitous(url: url)
            }

            // Incremental manifest update
            filesUploadedSinceLastManifest += 1
            if filesUploadedSinceLastManifest >= manifestUpdateInterval {
                do {
                    try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix)
                    filesUploadedSinceLastManifest = 0
                } catch {
                    // Non-fatal: log but continue backup
                    print("  \(errorColor)⚠️  Failed to update manifest: \(error)\(resetColor)")
                }
            }
        } catch TimeoutError.timedOut {
            await progress.fileFailed()
        } catch {
            await progress.fileFailed()
        }
    }

    // Remove deleted files from manifest (files that were in previous snapshot but no longer exist)
    let currentPaths = Set(allFiles.map { buildRelativePath(for: $0.url, from: folders) })
    manifestFiles = manifestFiles.filter { currentPaths.contains($0.path) }

    // Check if shutdown was requested
    if isShutdownRequested() {
        // Graceful shutdown - save partial manifest without success marker
        print("  💾 Uploading partial manifest...")
        try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix)

        await progress.printFinal()
        print("  📸 Partial manifest uploaded: \(remotePrefix)/snapshots/\(timestamp)/manifest.json")
        print("  ⚠️  Backup interrupted - progress saved")
        print("  ℹ️  Run 'kodema backup' again to continue from where you left off")

        // Show cursor and exit with interrupted status
        print("\u{001B}[?25h")
        fflush(stdout)
        exit(130)  // Standard exit code for SIGINT
    }

    // Normal completion - upload final manifest and success marker
    try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix)
    try await uploadSuccessMarker(client: client, timestamp: timestamp, remotePrefix: remotePrefix)

    await progress.printFinal()
    print("  📸 Snapshot manifest uploaded: \(remotePrefix)/snapshots/\(timestamp)/manifest.json")
    print("  ✅ Backup completed successfully")
}

// MARK: - Mirror logic (simple upload all)

func runMirror(config: AppConfig) async throws {
    let progress = ProgressTracker()

    let excludeHidden = config.filters?.excludeHidden ?? true
    let folders = try buildFoldersToScan(from: config)

    // Scan
    var allFiles: [FileItem] = []
    for folder in folders {
        allFiles.append(contentsOf: scanFolder(url: folder, excludeHidden: excludeHidden))
    }
    allFiles = applyFilters(allFiles, filters: config.filters)

    // Sort: Local first
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

    let remotePrefix = config.mirror?.remotePrefix ?? config.b2.remotePrefix ?? "mirror"

    // Initialize progress tracker
    let totalBytes = sortedFiles.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
    await progress.initialize(totalFiles: sortedFiles.count, totalBytes: totalBytes)

    print("\n\(boldColor)Starting mirror\(resetColor)")
    print("  📂 Files: \(sortedFiles.count)")
    print("  📦 Total size: \(formatBytes(totalBytes))")
    print("")

    // Upload loop
    for file in sortedFiles {
        await progress.printProgress()

        do {
            let url = file.url
            let status = file.status

            if status == "Cloud" {
                await progress.startFile(name: "☁️  \(url.lastPathComponent)")
                await progress.printProgress()

                startDownloadIfNeeded(url: url)
                let ok = try await withTimeoutBool(TimeInterval(icloudTimeout)) {
                    await waitForICloudDownload(url: url, timeoutSeconds: icloudTimeout)
                }
                if !ok {
                    await progress.fileFailed()
                    continue
                }
            } else if status == "Error" {
                await progress.fileFailed()
                continue
            }

            let remoteName = remoteFileName(for: url, remotePrefix: remotePrefix)
            let contentType = guessContentType(for: url)

            let size = file.size ?? (fileSize(url: url) ?? 0)
            let smallFileThreshold: Int64 = 5 * 1024 * 1024 * 1024 // 5 GB

            await progress.startFile(name: "\(url.lastPathComponent) (\(formatBytes(size)))")
            await progress.printProgress()

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

            await progress.fileCompleted(bytes: size)

            if status == "Cloud" {
                evictIfUbiquitous(url: url)
            }
        } catch TimeoutError.timedOut {
            await progress.fileFailed()
        } catch {
            await progress.fileFailed()
        }
    }

    await progress.printFinal()
}

// MARK: - Restore command

func parseRestoreOptions(from arguments: [String]) throws -> RestoreOptions {
    var options = RestoreOptions(
        snapshotTimestamp: nil,
        paths: [],
        outputDirectory: nil,
        force: false,
        listSnapshots: false
    )

    var i = 0
    while i < arguments.count {
        let arg = arguments[i]

        switch arg {
        case "--snapshot":
            guard i + 1 < arguments.count else {
                throw RestoreError.invalidSelection
            }
            options.snapshotTimestamp = arguments[i + 1]
            i += 2

        case "--path":
            guard i + 1 < arguments.count else {
                throw RestoreError.invalidSelection
            }
            options.paths.append(arguments[i + 1])
            i += 2

        case "--output":
            guard i + 1 < arguments.count else {
                throw RestoreError.invalidSelection
            }
            options.outputDirectory = URL(fileURLWithPath: arguments[i + 1]).expandedTilde()
            i += 2

        case "--force":
            options.force = true
            i += 1

        case "--list-snapshots":
            options.listSnapshots = true
            i += 1

        default:
            i += 1
        }
    }

    return options
}

func fetchAllSnapshots(client: B2Client, remotePrefix: String) async throws -> [SnapshotInfo] {
    let snapshotFiles = try await client.listFiles(prefix: "\(remotePrefix)/snapshots/")

    var snapshots: [SnapshotInfo] = []
    for file in snapshotFiles {
        guard file.fileName.hasSuffix("/manifest.json") else { continue }

        let components = file.fileName.split(separator: "/")
        guard components.count >= 3,
              let timestampStr = components[components.count - 2] as Substring?,
              let date = parseTimestamp(String(timestampStr)) else {
            continue
        }

        snapshots.append(SnapshotInfo(
            timestamp: String(timestampStr),
            date: date,
            manifestPath: file.fileName
        ))
    }

    return snapshots.sorted { $0.date > $1.date }
}

func formatRelativeTime(_ date: Date) -> String {
    let now = Date()
    let interval = now.timeIntervalSince(date)
    let hours = Int(interval / 3600)
    let days = Int(interval / 86400)

    if hours < 1 {
        return "just now"
    } else if hours < 24 {
        return "\(hours) hour\(hours == 1 ? "" : "s") ago"
    } else if days < 7 {
        return "\(days) day\(days == 1 ? "" : "s") ago"
    } else if days < 30 {
        let weeks = days / 7
        return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
    } else {
        let months = days / 30
        return "\(months) month\(months == 1 ? "" : "s") ago"
    }
}

func selectSnapshotInteractively(snapshots: [SnapshotInfo], client: B2Client, remotePrefix: String) async throws -> SnapshotManifest {
    guard !snapshots.isEmpty else {
        throw RestoreError.noSnapshotsFound
    }

    print("\n\(boldColor)Available Snapshots:\(resetColor)")
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")

    let displayCount = min(snapshots.count, 10)
    for (index, snapshot) in snapshots.prefix(displayCount).enumerated() {
        let manifestData = try await client.downloadFile(fileName: snapshot.manifestPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(SnapshotManifest.self, from: manifestData)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        let dateStr = formatter.string(from: snapshot.date)

        print("  \(boldColor)\(index + 1).\(resetColor) \(snapshot.timestamp)  (\(dateStr))")
        print("     Files: \(manifest.totalFiles)  |  Size: \(formatBytes(manifest.totalBytes))  |  \(formatRelativeTime(snapshot.date))")
        print("")
    }

    if snapshots.count > displayCount {
        print("     \(dimColor)... and \(snapshots.count - displayCount) more snapshots\(resetColor)\n")
    }

    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
    print("Select snapshot number (1-\(displayCount)), or 'latest': ", terminator: "")
    fflush(stdout)

    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        throw RestoreError.invalidSelection
    }

    let selectedSnapshot: SnapshotInfo
    if input.lowercased() == "latest" {
        selectedSnapshot = snapshots[0]
    } else if let number = Int(input), number >= 1, number <= displayCount {
        selectedSnapshot = snapshots[number - 1]
    } else {
        throw RestoreError.invalidSelection
    }

    print("\n\(localColor)✓\(resetColor) Selected snapshot: \(selectedSnapshot.timestamp)\n")

    let manifestData = try await client.downloadFile(fileName: selectedSnapshot.manifestPath)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SnapshotManifest.self, from: manifestData)
}

func getTargetSnapshot(client: B2Client, remotePrefix: String, options: RestoreOptions) async throws -> SnapshotManifest {
    if let timestamp = options.snapshotTimestamp {
        let manifestPath = "\(remotePrefix)/snapshots/\(timestamp)/manifest.json"
        do {
            let data = try await client.downloadFile(fileName: manifestPath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SnapshotManifest.self, from: data)
        } catch {
            throw RestoreError.invalidSnapshot(timestamp)
        }
    } else {
        let snapshots = try await fetchAllSnapshots(client: client, remotePrefix: remotePrefix)
        return try await selectSnapshotInteractively(snapshots: snapshots, client: client, remotePrefix: remotePrefix)
    }
}

func listSnapshotsCommand(config: AppConfig, options: RestoreOptions) async throws {
    let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
    let maxRetries = config.b2.maxRetries ?? 3
    let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)
    let remotePrefix = config.backup?.remotePrefix ?? "backup"

    let allSnapshots = try await fetchAllSnapshots(client: client, remotePrefix: remotePrefix)

    guard !allSnapshots.isEmpty else {
        print("\n\(dimColor)No snapshots found\(resetColor)\n")
        return
    }

    var snapshots: [(SnapshotInfo, SnapshotManifest)] = []
    for snapshot in allSnapshots {
        let manifestData = try await client.downloadFile(fileName: snapshot.manifestPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(SnapshotManifest.self, from: manifestData)

        if !options.paths.isEmpty {
            let filteredFiles = filterFilesToRestore(manifest: manifest, pathFilters: options.paths)
            if filteredFiles.isEmpty {
                continue
            }
            snapshots.append((snapshot, manifest))
        } else {
            snapshots.append((snapshot, manifest))
        }
    }

    guard !snapshots.isEmpty else {
        if !options.paths.isEmpty {
            print("\n\(dimColor)No snapshots found containing files matching: \(options.paths.joined(separator: ", "))\(resetColor)\n")
        } else {
            print("\n\(dimColor)No snapshots found\(resetColor)\n")
        }
        return
    }

    if !options.paths.isEmpty {
        print("\n\(boldColor)Snapshots containing '\(options.paths.joined(separator: ", "))':\(resetColor)")
    } else {
        print("\n\(boldColor)Available Snapshots:\(resetColor)")
    }
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")

    for (snapshot, manifest) in snapshots {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        let dateStr = formatter.string(from: snapshot.date)

        let displayFiles = !options.paths.isEmpty ? filterFilesToRestore(manifest: manifest, pathFilters: options.paths).count : manifest.totalFiles
        let displayBytes = !options.paths.isEmpty ? filterFilesToRestore(manifest: manifest, pathFilters: options.paths).reduce(Int64(0)) { $0 + $1.size } : manifest.totalBytes

        print("  \(boldColor)\(snapshot.timestamp)\(resetColor)  (\(dateStr))")
        print("     Files: \(displayFiles)  |  Size: \(formatBytes(displayBytes))  |  \(formatRelativeTime(snapshot.date))")
        print("")
    }

    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
}

func filterFilesToRestore(manifest: SnapshotManifest, pathFilters: [String]) -> [FileVersionInfo] {
    if pathFilters.isEmpty {
        return manifest.files
    }

    return manifest.files.filter { file in
        for filter in pathFilters {
            let normalizedFilter = filter.hasSuffix("/") ? String(filter.dropLast()) : filter
            let filePath = file.path

            if filePath == normalizedFilter {
                return true
            }

            if filePath.hasPrefix(normalizedFilter + "/") {
                return true
            }

            let fileComponents = filePath.split(separator: "/").map(String.init)
            let filterComponents = normalizedFilter.split(separator: "/").map(String.init)

            if filterComponents.count <= fileComponents.count {
                var matches = true
                for (index, filterComponent) in filterComponents.enumerated() {
                    if fileComponents[index] != filterComponent {
                        matches = false
                        break
                    }
                }
                if matches {
                    return true
                }
            }

            if filePath.contains("/" + normalizedFilter + "/") {
                return true
            }
        }
        return false
    }
}

func checkForConflicts(files: [FileVersionInfo], outputDir: URL) -> [FileConflict] {
    files.compactMap { file in
        let localPath = outputDir.appendingPathComponent(file.path)
        guard FileManager.default.fileExists(atPath: localPath.path) else {
            return nil
        }
        return FileConflict(
            relativePath: file.path,
            existingURL: localPath,
            existingSize: fileSize(url: localPath),
            existingMtime: fileModificationDate(url: localPath),
            restoreSize: file.size,
            restoreMtime: file.modificationDate
        )
    }
}

func handleConflicts(_ conflicts: [FileConflict]) throws {
    guard !conflicts.isEmpty else { return }

    print("\n\(errorColor)⚠️  Warning:\(resetColor) \(conflicts.count) file\(conflicts.count == 1 ? "" : "s") will be overwritten:\n")

    for conflict in conflicts.prefix(10) {
        let existingSizeStr = conflict.existingSize.map { formatBytes($0) } ?? "unknown"
        let restoreSizeStr = formatBytes(conflict.restoreSize)

        print("  • \(conflict.relativePath)")
        print("    \(dimColor)\(existingSizeStr) → \(restoreSizeStr)\(resetColor)")
    }

    if conflicts.count > 10 {
        print("  \(dimColor)... and \(conflicts.count - 10) more\(resetColor)")
    }

    print("\n\(boldColor)Options:\(resetColor)")
    print("  o - Overwrite all")
    print("  s - Skip all (cancel restore)")
    print("\nSelect option: ", terminator: "")
    fflush(stdout)

    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
        throw RestoreError.cancelled
    }

    switch input {
    case "o", "overwrite":
        print("\(localColor)✓\(resetColor) Will overwrite existing files\n")
    case "s", "skip", "cancel":
        throw RestoreError.cancelled
    default:
        throw RestoreError.invalidSelection
    }
}

func downloadAndRestoreFiles(client: B2Client, files: [FileVersionInfo], remotePrefix: String, snapshot: SnapshotManifest, outputDir: URL, progress: ProgressTracker) async throws {
    let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
    await progress.initialize(totalFiles: files.count, totalBytes: totalBytes)

    for file in files {
        await progress.startFile(name: "\(file.path) (\(formatBytes(file.size)))")
        await progress.printProgress()

        do {
            let remotePath = "\(remotePrefix)/files/\(file.path)/\(file.versionTimestamp)"
            let localPath = outputDir.appendingPathComponent(file.path)

            try FileManager.default.createDirectory(
                at: localPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Use streaming download to avoid loading entire file into RAM
            try await client.downloadFileStreaming(fileName: remotePath, to: localPath)

            try FileManager.default.setAttributes(
                [.modificationDate: file.modificationDate],
                ofItemAtPath: localPath.path
            )

            await progress.fileCompleted(bytes: file.size)
        } catch {
            print("\n\(errorColor)✗ Failed to restore \(file.path): \(error)\(resetColor)")
            await progress.fileFailed()
        }
    }

    await progress.printFinal()
}

func runRestore(config: AppConfig, options: RestoreOptions, dryRun: Bool = false) async throws {
    let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
    let maxRetries = config.b2.maxRetries ?? 3
    let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)
    let remotePrefix = config.backup?.remotePrefix ?? "backup"

    if dryRun {
        print("\n\(boldColor)Starting restore (DRY RUN - no changes will be made)\(resetColor)")
    } else {
        print("\n\(boldColor)Starting restore\(resetColor)")
    }

    let snapshot = try await getTargetSnapshot(client: client, remotePrefix: remotePrefix, options: options)
    print("  📸 Snapshot: \(snapshot.timestamp)")
    print("  📂 Total files in snapshot: \(snapshot.totalFiles)")

    let filesToRestore = filterFilesToRestore(manifest: snapshot, pathFilters: options.paths)
    print("  📤 Files to restore: \(filesToRestore.count)")

    if filesToRestore.isEmpty {
        print("\n\(dimColor)No files to restore\(resetColor)\n")
        return
    }

    let outputDir = options.outputDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    print("  📁 Restore location: \(outputDir.path)")

    let totalBytes = filesToRestore.reduce(Int64(0)) { $0 + $1.size }
    print("  💾 Total size: \(formatBytes(totalBytes))")

    let conflicts = checkForConflicts(files: filesToRestore, outputDir: outputDir)
    if !conflicts.isEmpty {
        print("  ⚠️  Conflicts: \(conflicts.count) files already exist")
        if dryRun {
            print("\n  \(dimColor)Files that would be overwritten:\(resetColor)")
            for conflict in conflicts.prefix(10) {
                print("     \(dimColor)• \(conflict)\(resetColor)")
            }
            if conflicts.count > 10 {
                print("     \(dimColor)... and \(conflicts.count - 10) more\(resetColor)")
            }
        } else if !options.force {
            try handleConflicts(conflicts)
        }
    }

    if dryRun {
        print("\n  \(dimColor)ℹ️  Dry run - no files will be downloaded\(resetColor)")
        print("\n\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("\(boldColor)Dry Run Complete!\(resetColor)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("  📤 Would restore: \(filesToRestore.count) files")
        print("  💾 Total size: \(formatBytes(totalBytes))")
        print("  📸 From snapshot: \(snapshot.timestamp)")
        print("  📁 To: \(outputDir.path)")
        if !conflicts.isEmpty {
            print("  ⚠️  Would overwrite: \(conflicts.count) files")
        }
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")
        return
    }

    let progress = ProgressTracker()
    try await downloadAndRestoreFiles(
        client: client,
        files: filesToRestore,
        remotePrefix: remotePrefix,
        snapshot: snapshot,
        outputDir: outputDir,
        progress: progress
    )

    print("  \(localColor)✅ Restore complete!\(resetColor)\n")
}

@main
struct Runner {
    static func main() async {
        setupSignalHandlers()

        let args = CommandLine.arguments

        // Get command (first argument after program name)
        let command = args.count > 1 ? args[1] : "help"

        switch command {
        case "help", "-h", "--help":
            printHelp()
            return

        case "version", "-v", "--version":
            printVersion()
            return

        case "list":
            listICloudFolders()
            return

        case "test-config":
            do {
                let configURL = readConfigURL(from: args)
                let config = try loadConfig(from: configURL)
                try await testConfig(config: config, configURL: configURL)
            } catch {
                print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
                exit(1)
            }
            return

        case "backup":
            do {
                let configURL = readConfigURL(from: args)
                let config = try loadConfig(from: configURL)
                let dryRun = hasDryRunFlag(from: args)
                try await runIncrementalBackup(config: config, dryRun: dryRun)
            } catch {
                print("\u{001B}[?25h", terminator: "")
                fflush(stdout)
                print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
                exit(1)
            }
            return

        case "mirror":
            do {
                let configURL = readConfigURL(from: args)
                let config = try loadConfig(from: configURL)
                try await runMirror(config: config)
            } catch {
                print("\u{001B}[?25h", terminator: "")
                fflush(stdout)
                print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
                exit(1)
            }
            return

        case "cleanup":
            do {
                let configURL = readConfigURL(from: args)
                let config = try loadConfig(from: configURL)
                let dryRun = hasDryRunFlag(from: args)
                try await runCleanup(config: config, dryRun: dryRun)
            } catch {
                print("\u{001B}[?25h", terminator: "")
                fflush(stdout)
                print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
                exit(1)
            }
            return

        case "restore":
            do {
                let configURL = readConfigURL(from: args)
                let config = try loadConfig(from: configURL)
                let options = try parseRestoreOptions(from: args)
                let dryRun = hasDryRunFlag(from: args)

                if options.listSnapshots {
                    try await listSnapshotsCommand(config: config, options: options)
                    return
                }

                try await runRestore(config: config, options: options, dryRun: dryRun)
            } catch {
                print("\u{001B}[?25h", terminator: "")
                fflush(stdout)
                print("\n\(errorColor)Fatal error:\(resetColor) \(error)")
                exit(1)
            }
            return

        default:
            print("\(errorColor)❌ Unknown command: '\(command)'\(resetColor)")
            print("Run 'kodema help' for usage information.\n")
            exit(1)
        }
    }
}
