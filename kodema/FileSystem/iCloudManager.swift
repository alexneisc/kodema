import Foundation

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
    let startTime = Date()
    var iteration = 0
    let spinners = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    while Date() < deadline {
        do {
            let values = try url.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            let isUbiquitous = values.isUbiquitousItem ?? false
            let status = values.ubiquitousItemDownloadingStatus

            if !isUbiquitous {
                // Clear the progress line before returning
                print("\r\u{001B}[K", terminator: "")
                fflush(stdout)
                return true
            }
            if status == URLUbiquitousItemDownloadingStatus.current {
                // Clear the progress line before returning
                print("\r\u{001B}[K", terminator: "")
                fflush(stdout)
                return true
            }

            // If status is nil or NotDownloaded, try to access the file
            // macOS will download on-demand when we try to read it
            if status == nil || status == URLUbiquitousItemDownloadingStatus.notDownloaded {
                // Try to open file for reading to trigger on-demand download
                if let fileHandle = try? FileHandle(forReadingFrom: url) {
                    try? fileHandle.close()
                    // File is readable, clear progress and return success
                    print("\r\u{001B}[K", terminator: "")
                    fflush(stdout)
                    return true
                }
            }
        } catch {
            // ignore and retry
        }

        // Show progress on same line
        let elapsed = Date().timeIntervalSince(startTime)
        let elapsedStr = formatDuration(elapsed)
        let spinner = spinners[iteration % spinners.count]
        print("\r\u{001B}[K  \(cloudColor)\(spinner) Downloading from iCloud... (\(elapsedStr) elapsed)\(resetColor)", terminator: "")
        fflush(stdout)

        iteration += 1
        try? await Task.sleep(nanoseconds: 500_000_000)
        if Task.isCancelled {
            print("\r\u{001B}[K", terminator: "")
            fflush(stdout)
            return false
        }
    }

    // Clear the progress line on timeout
    print("\r\u{001B}[K", terminator: "")
    fflush(stdout)
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
