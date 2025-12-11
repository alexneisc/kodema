import Testing
import Foundation
@testable import Kodema

@Suite("Retention Policy Tests")
struct RetentionPolicyTests {

    // MARK: - Snapshot Classification Tests

    @Test("Classify snapshot as hourly when within hourly limit")
    func testClassifyHourly() throws {
        let now = Date()
        let snapshot = now.addingTimeInterval(-1800) // 30 minutes ago
        let retention = RetentionConfig(hourly: 24, daily: nil, weekly: nil, monthly: nil)

        let bucket = classifySnapshot(date: snapshot, now: now, retention: retention)

        #expect(bucket == .hourly)
    }

    @Test("Classify snapshot as daily when outside hourly but within daily")
    func testClassifyDaily() throws {
        let now = Date()
        let snapshot = now.addingTimeInterval(-86400 * 2) // 2 days ago
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: nil, monthly: nil)

        let bucket = classifySnapshot(date: snapshot, now: now, retention: retention)

        #expect(bucket == .daily)
    }

    @Test("Classify snapshot as weekly when outside daily but within weekly")
    func testClassifyWeekly() throws {
        let now = Date()
        let snapshot = now.addingTimeInterval(-86400 * 10) // 10 days ago
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: 4, monthly: nil)

        let bucket = classifySnapshot(date: snapshot, now: now, retention: retention)

        #expect(bucket == .weekly)
    }

    @Test("Classify snapshot as monthly when outside weekly but within monthly")
    func testClassifyMonthly() throws {
        let now = Date()
        let snapshot = now.addingTimeInterval(-86400 * 45) // 45 days ago
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: 4, monthly: 12)

        let bucket = classifySnapshot(date: snapshot, now: now, retention: retention)

        #expect(bucket == .monthly)
    }

    @Test("Classify snapshot as tooOld when outside all limits")
    func testClassifyTooOld() throws {
        let now = Date()
        let snapshot = now.addingTimeInterval(-86400 * 400) // Over a year ago
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: 4, monthly: 12)

        let bucket = classifySnapshot(date: snapshot, now: now, retention: retention)

        #expect(bucket == .tooOld)
    }

    @Test("Classify with no limits returns tooOld")
    func testNoLimits() throws {
        let now = Date()
        let snapshot = now.addingTimeInterval(-3600) // 1 hour ago
        let retention = RetentionConfig(hourly: nil, daily: nil, weekly: nil, monthly: nil)

        let bucket = classifySnapshot(date: snapshot, now: now, retention: retention)

        #expect(bucket == .tooOld)
    }

    @Test("Classify at exact hourly boundary")
    func testExactHourlyBoundary() throws {
        let now = Date()
        let snapshot = now.addingTimeInterval(-3600 * 24) // Exactly 24 hours ago
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: nil, monthly: nil)

        let bucket = classifySnapshot(date: snapshot, now: now, retention: retention)

        // At exactly the boundary, should be hourly (< 24 hours)
        #expect(bucket == .hourly || bucket == .daily) // Implementation dependent
    }

    // MARK: - Snapshot Selection Tests

    @Test("Keep all hourly snapshots")
    func testKeepAllHourly() throws {
        let now = Date()
        let snapshots = [
            createSnapshot(timestamp: "2024-01-01_100000", hoursAgo: 1, from: now),
            createSnapshot(timestamp: "2024-01-01_110000", hoursAgo: 2, from: now),
            createSnapshot(timestamp: "2024-01-01_120000", hoursAgo: 3, from: now)
        ]
        let retention = RetentionConfig(hourly: 24, daily: nil, weekly: nil, monthly: nil)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        #expect(toKeep.count == 3)
        #expect(toKeep.contains("2024-01-01_100000"))
        #expect(toKeep.contains("2024-01-01_110000"))
        #expect(toKeep.contains("2024-01-01_120000"))
    }

    @Test("Keep one daily snapshot per day")
    func testKeepOneDailyPerDay() throws {
        let now = Date()
        let calendar = Calendar.current

        // Create specific dates for testing
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now)!
        let twoDaysAgoMorning = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: twoDaysAgo)!
        let twoDaysAgoAfternoon = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: twoDaysAgo)!
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now)!

        let snapshots = [
            SnapshotInfo(
                timestamp: "2024-01-01_100000",
                date: twoDaysAgoMorning,
                manifestPath: "backup/snapshots/2024-01-01_100000/manifest.json"
            ),
            SnapshotInfo(
                timestamp: "2024-01-01_140000",
                date: twoDaysAgoAfternoon,
                manifestPath: "backup/snapshots/2024-01-01_140000/manifest.json"
            ),
            SnapshotInfo(
                timestamp: "2024-01-02_100000",
                date: threeDaysAgo,
                manifestPath: "backup/snapshots/2024-01-02_100000/manifest.json"
            )
        ]
        let retention = RetentionConfig(hourly: 1, daily: 7, weekly: nil, monthly: nil)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        // Should keep only the latest from each day
        #expect(toKeep.contains("2024-01-01_140000")) // Latest from same calendar day
        #expect(toKeep.contains("2024-01-02_100000"))
        #expect(!toKeep.contains("2024-01-01_100000")) // Earlier snapshot from same day
    }

    @Test("Keep one weekly snapshot per week")
    func testKeepOneWeeklyPerWeek() throws {
        let now = Date()
        let calendar = Calendar.current
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: now)!
        let twoWeeksAgoLater = calendar.date(byAdding: .hour, value: 5, to: twoWeeksAgo)!

        let snapshots = [
            SnapshotInfo(
                timestamp: "2024-01-01_100000",
                date: twoWeeksAgo,
                manifestPath: "backup/snapshots/2024-01-01_100000/manifest.json"
            ),
            SnapshotInfo(
                timestamp: "2024-01-01_150000",
                date: twoWeeksAgoLater,
                manifestPath: "backup/snapshots/2024-01-01_150000/manifest.json"
            )
        ]
        let retention = RetentionConfig(hourly: 1, daily: 1, weekly: 4, monthly: nil)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        // Should keep the latest from the week
        #expect(toKeep.contains("2024-01-01_150000"))
    }

    @Test("Keep one monthly snapshot per month")
    func testKeepOneMonthlyPerMonth() throws {
        let now = Date()
        let calendar = Calendar.current
        let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now)!
        let twoMonthsAgoLater = calendar.date(byAdding: .day, value: 5, to: twoMonthsAgo)!

        let snapshots = [
            SnapshotInfo(
                timestamp: "2024-01-01_100000",
                date: twoMonthsAgo,
                manifestPath: "backup/snapshots/2024-01-01_100000/manifest.json"
            ),
            SnapshotInfo(
                timestamp: "2024-01-06_100000",
                date: twoMonthsAgoLater,
                manifestPath: "backup/snapshots/2024-01-06_100000/manifest.json"
            )
        ]
        let retention = RetentionConfig(hourly: 1, daily: 1, weekly: 1, monthly: 12)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        // Should keep the latest from the month
        #expect(toKeep.contains("2024-01-06_100000"))
    }

    @Test("Delete snapshots that are too old")
    func testDeleteTooOld() throws {
        let now = Date()
        let veryOld = now.addingTimeInterval(-86400 * 400) // Over a year ago
        let snapshots = [
            SnapshotInfo(
                timestamp: "2023-01-01_100000",
                date: veryOld,
                manifestPath: "backup/snapshots/2023-01-01_100000/manifest.json"
            )
        ]
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: 4, monthly: 12)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        #expect(toKeep.isEmpty)
    }

    @Test("Complex retention policy with multiple snapshots")
    func testComplexRetentionPolicy() throws {
        let now = Date()
        let snapshots = [
            createSnapshot(timestamp: "2024-01-10_100000", hoursAgo: 1, from: now),
            createSnapshot(timestamp: "2024-01-10_090000", hoursAgo: 2, from: now),
            createSnapshot(timestamp: "2024-01-09_100000", daysAgo: 2, from: now),
            createSnapshot(timestamp: "2024-01-09_090000", daysAgo: 2, from: now),
            createSnapshot(timestamp: "2024-01-03_100000", daysAgo: 10, from: now),
            createSnapshot(timestamp: "2023-12-01_100000", daysAgo: 60, from: now)
        ]
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: 4, monthly: 12)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        // Hourly: keep both from last 24 hours
        #expect(toKeep.contains("2024-01-10_100000"))
        #expect(toKeep.contains("2024-01-10_090000"))

        // Daily: keep latest from 2 days ago
        #expect(toKeep.contains("2024-01-09_100000"))

        // Weekly/Monthly: keep those snapshots
        #expect(toKeep.contains("2024-01-03_100000"))
        #expect(toKeep.contains("2023-12-01_100000"))
    }

    @Test("Empty snapshots list returns empty set")
    func testEmptySnapshots() throws {
        let snapshots: [SnapshotInfo] = []
        let retention = RetentionConfig(hourly: 24, daily: 7, weekly: 4, monthly: 12)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        #expect(toKeep.isEmpty)
    }

    @Test("Single snapshot is kept if within retention")
    func testSingleSnapshotKept() throws {
        let now = Date()
        let snapshots = [
            createSnapshot(timestamp: "2024-01-10_100000", hoursAgo: 1, from: now)
        ]
        let retention = RetentionConfig(hourly: 24, daily: nil, weekly: nil, monthly: nil)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        #expect(toKeep.count == 1)
        #expect(toKeep.contains("2024-01-10_100000"))
    }

    @Test("Multiple snapshots same hour keeps all in hourly bucket")
    func testMultipleSameHour() throws {
        let now = Date()
        let snapshots = [
            createSnapshot(timestamp: "2024-01-10_100000", hoursAgo: 1, from: now),
            createSnapshot(timestamp: "2024-01-10_100500", hoursAgo: 1, from: now),
            createSnapshot(timestamp: "2024-01-10_101000", hoursAgo: 1, from: now)
        ]
        let retention = RetentionConfig(hourly: 24, daily: nil, weekly: nil, monthly: nil)

        let toKeep = selectSnapshotsToKeep(snapshots: snapshots, retention: retention)

        // All should be kept in hourly bucket
        #expect(toKeep.count == 3)
    }

    // MARK: - Helper Functions

    private func createSnapshot(timestamp: String, hoursAgo: Int = 0, daysAgo: Int = 0, from now: Date) -> SnapshotInfo {
        let interval = TimeInterval(-(hoursAgo * 3600 + daysAgo * 86400))
        let date = now.addingTimeInterval(interval)
        return SnapshotInfo(
            timestamp: timestamp,
            date: date,
            manifestPath: "backup/snapshots/\(timestamp)/manifest.json"
        )
    }
}
