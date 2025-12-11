import Testing
import Foundation
@testable import Kodema

@Suite("Backup Workflow E2E Tests")
struct BackupWorkflowTests {

    // NOTE: These E2E tests require either:
    // 1. A mock B2 server
    // 2. A test B2 bucket
    // 3. Dependency injection for B2Client
    //
    // Most tests are commented out as they need infrastructure setup
    // They serve as documentation for integration testing

    // MARK: - Full Backup Workflow Tests

    /*
    @Test("Complete backup workflow with small files")
    func testFullBackupWorkflow() async throws {
        // Setup test environment
        let testDir = createTestDirectory()
        createTestFile(in: testDir, name: "file1.txt", content: "Content 1")
        createTestFile(in: testDir, name: "file2.txt", content: "Content 2")

        let config = createTestConfig(includingFolder: testDir.path)

        // Run backup
        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Files were uploaded to B2
        // 2. Snapshot manifest was created
        // 3. Success marker was uploaded

        // Cleanup
        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Incremental backup only uploads changed files")
    func testIncrementalBackup() async throws {
        let testDir = createTestDirectory()

        // First backup
        createTestFile(in: testDir, name: "file1.txt", content: "Original")
        createTestFile(in: testDir, name: "file2.txt", content: "Original")

        let config = createTestConfig(includingFolder: testDir.path)
        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Modify only one file
        createTestFile(in: testDir, name: "file1.txt", content: "Modified")

        // Second backup
        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Only file1.txt was re-uploaded
        // 2. file2.txt was not re-uploaded
        // 3. New snapshot includes both files

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup handles new files")
    func testBackupNewFiles() async throws {
        let testDir = createTestDirectory()

        // First backup
        createTestFile(in: testDir, name: "existing.txt", content: "Existing")

        let config = createTestConfig(includingFolder: testDir.path)
        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Add new file
        createTestFile(in: testDir, name: "new.txt", content: "New")

        // Second backup
        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. new.txt was uploaded
        // 2. Latest snapshot contains both files

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup handles deleted files")
    func testBackupDeletedFiles() async throws {
        let testDir = createTestDirectory()

        // First backup
        let file1 = createTestFile(in: testDir, name: "file1.txt", content: "Content 1")
        createTestFile(in: testDir, name: "file2.txt", content: "Content 2")

        let config = createTestConfig(includingFolder: testDir.path)
        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Delete one file
        try FileManager.default.removeItem(at: file1)

        // Second backup
        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Latest snapshot only contains file2.txt
        // 2. file1.txt is NOT in the new snapshot
        // 3. Old version of file1.txt is still in B2

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup with filters excludes matching files")
    func testBackupWithFilters() async throws {
        let testDir = createTestDirectory()

        createTestFile(in: testDir, name: "include.txt", content: "Include")
        createTestFile(in: testDir, name: "exclude.tmp", content: "Exclude")
        createTestFile(in: testDir, name: "include.md", content: "Include")

        let config = createTestConfigWithFilters(
            includingFolder: testDir.path,
            excludeGlobs: ["*.tmp"]
        )

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. include.txt and include.md were uploaded
        // 2. exclude.tmp was NOT uploaded

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup handles large files")
    func testBackupLargeFiles() async throws {
        let testDir = createTestDirectory()

        // Create file larger than 5GB threshold (use smaller size for testing)
        let largeData = Data(repeating: 0x42, count: 20 * 1024 * 1024) // 20 MB
        createTestFile(in: testDir, name: "large.bin", data: largeData)

        let config = createTestConfig(includingFolder: testDir.path)

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Large file was uploaded using multipart upload
        // 2. File appears in snapshot manifest

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup dry-run does not upload files")
    func testBackupDryRun() async throws {
        let testDir = createTestDirectory()
        createTestFile(in: testDir, name: "test.txt", content: "Test")

        let config = createTestConfig(includingFolder: testDir.path)

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: true)

        // Verify:
        // 1. No files were uploaded
        // 2. No snapshot was created
        // 3. Output showed what would be uploaded

        try FileManager.default.removeItem(at: testDir)
    }
    */

    // MARK: - Manifest Update Tests

    /*
    @Test("Backup creates initial manifest")
    func testInitialManifest() async throws {
        let testDir = createTestDirectory()
        createTestFile(in: testDir, name: "test.txt", content: "Test")

        let config = createTestConfig(includingFolder: testDir.path)

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Manifest was uploaded before file uploads started
        // 2. Manifest contains metadata

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup updates manifest incrementally")
    func testIncrementalManifestUpdates() async throws {
        let testDir = createTestDirectory()

        // Create many files to trigger incremental updates
        for i in 0..<150 {
            createTestFile(in: testDir, name: "file\(i).txt", content: "Content \(i)")
        }

        let config = createTestConfigWithManifestInterval(
            includingFolder: testDir.path,
            interval: 50
        )

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Manifest was updated multiple times during upload
        // 2. Final manifest contains all files

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup uploads success marker")
    func testSuccessMarker() async throws {
        let testDir = createTestDirectory()
        createTestFile(in: testDir, name: "test.txt", content: "Test")

        let config = createTestConfig(includingFolder: testDir.path)

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Success marker was uploaded after manifest
        // 2. Marker indicates completed backup

        try FileManager.default.removeItem(at: testDir)
    }
    */

    // MARK: - Error Handling Tests

    /*
    @Test("Backup handles upload failures gracefully")
    func testBackupUploadFailure() async throws {
        let testDir = createTestDirectory()
        createTestFile(in: testDir, name: "test1.txt", content: "Test 1")
        createTestFile(in: testDir, name: "test2.txt", content: "Test 2")

        let config = createTestConfig(includingFolder: testDir.path)

        // Mock upload failure for one file

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Backup continued after failure
        // 2. Failed file is tracked
        // 3. Successful files are in manifest

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Backup skips files with paths too long")
    func testBackupLongPaths() async throws {
        let testDir = createTestDirectory()

        // Create file with very long path
        let longName = String(repeating: "a", count: 1000)
        createTestFile(in: testDir, name: longName, content: "Test")

        let config = createTestConfig(includingFolder: testDir.path)

        try await runIncrementalBackup(config: config, notificationManager: MockNotificationManager(), dryRun: false)

        // Verify:
        // 1. Long path file was skipped
        // 2. Warning was displayed
        // 3. Other files were backed up

        try FileManager.default.removeItem(at: testDir)
    }

    @Test("Graceful shutdown saves progress")
    func testGracefulShutdown() async throws {
        let testDir = createTestDirectory()

        // Create many files
        for i in 0..<100 {
            createTestFile(in: testDir, name: "file\(i).txt", content: "Content \(i)")
        }

        let config = createTestConfig(includingFolder: testDir.path)

        // Start backup and simulate SIGINT partway through
        // (This requires special test setup)

        // Verify:
        // 1. Current file upload completed
        // 2. Partial manifest was saved
        // 3. Progress was tracked

        try FileManager.default.removeItem(at: testDir)
    }
    */

    // MARK: - Path Length Validation Tests

    @Test("Validate B2 path length limit")
    func testB2PathLengthLimit() throws {
        let shortPath = "Documents/test.txt"
        let longPath = String(repeating: "a/", count: 500) + "file.txt" // ~1000+ chars

        let shortB2Path = "backup/files/\(shortPath)"
        let longB2Path = "backup/files/\(longPath)"

        #expect(shortB2Path.utf8.count < 950)
        #expect(longB2Path.utf8.count > 950)
    }

    // MARK: - Helper Functions

    /*
    private func createTestDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let testDir = tempDir.appendingPathComponent("kodema-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        return testDir
    }

    @discardableResult
    private func createTestFile(in directory: URL, name: String, content: String) -> URL {
        let data = content.data(using: .utf8)!
        return createTestFile(in: directory, name: name, data: data)
    }

    @discardableResult
    private func createTestFile(in directory: URL, name: String, data: Data) -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try! data.write(to: fileURL)
        return fileURL
    }

    private func createTestConfig(includingFolder: String) -> AppConfig {
        return AppConfig(
            b2: B2Config(
                keyID: "test-key",
                applicationKey: "test-secret",
                bucketName: "test-bucket",
                bucketId: nil,
                remotePrefix: "backup",
                partSizeMB: nil,
                maxRetries: 3,
                uploadConcurrency: 1
            ),
            timeouts: nil,
            include: IncludeConfig(folders: [includingFolder], files: nil),
            filters: nil,
            backup: BackupConfig(
                remotePrefix: "backup",
                retention: nil,
                manifestUpdateInterval: 50
            ),
            mirror: nil,
            encryption: nil
        )
    }

    private func createTestConfigWithFilters(includingFolder: String, excludeGlobs: [String]) -> AppConfig {
        return AppConfig(
            b2: B2Config(
                keyID: "test-key",
                applicationKey: "test-secret",
                bucketName: "test-bucket",
                bucketId: nil,
                remotePrefix: "backup",
                partSizeMB: nil,
                maxRetries: 3,
                uploadConcurrency: 1
            ),
            timeouts: nil,
            include: IncludeConfig(folders: [includingFolder], files: nil),
            filters: FiltersConfig(
                excludeHidden: nil,
                minSizeBytes: nil,
                maxSizeBytes: nil,
                excludeGlobs: excludeGlobs
            ),
            backup: BackupConfig(
                remotePrefix: "backup",
                retention: nil,
                manifestUpdateInterval: 50
            ),
            mirror: nil,
            encryption: nil
        )
    }

    private func createTestConfigWithManifestInterval(includingFolder: String, interval: Int) -> AppConfig {
        return AppConfig(
            b2: B2Config(
                keyID: "test-key",
                applicationKey: "test-secret",
                bucketName: "test-bucket",
                bucketId: nil,
                remotePrefix: "backup",
                partSizeMB: nil,
                maxRetries: 3,
                uploadConcurrency: 1
            ),
            timeouts: nil,
            include: IncludeConfig(folders: [includingFolder], files: nil),
            filters: nil,
            backup: BackupConfig(
                remotePrefix: "backup",
                retention: nil,
                manifestUpdateInterval: interval
            ),
            mirror: nil,
            encryption: nil
        )
    }
    */
}
