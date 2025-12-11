import XCTest
@testable import Kodema

final class ProgressTrackerTests: XCTestCase {

    // MARK: - Initialization Tests

    func testProgressTrackerInitialization() async {
        let tracker = ProgressTracker()

        await tracker.initialize(totalFiles: 100, totalBytes: 1000000)

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.total, 100)
        XCTAssertEqual(stats.totalBytes, 1000000)
        XCTAssertEqual(stats.completed, 0)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertEqual(stats.skipped, 0)
        XCTAssertEqual(stats.completedBytes, 0)
    }

    // MARK: - File Completion Tests

    func testFileCompleted() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        await tracker.fileCompleted(bytes: 5000)

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.completed, 1)
        XCTAssertEqual(stats.completedBytes, 5000)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertEqual(stats.skipped, 0)
    }

    func testMultipleFilesCompleted() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        await tracker.fileCompleted(bytes: 1000)
        await tracker.fileCompleted(bytes: 2000)
        await tracker.fileCompleted(bytes: 3000)

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.completed, 3)
        XCTAssertEqual(stats.completedBytes, 6000)
    }

    // MARK: - File Failed Tests

    func testFileFailed() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        await tracker.fileFailed()

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.completed, 0)
        XCTAssertEqual(stats.failed, 1)
        XCTAssertEqual(stats.skipped, 0)
    }

    func testMultipleFilesFailed() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        await tracker.fileFailed()
        await tracker.fileFailed()

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.failed, 2)
    }

    // MARK: - File Skipped Tests

    func testFileSkipped() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        await tracker.fileSkipped()

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.completed, 0)
        XCTAssertEqual(stats.failed, 0)
        XCTAssertEqual(stats.skipped, 1)
    }

    func testMultipleFilesSkipped() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        await tracker.fileSkipped()
        await tracker.fileSkipped()
        await tracker.fileSkipped()

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.skipped, 3)
    }

    // MARK: - Mixed Operations Tests

    func testMixedOperations() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 20, totalBytes: 200000)

        await tracker.fileCompleted(bytes: 10000)
        await tracker.fileCompleted(bytes: 20000)
        await tracker.fileFailed()
        await tracker.fileSkipped()
        await tracker.fileCompleted(bytes: 5000)
        await tracker.fileFailed()

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.completed, 3)
        XCTAssertEqual(stats.completedBytes, 35000)
        XCTAssertEqual(stats.failed, 2)
        XCTAssertEqual(stats.skipped, 1)
        XCTAssertEqual(stats.total, 20)
        XCTAssertEqual(stats.totalBytes, 200000)
    }

    // MARK: - getStats Tests

    func testGetStatsReturnsCorrectValues() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 50, totalBytes: 500000)

        await tracker.fileCompleted(bytes: 100000)
        await tracker.fileCompleted(bytes: 150000)
        await tracker.fileFailed()
        await tracker.fileSkipped()

        let stats = await tracker.getStats()

        XCTAssertEqual(stats.completed, 2)
        XCTAssertEqual(stats.completedBytes, 250000)
        XCTAssertEqual(stats.failed, 1)
        XCTAssertEqual(stats.skipped, 1)
        XCTAssertEqual(stats.total, 50)
        XCTAssertEqual(stats.totalBytes, 500000)
        XCTAssertGreaterThan(stats.elapsed, 0)
    }

    func testGetStatsElapsedTime() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        // Wait a small amount of time
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        let stats = await tracker.getStats()
        XCTAssertGreaterThan(stats.elapsed, 0)
        XCTAssertLessThan(stats.elapsed, 1.0) // Should be less than 1 second
    }

    // MARK: - Concurrent Operations Tests

    func testConcurrentFileOperations() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 100, totalBytes: 1000000)

        // Simulate concurrent file operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 3 == 0 {
                        await tracker.fileFailed()
                    } else if i % 3 == 1 {
                        await tracker.fileSkipped()
                    } else {
                        await tracker.fileCompleted(bytes: 1000)
                    }
                }
            }
        }

        let stats = await tracker.getStats()

        // Verify total operations equal 50
        let totalOperations = stats.completed + stats.failed + stats.skipped
        XCTAssertEqual(totalOperations, 50)
    }

    // MARK: - Edge Cases Tests

    func testZeroFiles() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 0, totalBytes: 0)

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.total, 0)
        XCTAssertEqual(stats.totalBytes, 0)
        XCTAssertEqual(stats.completed, 0)
    }

    func testLargeNumbers() async {
        let tracker = ProgressTracker()
        let largeFileCount = 1_000_000
        let largeBytesCount: Int64 = 1_000_000_000_000 // 1 TB

        await tracker.initialize(totalFiles: largeFileCount, totalBytes: largeBytesCount)

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.total, largeFileCount)
        XCTAssertEqual(stats.totalBytes, largeBytesCount)
    }

    // MARK: - Current File Name Tests

    func testStartFile() async {
        let tracker = ProgressTracker()
        await tracker.initialize(totalFiles: 10, totalBytes: 100000)

        await tracker.startFile(name: "test.txt")

        // We can't directly test currentFileName as it's private,
        // but we can verify it doesn't crash
        await tracker.fileCompleted(bytes: 1000)

        let stats = await tracker.getStats()
        XCTAssertEqual(stats.completed, 1)
    }
}
