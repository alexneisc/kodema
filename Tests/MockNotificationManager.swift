import Foundation
@testable import Kodema

// MARK: - Mock Notification Manager for Tests

/// Mock notification manager that records calls instead of sending real notifications
actor MockNotificationManager: NotificationProtocol {
    struct Notification {
        let title: String
        let message: String
        let sound: Bool
        let type: NotificationType
    }

    enum NotificationType {
        case generic
        case success
        case failure
        case warning
    }

    private(set) var notifications: [Notification] = []

    func send(title: String, message: String, sound: Bool) async {
        notifications.append(Notification(
            title: title,
            message: message,
            sound: sound,
            type: .generic
        ))
    }

    func sendSuccess(operation: String, details: String) async {
        notifications.append(Notification(
            title: "Kodema - \(operation) Complete",
            message: details,
            sound: true,
            type: .success
        ))
    }

    func sendFailure(operation: String, details: String) async {
        notifications.append(Notification(
            title: "Kodema - \(operation) Failed",
            message: details,
            sound: true,
            type: .failure
        ))
    }

    func sendWarning(operation: String, details: String) async {
        notifications.append(Notification(
            title: "Kodema - \(operation) Interrupted",
            message: details,
            sound: true,
            type: .warning
        ))
    }

    // Helper methods for tests
    func reset() {
        notifications = []
    }

    func notificationCount() -> Int {
        return notifications.count
    }

    func lastNotification() -> Notification? {
        return notifications.last
    }
}
