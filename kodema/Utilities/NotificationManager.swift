import Foundation

// MARK: - Notification Protocol

/// Protocol for sending notifications
protocol NotificationProtocol: Actor {
    /// Send a notification with title and message
    func send(title: String, message: String, sound: Bool) async

    /// Send a success notification for completed operations
    func sendSuccess(operation: String, details: String) async

    /// Send a failure notification for failed operations
    func sendFailure(operation: String, details: String) async

    /// Send a warning notification for interrupted operations
    func sendWarning(operation: String, details: String) async
}

// MARK: - Notification Manager

/// Manages macOS system notifications for kodema operations
actor NotificationManager: NotificationProtocol {
    private let enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    /// Send a notification with title and message
    func send(title: String, message: String, sound: Bool = true) async {
        guard enabled else { return }

        let soundParam = sound ? "sound name \"default\"" : ""
        let script = """
        display notification "\(escapeForAppleScript(message))" \
        with title "\(escapeForAppleScript(title))" \
        \(soundParam)
        """

        await executeAppleScript(script)
    }

    /// Send a success notification for completed operations
    func sendSuccess(operation: String, details: String) async {
        await send(title: "Kodema - \(operation) Complete", message: details, sound: true)
    }

    /// Send a failure notification for failed operations
    func sendFailure(operation: String, details: String) async {
        await send(title: "Kodema - \(operation) Failed", message: details, sound: true)
    }

    /// Send a warning notification for interrupted operations
    func sendWarning(operation: String, details: String) async {
        await send(title: "Kodema - \(operation) Interrupted", message: details, sound: true)
    }

    // MARK: - Private Helpers

    private func escapeForAppleScript(_ text: String) -> String {
        // Escape quotes and backslashes for AppleScript
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func executeAppleScript(_ script: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        // Suppress output
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // Silently fail if notification cannot be sent
            // This prevents notification errors from breaking the main operation
        }
    }
}
