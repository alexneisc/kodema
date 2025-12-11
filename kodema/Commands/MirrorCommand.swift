import Foundation

// MARK: - Mirror logic (simple upload all)

func runMirror(config: AppConfig, notificationManager: NotificationProtocol) async throws {
    let progress = ProgressTracker()

    let excludeHidden = config.filters?.excludeHidden ?? true
    let folders = try buildFoldersToScan(from: config)
    let files = buildFilesToScan(from: config)

    // Scan
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

    // Send notification with detailed status
    let stats = await progress.getStats()
    if stats.failed > 0 {
        // Has failures - send warning
        var details = "\(stats.completed) uploaded (\(formatBytes(stats.completedBytes))), \(stats.failed) failed"
        if stats.skipped > 0 {
            details += ", \(stats.skipped) skipped"
        }
        await notificationManager.sendWarning(operation: "Mirror", details: details)
    } else if stats.skipped > 0 {
        // No failures but has skipped files - send success with note
        await notificationManager.sendSuccess(
            operation: "Mirror",
            details: "\(stats.completed) uploaded (\(formatBytes(stats.completedBytes))), \(stats.skipped) skipped"
        )
    } else {
        // Perfect - no failures, no skipped
        await notificationManager.sendSuccess(
            operation: "Mirror",
            details: "\(stats.completed) files uploaded (\(formatBytes(stats.completedBytes)))"
        )
    }
}
