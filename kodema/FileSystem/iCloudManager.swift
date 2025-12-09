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
