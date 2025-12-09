import Foundation

// MARK: - Main backup logic (incremental with snapshots)

func runIncrementalBackup(config: AppConfig, dryRun: Bool = false) async throws {
    let progress = ProgressTracker()

    let excludeHidden = config.filters?.excludeHidden ?? true
    let folders = try buildFoldersToScan(from: config)
    let files = buildFilesToScan(from: config)

    // Scan local files
    var allFiles: [FileItem] = []
    for folder in folders {
        allFiles.append(contentsOf: scanFolder(url: folder, excludeHidden: excludeHidden))
    }
    for file in files {
        if let fileItem = scanFile(url: file) {
            allFiles.append(fileItem)
        }
    }
    allFiles = applyFilters(allFiles, filters: config.filters)

    // Prepare B2 client
    let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
    let overallUploadTimeout = TimeInterval(config.timeouts?.overallUploadSeconds ?? 7200)
    let icloudTimeout = config.timeouts?.icloudDownloadSeconds ?? 1800
    let maxRetries = config.b2.maxRetries ?? 3
    let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)

    // Initialize encryption manager if encryption enabled
    var encryptionManager: EncryptionManager?
    if let encryptionConfig = config.encryption, encryptionConfig.enabled == true {
        encryptionManager = EncryptionManager(config: encryptionConfig)
        print("  🔐 Encryption enabled")
    }

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
    let latestManifest = try await fetchLatestManifest(client: client, remotePrefix: remotePrefix, encryptionManager: encryptionManager)
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
        try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix, encryptionManager: encryptionManager)
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

            // Prepare upload path and encryption
            var uploadURL = url
            var uploadPath = "\(remotePrefix)/files/\(relativePath)/\(timestamp)"
            var isEncrypted = false
            var encryptedFilePath: String?
            var encryptedFileSize: Int64?
            var tempEncryptedURL: URL?

            // Encrypt file if encryption enabled
            if let encMgr = encryptionManager {
                do {
                    // Encrypt filename if configured
                    if encMgr.config.encryptFilenames == true {
                        let encryptedFileName = try encMgr.encryptFilename(relativePath)
                        uploadPath = "\(remotePrefix)/files/\(encryptedFileName)/\(timestamp)"
                        encryptedFilePath = encryptedFileName
                    }

                    // Create temp file for encrypted content
                    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("encrypted")

                    // Encrypt file content
                    encryptedFileSize = try encMgr.encryptFile(inputURL: url, outputURL: tempURL)
                    uploadURL = tempURL
                    tempEncryptedURL = tempURL
                    isEncrypted = true
                    uploadPath += ".encrypted"
                } catch {
                    print("  \(errorColor)⚠️  Encryption failed: \(error)\(resetColor)")
                    await progress.fileFailed()
                    continue
                }
            }

            // Check if path length exceeds B2 limit
            let pathByteCount = uploadPath.utf8.count
            if pathByteCount > maxB2PathLength {
                print("  \(errorColor)⚠️  Skipping file with path too long (\(pathByteCount) bytes > \(maxB2PathLength) limit)\(resetColor)")
                print("  \(dimColor)   Path: \(uploadPath)\(resetColor)")
                if let temp = tempEncryptedURL {
                    try? FileManager.default.removeItem(at: temp)
                }
                await progress.fileSkipped()
                await progress.printProgress()
                continue
            }

            let contentType = guessContentType(for: url)
            let originalSize = file.size ?? (fileSize(url: url) ?? 0)
            let mtime = file.modificationDate ?? Date()

            await progress.startFile(name: "\(url.lastPathComponent) (\(formatBytes(originalSize)))")
            await progress.printProgress()

            let smallFileThreshold: Int64 = 5 * 1024 * 1024 * 1024 // 5 GB
            let uploadSize = encryptedFileSize ?? originalSize

            if uploadSize <= smallFileThreshold {
                let sha1 = try sha1HexStream(fileURL: uploadURL)
                try await withTimeoutVoid(overallUploadTimeout) {
                    try await client.uploadSmallFile(fileURL: uploadURL, fileName: uploadPath, contentType: contentType, sha1Hex: sha1)
                }
            } else {
                try await withTimeoutVoid(overallUploadTimeout) {
                    try await client.uploadLargeFile(fileURL: uploadURL, fileName: uploadPath, contentType: contentType, partSize: partSizeBytes, concurrency: uploadConcurrency)
                }
            }

            // Clean up temp encrypted file
            if let temp = tempEncryptedURL {
                try? FileManager.default.removeItem(at: temp)
            }

            await progress.fileCompleted(bytes: originalSize)

            // Update manifest: replace old version or add new
            if let existingIndex = manifestFiles.firstIndex(where: { $0.path == relativePath }) {
                manifestFiles[existingIndex] = FileVersionInfo(
                    path: relativePath,
                    size: originalSize,
                    modificationDate: mtime,
                    versionTimestamp: timestamp,
                    encrypted: isEncrypted ? true : nil,
                    encryptedPath: encryptedFilePath,
                    encryptedSize: encryptedFileSize
                )
            } else {
                manifestFiles.append(FileVersionInfo(
                    path: relativePath,
                    size: originalSize,
                    modificationDate: mtime,
                    versionTimestamp: timestamp,
                    encrypted: isEncrypted ? true : nil,
                    encryptedPath: encryptedFilePath,
                    encryptedSize: encryptedFileSize
                ))
            }

            if status == "Cloud" {
                evictIfUbiquitous(url: url)
            }

            // Incremental manifest update
            filesUploadedSinceLastManifest += 1
            if filesUploadedSinceLastManifest >= manifestUpdateInterval {
                do {
                    try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix, encryptionManager: encryptionManager)
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
        try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix, encryptionManager: encryptionManager)

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
    try await uploadManifest(client: client, manifestFiles: manifestFiles, timestamp: timestamp, remotePrefix: remotePrefix, encryptionManager: encryptionManager)
    try await uploadSuccessMarker(client: client, timestamp: timestamp, remotePrefix: remotePrefix)

    await progress.printFinal()
    print("  📸 Snapshot manifest uploaded: \(remotePrefix)/snapshots/\(timestamp)/manifest.json")
    print("  ✅ Backup completed successfully")
}
