import XCTest
@testable import Kodema

final class NotificationManagerTests: XCTestCase {

    // MARK: - Mock Tests

    func testMockNotificationManagerRecordsCalls() async {
        let mock = MockNotificationManager()

        await mock.send(title: "Test", message: "Message", sound: true)
        await mock.sendSuccess(operation: "Backup", details: "100 files")

        let count = await mock.notificationCount()
        XCTAssertEqual(count, 2)
    }

    func testMockSendNotification() async {
        let mock = MockNotificationManager()

        await mock.send(title: "Test Title", message: "Test Message", sound: false)

        let last = await mock.lastNotification()
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.title, "Test Title")
        XCTAssertEqual(last?.message, "Test Message")
        XCTAssertEqual(last?.sound, false)
        XCTAssertEqual(last?.type, .generic)
    }

    func testMockSendSuccess() async {
        let mock = MockNotificationManager()

        await mock.sendSuccess(operation: "Backup", details: "150 files uploaded")

        let last = await mock.lastNotification()
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.title, "Kodema - Backup Complete")
        XCTAssertEqual(last?.message, "150 files uploaded")
        XCTAssertEqual(last?.sound, true)
        XCTAssertEqual(last?.type, .success)
    }

    func testMockSendFailure() async {
        let mock = MockNotificationManager()

        await mock.sendFailure(operation: "Restore", details: "Network error")

        let last = await mock.lastNotification()
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.title, "Kodema - Restore Failed")
        XCTAssertEqual(last?.message, "Network error")
        XCTAssertEqual(last?.sound, true)
        XCTAssertEqual(last?.type, .failure)
    }

    func testMockSendWarning() async {
        let mock = MockNotificationManager()

        await mock.sendWarning(operation: "Cleanup", details: "Interrupted")

        let last = await mock.lastNotification()
        XCTAssertNotNil(last)
        XCTAssertEqual(last?.title, "Kodema - Cleanup Interrupted")
        XCTAssertEqual(last?.message, "Interrupted")
        XCTAssertEqual(last?.sound, true)
        XCTAssertEqual(last?.type, .warning)
    }

    func testMockMultipleNotifications() async {
        let mock = MockNotificationManager()

        await mock.sendSuccess(operation: "Op1", details: "Details1")
        await mock.sendFailure(operation: "Op2", details: "Details2")
        await mock.sendWarning(operation: "Op3", details: "Details3")

        let count = await mock.notificationCount()
        XCTAssertEqual(count, 3)

        let notifications = await mock.notifications
        XCTAssertEqual(notifications[0].type, .success)
        XCTAssertEqual(notifications[1].type, .failure)
        XCTAssertEqual(notifications[2].type, .warning)
    }

    func testMockReset() async {
        let mock = MockNotificationManager()

        await mock.send(title: "Test", message: "Test", sound: true)
        await mock.reset()

        let count = await mock.notificationCount()
        XCTAssertEqual(count, 0)

        let last = await mock.lastNotification()
        XCTAssertNil(last)
    }

    func testMockConcurrentNotifications() async {
        let mock = MockNotificationManager()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await mock.sendSuccess(operation: "Op\(i)", details: "Details\(i)")
                }
            }
        }

        let count = await mock.notificationCount()
        XCTAssertEqual(count, 10)
    }

    // MARK: - Real NotificationManager Tests (disabled by default)

    func testRealNotificationManagerDisabled() async {
        let manager = NotificationManager(enabled: false)

        // These should complete without sending actual notifications
        await manager.send(title: "Test", message: "Test", sound: true)
        await manager.sendSuccess(operation: "Test", details: "Test")

        // No assertions - just verify no crashes
    }
}
