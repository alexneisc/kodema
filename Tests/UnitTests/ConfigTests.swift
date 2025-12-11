import XCTest
import Yams
@testable import Kodema

final class ConfigTests: XCTestCase {

    // MARK: - Notifications Config Tests

    func testNotificationsConfigEnabled() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        notifications:
          enabled: true
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        XCTAssertNotNil(config.notifications)
        XCTAssertEqual(config.notifications?.enabled, true)
    }

    func testNotificationsConfigDisabled() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        notifications:
          enabled: false
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        XCTAssertNotNil(config.notifications)
        XCTAssertEqual(config.notifications?.enabled, false)
    }

    func testNotificationsConfigMissing() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        // Notifications config is optional, should be nil if not specified
        XCTAssertNil(config.notifications)
    }

    func testNotificationsConfigWithoutEnabled() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        notifications:
          enabled:
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        // When enabled field is explicitly null in YAML, it should be nil
        XCTAssertNotNil(config.notifications)
        XCTAssertNil(config.notifications?.enabled)
    }

    // MARK: - Full Config Tests

    func testFullConfigWithNotifications() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
          partSizeMB: 100
          maxRetries: 3
          uploadConcurrency: 1
        timeouts:
          icloudDownloadSeconds: 1800
          networkSeconds: 300
          overallUploadSeconds: 7200
        include:
          folders:
            - ~/Documents
            - ~/Desktop
        filters:
          excludeHidden: true
          minSizeBytes: 0
          maxSizeBytes: 10737418240
          excludeGlobs:
            - "*.tmp"
            - "**/.DS_Store"
        backup:
          remotePrefix: "backup"
          manifestUpdateInterval: 50
          retention:
            hourly: 24
            daily: 30
            weekly: 12
            monthly: 12
        mirror:
          remotePrefix: "mirror"
        encryption:
          enabled: false
        notifications:
          enabled: true
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        // Verify B2 config
        XCTAssertEqual(config.b2.keyID, "test_key")
        XCTAssertEqual(config.b2.applicationKey, "test_app_key")
        XCTAssertEqual(config.b2.bucketName, "test-bucket")

        // Verify timeouts
        XCTAssertNotNil(config.timeouts)
        XCTAssertEqual(config.timeouts?.icloudDownloadSeconds, 1800)

        // Verify include
        XCTAssertNotNil(config.include)
        XCTAssertEqual(config.include?.folders?.count, 2)

        // Verify filters
        XCTAssertNotNil(config.filters)
        XCTAssertEqual(config.filters?.excludeHidden, true)

        // Verify backup
        XCTAssertNotNil(config.backup)
        XCTAssertEqual(config.backup?.remotePrefix, "backup")

        // Verify mirror
        XCTAssertNotNil(config.mirror)
        XCTAssertEqual(config.mirror?.remotePrefix, "mirror")

        // Verify encryption
        XCTAssertNotNil(config.encryption)
        XCTAssertEqual(config.encryption?.enabled, false)

        // Verify notifications
        XCTAssertNotNil(config.notifications)
        XCTAssertEqual(config.notifications?.enabled, true)
    }

    // MARK: - Minimal Config Tests

    func testMinimalConfig() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        // Only B2 config is required
        XCTAssertEqual(config.b2.keyID, "test_key")

        // All other configs should be nil
        XCTAssertNil(config.timeouts)
        XCTAssertNil(config.include)
        XCTAssertNil(config.filters)
        XCTAssertNil(config.backup)
        XCTAssertNil(config.mirror)
        XCTAssertNil(config.encryption)
        XCTAssertNil(config.notifications)
    }

    // MARK: - Default Values Tests

    func testNotificationDefaultValue() {
        // Test that when notifications config is missing, we default to false
        let config = AppConfig(
            b2: B2Config(
                keyID: "test",
                applicationKey: "test",
                bucketName: "test",
                bucketId: nil,
                remotePrefix: nil,
                partSizeMB: nil,
                maxRetries: nil,
                uploadConcurrency: nil
            ),
            timeouts: nil,
            include: nil,
            filters: nil,
            backup: nil,
            mirror: nil,
            encryption: nil,
            notifications: nil
        )

        // Default behavior: notifications disabled when config is nil
        let enabled = config.notifications?.enabled ?? false
        XCTAssertFalse(enabled)
    }

    func testNotificationEnabledByDefault() {
        let config = AppConfig(
            b2: B2Config(
                keyID: "test",
                applicationKey: "test",
                bucketName: "test",
                bucketId: nil,
                remotePrefix: nil,
                partSizeMB: nil,
                maxRetries: nil,
                uploadConcurrency: nil
            ),
            timeouts: nil,
            include: nil,
            filters: nil,
            backup: nil,
            mirror: nil,
            encryption: nil,
            notifications: NotificationsConfig(enabled: true)
        )

        let enabled = config.notifications?.enabled ?? false
        XCTAssertTrue(enabled)
    }

    // MARK: - Invalid Config Tests

    func testInvalidNotificationsValue() {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        notifications:
          enabled: "not_a_boolean"
        """

        let decoder = YAMLDecoder()

        // Should throw decoding error for invalid boolean value
        XCTAssertThrowsError(try decoder.decode(AppConfig.self, from: yamlString))
    }

    // MARK: - Encryption Config Tests (existing functionality)

    func testEncryptionConfigKeychain() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        encryption:
          enabled: true
          keySource: keychain
          keychainAccount: "kodema-key"
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        XCTAssertNotNil(config.encryption)
        XCTAssertEqual(config.encryption?.enabled, true)
        XCTAssertEqual(config.encryption?.keySource, .keychain)
        XCTAssertEqual(config.encryption?.keychainAccount, "kodema-key")
    }

    func testEncryptionConfigFile() throws {
        let yamlString = """
        b2:
          keyID: "test_key"
          applicationKey: "test_app_key"
          bucketName: "test-bucket"
        encryption:
          enabled: true
          keySource: file
          keyFile: "~/.config/kodema/key.bin"
        """

        let decoder = YAMLDecoder()
        let config = try decoder.decode(AppConfig.self, from: yamlString)

        XCTAssertNotNil(config.encryption)
        XCTAssertEqual(config.encryption?.enabled, true)
        XCTAssertEqual(config.encryption?.keySource, .file)
        XCTAssertEqual(config.encryption?.keyFile, "~/.config/kodema/key.bin")
    }
}
