import Foundation

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

func selectSnapshotInteractively(snapshots: [SnapshotInfo], client: B2Client, remotePrefix: String, encryptionManager: EncryptionManager?) async throws -> SnapshotManifest {
    guard !snapshots.isEmpty else {
        throw RestoreError.noSnapshotsFound
    }

    print("\n\(boldColor)Available Snapshots:\(resetColor)")
    print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")

    let displayCount = min(snapshots.count, 10)
    for (index, snapshot) in snapshots.prefix(displayCount).enumerated() {
        var manifestData = try await client.downloadFile(fileName: snapshot.manifestPath)

        // Decrypt manifest if encryption is enabled
        if let encryptionManager = encryptionManager {
            manifestData = try encryptionManager.decryptData(manifestData)
        }

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

    var manifestData = try await client.downloadFile(fileName: selectedSnapshot.manifestPath)

    // Decrypt manifest if encryption is enabled
    if let encryptionManager = encryptionManager {
        manifestData = try encryptionManager.decryptData(manifestData)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(SnapshotManifest.self, from: manifestData)
}

func getTargetSnapshot(client: B2Client, remotePrefix: String, options: RestoreOptions, encryptionManager: EncryptionManager?) async throws -> SnapshotManifest {
    if let timestamp = options.snapshotTimestamp {
        let manifestPath = "\(remotePrefix)/snapshots/\(timestamp)/manifest.json"
        do {
            var data = try await client.downloadFile(fileName: manifestPath)

            // Decrypt manifest if encryption is enabled
            if let encryptionManager = encryptionManager {
                data = try encryptionManager.decryptData(data)
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SnapshotManifest.self, from: data)
        } catch {
            throw RestoreError.invalidSnapshot(timestamp)
        }
    } else {
        let snapshots = try await fetchAllSnapshots(client: client, remotePrefix: remotePrefix)
        return try await selectSnapshotInteractively(snapshots: snapshots, client: client, remotePrefix: remotePrefix, encryptionManager: encryptionManager)
    }
}

func listSnapshotsCommand(config: AppConfig, options: RestoreOptions) async throws {
    let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
    let maxRetries = config.b2.maxRetries ?? 3
    let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)
    let remotePrefix = config.backup?.remotePrefix ?? "backup"

    // Initialize encryption manager if encryption enabled
    var encryptionManager: EncryptionManager?
    if let encryptionConfig = config.encryption, encryptionConfig.enabled == true {
        encryptionManager = EncryptionManager(config: encryptionConfig)
    }

    let allSnapshots = try await fetchAllSnapshots(client: client, remotePrefix: remotePrefix)

    guard !allSnapshots.isEmpty else {
        print("\n\(dimColor)No snapshots found\(resetColor)\n")
        return
    }

    var snapshots: [(SnapshotInfo, SnapshotManifest)] = []
    for snapshot in allSnapshots {
        var manifestData = try await client.downloadFile(fileName: snapshot.manifestPath)

        // Decrypt manifest if encryption is enabled
        if let encryptionManager = encryptionManager {
            manifestData = try encryptionManager.decryptData(manifestData)
        }

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

func downloadAndRestoreFiles(client: B2Client, files: [FileVersionInfo], remotePrefix: String, snapshot: SnapshotManifest, outputDir: URL, progress: ProgressTracker, encryptionManager: EncryptionManager?) async throws {
    let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
    await progress.initialize(totalFiles: files.count, totalBytes: totalBytes)

    var skippedEncrypted = 0

    for file in files {
        await progress.startFile(name: "\(file.path) (\(formatBytes(file.size)))")
        await progress.printProgress()

        do {
            // Check if file is encrypted
            let isEncrypted = file.encrypted == true

            // Build remote path (handle encrypted filenames)
            var remotePath: String
            if isEncrypted {
                if let encryptedPath = file.encryptedPath {
                    remotePath = "\(remotePrefix)/files/\(encryptedPath)/\(file.versionTimestamp).encrypted"
                } else {
                    remotePath = "\(remotePrefix)/files/\(file.path)/\(file.versionTimestamp).encrypted"
                }
            } else {
                remotePath = "\(remotePrefix)/files/\(file.path)/\(file.versionTimestamp)"
            }

            let localPath = outputDir.appendingPathComponent(file.path)

            try FileManager.default.createDirectory(
                at: localPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if isEncrypted {
                // Handle encrypted file
                guard let encMgr = encryptionManager else {
                    print("\n\(errorColor)⚠️  Skipping encrypted file \(file.path) - no encryption key available\(resetColor)")
                    skippedEncrypted += 1
                    await progress.fileSkipped()
                    continue
                }

                // Download to temp location
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("encrypted")

                defer {
                    try? FileManager.default.removeItem(at: tempURL)
                }

                try await client.downloadFileStreaming(fileName: remotePath, to: tempURL)

                // Decrypt to final location
                do {
                    try encMgr.decryptFile(inputURL: tempURL, outputURL: localPath)
                } catch {
                    print("\n\(errorColor)✗ Failed to decrypt \(file.path): \(error)\(resetColor)")
                    await progress.fileFailed()
                    continue
                }
            } else {
                // Direct download for unencrypted files
                try await client.downloadFileStreaming(fileName: remotePath, to: localPath)
            }

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

    if skippedEncrypted > 0 {
        print("\n\(errorColor)⚠️  Skipped \(skippedEncrypted) encrypted file(s) - encryption key not available\(resetColor)")
        print("  \(dimColor)Configure encryption in your config file and try again\(resetColor)")
    }
}

func runRestore(config: AppConfig, options: RestoreOptions, notificationManager: NotificationProtocol, dryRun: Bool = false) async throws {
    let networkTimeout = TimeInterval(config.timeouts?.networkSeconds ?? 300)
    let maxRetries = config.b2.maxRetries ?? 3
    let client = B2Client(cfg: config.b2, networkTimeout: networkTimeout, maxRetries: maxRetries)
    let remotePrefix = config.backup?.remotePrefix ?? "backup"

    // Initialize encryption manager if encryption enabled
    var encryptionManager: EncryptionManager?
    if let encryptionConfig = config.encryption, encryptionConfig.enabled == true {
        encryptionManager = EncryptionManager(config: encryptionConfig)
    }

    if dryRun {
        print("\n\(boldColor)Starting restore (DRY RUN - no changes will be made)\(resetColor)")
    } else {
        print("\n\(boldColor)Starting restore\(resetColor)")
    }

    let snapshot = try await getTargetSnapshot(client: client, remotePrefix: remotePrefix, options: options, encryptionManager: encryptionManager)
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

    // Check if output directory exists, create if needed
    if options.outputDirectory != nil {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory)

        if !exists {
            // Try to create the directory
            do {
                try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
                print("  \(localColor)✓\(resetColor) Created output directory: \(outputDir.path)")
            } catch {
                print("\n\(errorColor)✗ Error: Output directory does not exist and cannot be created\(resetColor)")
                print("  Directory: \(outputDir.path)")
                print("  \(dimColor)Reason: \(error.localizedDescription)\(resetColor)")
                print("\n\(boldColor)Suggestions:\(resetColor)")
                print("  • Create the directory manually: mkdir -p \"\(outputDir.path)\"")
                print("  • Check parent directory permissions")
                print("  • Use a different output directory with --output <path>")
                print("  • Omit --output to restore to original locations\n")
                throw RestoreError.invalidSelection
            }
        } else if !isDirectory.boolValue {
            print("\n\(errorColor)✗ Error: Output path exists but is not a directory\(resetColor)")
            print("  Path: \(outputDir.path)")
            print("\n\(boldColor)Suggestions:\(resetColor)")
            print("  • Use a different output directory with --output <path>")
            print("  • Remove the file at this path if it's not needed\n")
            throw RestoreError.invalidSelection
        }
    }

    let totalBytes = filesToRestore.reduce(Int64(0)) { $0 + $1.size }
    print("  💾 Total size: \(formatBytes(totalBytes))")

    // Warn if restoring to original location (no --output specified)
    if options.outputDirectory == nil && !dryRun && !options.force {
        print("\n\(errorColor)⚠️  Warning:\(resetColor) You are about to restore files to their original locations.")
        print("  This may overwrite your current files!")
        print("  Consider using --output <directory> to restore to a different location.")
        print("\n\(boldColor)Options:\(resetColor)")
        print("  c - Continue with restore to original location")
        print("  s - Cancel")
        print("\nSelect option: ", terminator: "")
        fflush(stdout)

        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            throw RestoreError.cancelled
        }

        switch input {
        case "c", "continue":
            print("\(localColor)✓\(resetColor) Continuing...\n")
        case "s", "skip", "cancel":
            throw RestoreError.cancelled
        default:
            throw RestoreError.invalidSelection
        }
    }

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
        progress: progress,
        encryptionManager: encryptionManager
    )

    print("  \(localColor)✅ Restore complete!\(resetColor)\n")

    // Send notification with detailed status
    let stats = await progress.getStats()
    if stats.failed > 0 {
        // Has failures - send warning
        var details = "\(stats.completed) restored (\(formatBytes(stats.completedBytes))), \(stats.failed) failed"
        if stats.skipped > 0 {
            details += ", \(stats.skipped) skipped"
        }
        await notificationManager.sendWarning(operation: "Restore", details: details)
    } else if stats.skipped > 0 {
        // No failures but has skipped files - send success with note
        await notificationManager.sendSuccess(
            operation: "Restore",
            details: "\(stats.completed) restored (\(formatBytes(stats.completedBytes))), \(stats.skipped) skipped"
        )
    } else {
        // Perfect - no failures, no skipped
        await notificationManager.sendSuccess(
            operation: "Restore",
            details: "\(stats.completed) files restored (\(formatBytes(stats.completedBytes)))"
        )
    }
}
