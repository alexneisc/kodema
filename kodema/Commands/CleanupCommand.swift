import Foundation

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

func runCleanup(config: AppConfig, notificationManager: NotificationProtocol, dryRun: Bool = false) async throws {
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

    // Initialize encryption manager if encryption enabled
    var encryptionManager: EncryptionManager?
    if let encryptionConfig = config.encryption, encryptionConfig.enabled == true {
        encryptionManager = EncryptionManager(config: encryptionConfig)
    }

    // Fetch all snapshots
    print("  ☁️  Fetching snapshots from B2...")
    let snapshotFiles = try await client.listFiles(prefix: "\(remotePrefix)/snapshots/")

    // Parse snapshot list
    var snapshots: [SnapshotInfo] = []
    for file in snapshotFiles {
        // Expected format: backup/snapshots/2024-11-27_143022/manifest.json
        let components = file.fileName.split(separator: "/")
        guard components.count >= 3,
              let date = parseTimestamp(String(components[components.count - 2])) else {
            continue
        }
        snapshots.append(SnapshotInfo(
            timestamp: String(components[components.count - 2]),
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
                var manifestData = try await client.downloadFile(fileName: snapshot.manifestPath)

                // Decrypt manifest if encryption is enabled
                if let encryptionManager = encryptionManager {
                    manifestData = try encryptionManager.decryptData(manifestData)
                }

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
        // Expected format: backup/files/Library/Mobile Documents/iCloud~md~obsidian/notes/work.md/2024-11-27_143022
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

    // Send success notification (only for actual cleanup, not dry run)
    if !dryRun {
        await notificationManager.sendSuccess(
            operation: "Cleanup",
            details: "Removed \(deletedSnapshots) old snapshots, retained \(toKeep.count)"
        )
    }
}
