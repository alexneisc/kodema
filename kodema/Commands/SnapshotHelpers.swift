import Foundation

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
func fetchLatestManifest(client: B2Client, remotePrefix: String, encryptionManager: EncryptionManager?) async throws -> SnapshotManifest? {
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

    var data = try await client.downloadFile(fileName: latest.fileName)

    // Decrypt manifest if encryption is enabled
    if let encryptionManager = encryptionManager {
        do {
            data = try encryptionManager.decryptData(data)
        } catch {
            // If decryption fails, try parsing as plaintext (backward compatibility)
            // This allows reading old unencrypted manifests
            print("  \(dimColor)ℹ️  Manifest is plaintext (pre-encryption)\(resetColor)")
        }
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SnapshotManifest.self, from: data)
}

// Upload manifest to B2
func uploadManifest(client: B2Client, manifestFiles: [FileVersionInfo], timestamp: String, remotePrefix: String, encryptionManager: EncryptionManager?) async throws {
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
    var manifestData = try encoder.encode(manifest)

    // Encrypt manifest if encryption is enabled
    if let encryptionManager = encryptionManager {
        manifestData = try encryptionManager.encryptData(manifestData)
    }

    let manifestPath = "\(remotePrefix)/snapshots/\(timestamp)/manifest.json"
    let manifestTempURL = FileManager.default.temporaryDirectory.appendingPathComponent("manifest_\(timestamp).json")
    try manifestData.write(to: manifestTempURL)
    defer { try? FileManager.default.removeItem(at: manifestTempURL) }

    let manifestSha1 = try sha1HexStream(fileURL: manifestTempURL)
    let contentType = encryptionManager != nil ? "application/octet-stream" : "application/json"
    try await client.uploadSmallFile(fileURL: manifestTempURL, fileName: manifestPath, contentType: contentType, sha1Hex: manifestSha1)
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
