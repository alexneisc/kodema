import Testing
import Foundation
import Yams
@testable import Kodema

@Suite("Config Parsing Tests")
struct ConfigParsingTests {

    // MARK: - Basic Config Tests

    @Test("Parse minimal valid config")
    func testMinimalConfig() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.b2.keyID == "test-key-id")
        #expect(config.b2.applicationKey == "test-app-key")
        #expect(config.b2.bucketName == "test-bucket")
        #expect(config.b2.bucketId == nil)
        #expect(config.b2.remotePrefix == nil)
    }

    @Test("Parse config with all B2 fields")
    func testCompleteB2Config() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
          bucketId: test-bucket-id
          remotePrefix: backup/files
          partSizeMB: 100
          maxRetries: 5
          uploadConcurrency: 3
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.b2.keyID == "test-key-id")
        #expect(config.b2.bucketId == "test-bucket-id")
        #expect(config.b2.remotePrefix == "backup/files")
        #expect(config.b2.partSizeMB == 100)
        #expect(config.b2.maxRetries == 5)
        #expect(config.b2.uploadConcurrency == 3)
    }

    // MARK: - Timeouts Config Tests

    @Test("Parse timeouts configuration")
    func testTimeoutsConfig() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        timeouts:
          icloudDownloadSeconds: 3600
          networkSeconds: 300
          overallUploadSeconds: 7200
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.timeouts?.icloudDownloadSeconds == 3600)
        #expect(config.timeouts?.networkSeconds == 300)
        #expect(config.timeouts?.overallUploadSeconds == 7200)
    }

    @Test("Timeouts are optional")
    func testOptionalTimeouts() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.timeouts == nil)
    }

    // MARK: - Include Config Tests

    @Test("Parse include folders")
    func testIncludeFolders() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        include:
          folders:
            - ~/Documents
            - ~/Pictures
            - ~/Projects
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.include?.folders?.count == 3)
        #expect(config.include?.folders?.contains("~/Documents") == true)
        #expect(config.include?.folders?.contains("~/Pictures") == true)
        #expect(config.include?.folders?.contains("~/Projects") == true)
    }

    @Test("Parse include files")
    func testIncludeFiles() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        include:
          files:
            - ~/important.txt
            - ~/.zshrc
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.include?.files?.count == 2)
        #expect(config.include?.files?.contains("~/important.txt") == true)
    }

    // MARK: - Filters Config Tests

    @Test("Parse filters configuration")
    func testFiltersConfig() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        filters:
          excludeHidden: true
          minSizeBytes: 1024
          maxSizeBytes: 10737418240
          excludeGlobs:
            - "*.tmp"
            - "**/node_modules/**"
            - "**/.git/**"
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.filters?.excludeHidden == true)
        #expect(config.filters?.minSizeBytes == 1024)
        #expect(config.filters?.maxSizeBytes == 10737418240)
        #expect(config.filters?.excludeGlobs?.count == 3)
        #expect(config.filters?.excludeGlobs?.contains("*.tmp") == true)
    }

    @Test("Parse empty exclude globs")
    func testEmptyExcludeGlobs() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        filters:
          excludeGlobs: []
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.filters?.excludeGlobs?.isEmpty == true)
    }

    // MARK: - Retention Config Tests

    @Test("Parse retention configuration")
    func testRetentionConfig() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        backup:
          retention:
            hourly: 24
            daily: 7
            weekly: 4
            monthly: 12
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.backup?.retention?.hourly == 24)
        #expect(config.backup?.retention?.daily == 7)
        #expect(config.backup?.retention?.weekly == 4)
        #expect(config.backup?.retention?.monthly == 12)
    }

    @Test("Parse partial retention configuration")
    func testPartialRetention() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        backup:
          retention:
            hourly: 24
            monthly: 6
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.backup?.retention?.hourly == 24)
        #expect(config.backup?.retention?.daily == nil)
        #expect(config.backup?.retention?.weekly == nil)
        #expect(config.backup?.retention?.monthly == 6)
    }

    // MARK: - Backup Config Tests

    @Test("Parse backup configuration")
    func testBackupConfig() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        backup:
          remotePrefix: backup
          manifestUpdateInterval: 100
          retention:
            hourly: 24
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.backup?.remotePrefix == "backup")
        #expect(config.backup?.manifestUpdateInterval == 100)
        #expect(config.backup?.retention?.hourly == 24)
    }

    // MARK: - Mirror Config Tests

    @Test("Parse mirror configuration")
    func testMirrorConfig() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        mirror:
          remotePrefix: mirror
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.mirror?.remotePrefix == "mirror")
    }

    // MARK: - Encryption Config Tests

    @Test("Parse encryption config with keychain")
    func testEncryptionKeychain() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        encryption:
          enabled: true
          keySource: keychain
          keychainAccount: kodema-backup
          encryptFilenames: true
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.encryption?.enabled == true)
        #expect(config.encryption?.keySource == .keychain)
        #expect(config.encryption?.keychainAccount == "kodema-backup")
        #expect(config.encryption?.encryptFilenames == true)
    }

    @Test("Parse encryption config with file")
    func testEncryptionFile() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        encryption:
          enabled: true
          keySource: file
          keyFile: ~/.config/kodema/encryption.key
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.encryption?.enabled == true)
        #expect(config.encryption?.keySource == .file)
        #expect(config.encryption?.keyFile == "~/.config/kodema/encryption.key")
    }

    @Test("Parse encryption config with passphrase")
    func testEncryptionPassphrase() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        encryption:
          enabled: true
          keySource: passphrase
          encryptFilenames: false
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.encryption?.enabled == true)
        #expect(config.encryption?.keySource == .passphrase)
        #expect(config.encryption?.encryptFilenames == false)
    }

    @Test("Encryption disabled by default")
    func testEncryptionDisabled() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        encryption:
          enabled: false
        """

        let config = try parseConfig(yaml: yaml)

        #expect(config.encryption?.enabled == false)
    }

    // MARK: - Complex Config Tests

    @Test("Parse complete complex configuration")
    func testCompleteConfig() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
          partSizeMB: 50
          maxRetries: 3
          uploadConcurrency: 2

        timeouts:
          icloudDownloadSeconds: 1800
          networkSeconds: 300

        include:
          folders:
            - ~/Documents
            - ~/Projects

        filters:
          excludeHidden: true
          minSizeBytes: 100
          excludeGlobs:
            - "*.tmp"
            - "**/node_modules/**"

        backup:
          remotePrefix: backup
          manifestUpdateInterval: 50
          retention:
            hourly: 24
            daily: 7
            weekly: 4
            monthly: 12

        encryption:
          enabled: true
          keySource: keychain
          keychainAccount: kodema-backup
          encryptFilenames: true
        """

        let config = try parseConfig(yaml: yaml)

        // Verify all sections are parsed
        #expect(config.b2.keyID == "test-key-id")
        #expect(config.timeouts?.icloudDownloadSeconds == 1800)
        #expect(config.include?.folders?.count == 2)
        #expect(config.filters?.excludeGlobs?.count == 2)
        #expect(config.backup?.retention?.hourly == 24)
        #expect(config.encryption?.enabled == true)
    }

    // MARK: - Error Cases

    @Test("Fail on missing required B2 fields")
    func testMissingRequiredFields() throws {
        let yaml = """
        b2:
          keyID: test-key-id
        """

        #expect(throws: Error.self) {
            try parseConfig(yaml: yaml)
        }
    }

    @Test("Fail on invalid YAML syntax")
    func testInvalidYAML() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: [invalid
        """

        #expect(throws: Error.self) {
            try parseConfig(yaml: yaml)
        }
    }

    @Test("Fail on invalid encryption key source")
    func testInvalidKeySource() throws {
        let yaml = """
        b2:
          keyID: test-key-id
          applicationKey: test-app-key
          bucketName: test-bucket
        encryption:
          keySource: invalid-source
        """

        #expect(throws: Error.self) {
            try parseConfig(yaml: yaml)
        }
    }

    // MARK: - Helper Functions

    private func parseConfig(yaml: String) throws -> AppConfig {
        let decoder = YAMLDecoder()
        return try decoder.decode(AppConfig.self, from: yaml)
    }
}
