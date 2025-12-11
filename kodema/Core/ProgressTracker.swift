import Foundation

struct ProgressStats {
    let completed: Int
    let failed: Int
    let skipped: Int
    let total: Int
    let completedBytes: Int64
    let totalBytes: Int64
    let elapsed: TimeInterval
}

actor ProgressTracker {
    private(set) var totalFiles: Int = 0
    private(set) var completedFiles: Int = 0
    private(set) var failedFiles: Int = 0
    private(set) var skippedFiles: Int = 0
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

    func fileSkipped() {
        skippedFiles += 1
        currentFileName = ""
    }

    func currentProgress() -> (completed: Int, failed: Int, skipped: Int, total: Int, uploadedBytes: Int64, totalBytes: Int64, currentFile: String, elapsed: TimeInterval) {
        return (completedFiles, failedFiles, skippedFiles, totalFiles, uploadedBytes, totalBytes, currentFileName, Date().timeIntervalSince(startTime))
    }

    func getStats() -> ProgressStats {
        return ProgressStats(
            completed: completedFiles,
            failed: failedFiles,
            skipped: skippedFiles,
            total: totalFiles,
            completedBytes: uploadedBytes,
            totalBytes: totalBytes,
            elapsed: Date().timeIntervalSince(startTime)
        )
    }

    func printProgress() {
        let (completed, failed, skipped, total, uploaded, totalSize, currentFile, elapsed) = currentProgress()
        let remaining = total - completed - failed - skipped
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
        var statusLine = "\(boldColor)[\(bar)] \(String(format: "%.1f", percentage))%\(resetColor) | " +
              "\(localColor)\(completed) ✅\(resetColor) " +
              "\(errorColor)\(failed) ❌\(resetColor) "
        if skipped > 0 {
            statusLine += "\(dimColor)\(skipped) ⏭️\(resetColor) "
        }
        statusLine += "\(dimColor)\(remaining) ⏳\(resetColor) | " +
              "\(uploadedStr)/\(totalStr) | " +
              "\(speedStr) | " +
              "ETA: \(etaStr)"
        print(statusLine, terminator: "")

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
        let (completed, failed, skipped, _, uploaded, totalSize, _, elapsed) = currentProgress()

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
        if skipped > 0 {
            print("  \(dimColor)⏭️  Skipped:\(resetColor) \(skipped) files (path too long)")
        }
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
