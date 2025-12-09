import Foundation
import Darwin

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
