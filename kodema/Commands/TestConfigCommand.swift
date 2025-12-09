import Foundation

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

    // 3. Folders and files validation
    print("\n\(boldColor)Folders and Files to Backup:\(resetColor)")

    let folders = config.include?.folders ?? []
    let files = config.include?.files ?? []

    guard !folders.isEmpty || !files.isEmpty else {
        print("  \(errorColor)✗ No folders or files configured\(resetColor)")
        print("    Add folders to config under 'include.folders' or files under 'include.files'")
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
    var longPathFiles = 0

    let remotePrefix = config.backup?.remotePrefix ?? "backup"
    let timestamp = "20250101_000000"  // Sample timestamp for path length calculation
    let folderURLs = folders.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }

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
            let scanResult: (Int, Int64, Int, Int) = {
                var files = 0
                var bytes: Int64 = 0
                var notDownloaded = 0
                var longPaths = 0

                guard let enumerator = fm.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    return (0, 0, 0, 0)
                }

                for case let fileURL as URL in enumerator {
                    if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
                       let isFile = resourceValues.isRegularFile,
                       isFile {
                        files += 1
                        if let size = resourceValues.fileSize {
                            bytes += Int64(size)
                        }

                        // Check path length
                        let relativePath = buildRelativePath(for: fileURL, from: folderURLs)
                        let versionPath = "\(remotePrefix)/files/\(relativePath)/\(timestamp)"
                        if versionPath.utf8.count > maxB2PathLength {
                            longPaths += 1
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

                return (files, bytes, notDownloaded, longPaths)
            }()

            folderFiles = scanResult.0
            folderBytes = scanResult.1
            folderICloudNotDownloaded = scanResult.2
            let folderLongPaths = scanResult.3

            totalFiles += folderFiles
            totalBytes += folderBytes
            icloudNotDownloaded += folderICloudNotDownloaded
            longPathFiles += folderLongPaths

            print("  \(localColor)✓\(resetColor) \(folder) (\(folderFiles) files, \(formatBytes(folderBytes)))")
        } else {
            print("  \(errorColor)✗ \(folder) - folder does not exist\(resetColor)")
            print("    Remove this folder from config or create it")
            hasErrors = true
        }
    }

    // Check individual files
    for file in files {
        let expandedPath = NSString(string: file).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) && !isDir.boolValue {
            // Check file properties
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
               let size = resourceValues.fileSize {
                totalFiles += 1
                totalBytes += Int64(size)

                // Check path length
                let relativePath = fileURL.lastPathComponent
                let versionPath = "\(remotePrefix)/files/\(relativePath)/\(timestamp)"
                if versionPath.utf8.count > maxB2PathLength {
                    longPathFiles += 1
                }

                // Check iCloud status
                if let isUbiquitous = resourceValues.isUbiquitousItem, isUbiquitous {
                    if let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus {
                        if downloadStatus != URLUbiquitousItemDownloadingStatus.current {
                            icloudNotDownloaded += 1
                        }
                    }
                }

                print("  \(localColor)✓\(resetColor) \(file) (\(formatBytes(Int64(size))))")
            } else {
                print("  \(errorColor)✗ \(file) - cannot read file properties\(resetColor)")
                hasErrors = true
            }
        } else if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir) && isDir.boolValue {
            print("  \(errorColor)✗ \(file) - is a directory, not a file\(resetColor)")
            print("    Use 'include.folders' for directories")
            hasErrors = true
        } else {
            print("  \(errorColor)✗ \(file) - file does not exist\(resetColor)")
            print("    Remove this file from config or create it")
            hasErrors = true
        }
    }

    if icloudNotDownloaded > 0 {
        print("  \(errorColor)⚠\(resetColor)  iCloud: \(icloudNotDownloaded) files not yet downloaded locally")
        print("    These will be downloaded automatically during backup")
        hasWarnings = true
    }

    if longPathFiles > 0 {
        print("  \(errorColor)⚠\(resetColor)  Path length: \(longPathFiles) files have paths longer than \(maxB2PathLength) bytes")
        print("    These files will be skipped during backup due to B2 limits")
        print("    Consider using excludeGlobs to filter out deep folder structures")
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
