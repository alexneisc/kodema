import Testing
import Foundation
@testable import Kodema

@Suite("Encryption Tests")
struct EncryptionTests {

    // MARK: - Test Helpers

    /// Create test encryption manager with in-memory keys (file-based)
    private func createTestEncryptionManager() throws -> EncryptionManager {
        // Create temporary key file
        let keyData = Data(repeating: 0x42, count: 64) // 64-byte encryption + HMAC key
        let keyFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-key-\(UUID().uuidString).dat")
        try keyData.write(to: keyFileURL)

        let config = EncryptionConfig(
            enabled: true,
            keySource: .file,
            keyFile: keyFileURL.path,
            keychainAccount: nil,
            encryptFilenames: false
        )

        return EncryptionManager(config: config)
    }

    private func cleanupTestKeyFile(manager: EncryptionManager) throws {
        if let keyFile = manager.config.keyFile {
            let keyFileURL = URL(fileURLWithPath: (keyFile as NSString).expandingTildeInPath)
            try? FileManager.default.removeItem(at: keyFileURL)
        }
    }

    // MARK: - Configuration Tests

    @Test("Create encryption manager with keychain config")
    func testKeychainConfig() throws {
        let config = EncryptionConfig(
            enabled: true,
            keySource: .keychain,
            keyFile: nil,
            keychainAccount: "test-account",
            encryptFilenames: false
        )

        let manager = EncryptionManager(config: config)

        #expect(manager.config.enabled == true)
        #expect(manager.config.keySource == .keychain)
        #expect(manager.config.keychainAccount == "test-account")
    }

    @Test("Create encryption manager with file config")
    func testFileConfig() throws {
        let config = EncryptionConfig(
            enabled: true,
            keySource: .file,
            keyFile: "~/.config/kodema/key.dat",
            keychainAccount: nil,
            encryptFilenames: true
        )

        let manager = EncryptionManager(config: config)

        #expect(manager.config.keySource == .file)
        #expect(manager.config.keyFile == "~/.config/kodema/key.dat")
        #expect(manager.config.encryptFilenames == true)
    }

    @Test("Create encryption manager with passphrase config")
    func testPassphraseConfig() throws {
        let config = EncryptionConfig(
            enabled: true,
            keySource: .passphrase,
            keyFile: nil,
            keychainAccount: nil,
            encryptFilenames: false
        )

        let manager = EncryptionManager(config: config)

        #expect(manager.config.keySource == .passphrase)
    }

    // MARK: - Data Encryption/Decryption Tests

    @Test("Encrypt and decrypt small data")
    func testEncryptDecryptSmallData() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        let originalData = "Test data for encryption".data(using: .utf8)!

        let encrypted = try manager.encryptData(originalData)
        let decrypted = try manager.decryptData(encrypted)

        #expect(decrypted == originalData)
        #expect(encrypted != originalData) // Should be different when encrypted
    }

    @Test("Encrypt and decrypt large data")
    func testEncryptDecryptLargeData() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        let largeData = Data(repeating: 0x42, count: 1024 * 1024) // 1 MB

        let encrypted = try manager.encryptData(largeData)
        let decrypted = try manager.decryptData(encrypted)

        #expect(decrypted == largeData)
    }

    @Test("Encrypted data is different from original")
    func testEncryptedDataDifferent() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        let original = "secret data".data(using: .utf8)!
        let encrypted = try manager.encryptData(original)

        #expect(encrypted != original)
        #expect(encrypted.count != original.count) // Usually larger due to padding
    }

    // MARK: - Filename Encryption Tests

    @Test("Encrypt and decrypt filename")
    func testEncryptDecryptFilename() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        let originalPath = "Documents/secret/file.txt"

        let encryptedPath = try manager.encryptFilename(originalPath)
        let decryptedPath = try manager.decryptFilename(encryptedPath)

        #expect(decryptedPath == originalPath)
        #expect(encryptedPath != originalPath)
    }

    @Test("Encrypted filename is URL-safe base64")
    func testEncryptedFilenameFormat() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        let path = "Documents/test.txt"
        let encrypted = try manager.encryptFilename(path)

        // Should be URL-safe base64 (no +, /, =)
        let urlSafeCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let encryptedCharacters = CharacterSet(charactersIn: encrypted)

        #expect(urlSafeCharacters.isSuperset(of: encryptedCharacters))
    }

    // MARK: - File Encryption Tests (Requires temporary files)

    @Test("Encrypt and decrypt file")
    func testEncryptDecryptFile() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        // Create test file
        let originalContent = "File content for encryption test".data(using: .utf8)!
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-input-\(UUID().uuidString).tmp")
        try originalContent.write(to: inputURL)

        let encryptedURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-encrypted-\(UUID().uuidString).tmp")
        let decryptedURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-decrypted-\(UUID().uuidString).tmp")

        // Encrypt
        _ = try manager.encryptFile(inputURL: inputURL, outputURL: encryptedURL)

        // Decrypt
        try manager.decryptFile(inputURL: encryptedURL, outputURL: decryptedURL)

        // Verify
        let decryptedContent = try Data(contentsOf: decryptedURL)
        #expect(decryptedContent == originalContent)

        // Cleanup
        try? FileManager.default.removeItem(at: inputURL)
        try? FileManager.default.removeItem(at: encryptedURL)
        try? FileManager.default.removeItem(at: decryptedURL)
    }

    @Test("Encrypt large file in chunks")
    func testEncryptLargeFile() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        // Create 10 MB file (larger than 8 MB chunk size)
        let largeContent = Data(repeating: 0xAB, count: 10 * 1024 * 1024)
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-large-\(UUID().uuidString).tmp")
        try largeContent.write(to: inputURL)

        let encryptedURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-large-enc-\(UUID().uuidString).tmp")
        let decryptedURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-large-dec-\(UUID().uuidString).tmp")

        // Encrypt
        _ = try manager.encryptFile(inputURL: inputURL, outputURL: encryptedURL)

        // Decrypt
        try manager.decryptFile(inputURL: encryptedURL, outputURL: decryptedURL)

        // Verify
        let decryptedContent = try Data(contentsOf: decryptedURL)
        #expect(decryptedContent == largeContent)

        // Cleanup
        try? FileManager.default.removeItem(at: inputURL)
        try? FileManager.default.removeItem(at: encryptedURL)
        try? FileManager.default.removeItem(at: decryptedURL)
    }

    @Test("Encrypted file size is different")
    func testEncryptedFileSize() throws {
        let manager = try createTestEncryptionManager()
        defer { try? cleanupTestKeyFile(manager: manager) }

        let content = "Test content".data(using: .utf8)!
        let inputURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-size-\(UUID().uuidString).tmp")
        try content.write(to: inputURL)

        let encryptedURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-size-enc-\(UUID().uuidString).tmp")

        _ = try manager.encryptFile(inputURL: inputURL, outputURL: encryptedURL)

        let originalSize = try FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as! UInt64
        let encryptedSize = try FileManager.default.attributesOfItem(atPath: encryptedURL.path)[.size] as! UInt64

        // Encrypted file should be larger (due to RNCryptor header and padding)
        #expect(encryptedSize > originalSize)

        // Cleanup
        try? FileManager.default.removeItem(at: inputURL)
        try? FileManager.default.removeItem(at: encryptedURL)
    }

    // MARK: - Error Handling Tests

    @Test("Throw error when key source not specified")
    func testMissingKeySource() throws {
        let config = EncryptionConfig(
            enabled: true,
            keySource: nil,
            keyFile: nil,
            keychainAccount: nil,
            encryptFilenames: false
        )

        let manager = EncryptionManager(config: config)

        // Should throw when trying to get keys without key source
        #expect(throws: EncryptionError.self) {
            try manager.getEncryptionKeys()
        }
    }

    @Test("Throw error when using getEncryptionKeys with passphrase source")
    func testPassphraseWithGetKeys() throws {
        let config = EncryptionConfig(
            enabled: true,
            keySource: .passphrase,
            keyFile: nil,
            keychainAccount: nil,
            encryptFilenames: false
        )

        let manager = EncryptionManager(config: config)

        // getEncryptionKeys should not work with passphrase source
        #expect(throws: EncryptionError.self) {
            try manager.getEncryptionKeys()
        }
    }

    // MARK: - Configuration Validation Tests

    @Test("Valid keychain configuration")
    func testValidKeychainConfiguration() throws {
        let config = EncryptionConfig(
            enabled: true,
            keySource: .keychain,
            keyFile: nil,
            keychainAccount: "test-account",
            encryptFilenames: false
        )

        #expect(config.keySource == .keychain)
        #expect(config.keychainAccount != nil)
    }

    @Test("Valid file configuration")
    func testValidFileConfiguration() throws {
        let config = EncryptionConfig(
            enabled: true,
            keySource: .file,
            keyFile: "~/.config/kodema/key",
            keychainAccount: nil,
            encryptFilenames: false
        )

        #expect(config.keySource == .file)
        #expect(config.keyFile != nil)
    }

    @Test("Encryption disabled configuration")
    func testDisabledConfiguration() throws {
        let config = EncryptionConfig(
            enabled: false,
            keySource: nil,
            keyFile: nil,
            keychainAccount: nil,
            encryptFilenames: false
        )

        #expect(config.enabled == false)
    }

    // MARK: - Edge Cases

    @Test("Handle nil optional fields")
    func testNilOptionalFields() throws {
        let config = EncryptionConfig(
            enabled: nil,
            keySource: nil,
            keyFile: nil,
            keychainAccount: nil,
            encryptFilenames: nil
        )

        let manager = EncryptionManager(config: config)

        #expect(manager.config.enabled == nil)
        #expect(manager.config.keySource == nil)
    }

    // MARK: - Helper Functions

    /*
    private func createTestConfig() -> EncryptionConfig {
        // This would create a test config with test keys
        // For actual testing, you'd need to set up test keys in keychain
        // or use a test key file
        return EncryptionConfig(
            enabled: true,
            keySource: .passphrase,
            keyFile: nil,
            keychainAccount: nil,
            encryptFilenames: false
        )
    }

    private func createTempFile(content: Data) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-\(UUID().uuidString).tmp"
        let fileURL = tempDir.appendingPathComponent(fileName)
        try! content.write(to: fileURL)
        return fileURL
    }

    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "test-\(UUID().uuidString).tmp"
        return tempDir.appendingPathComponent(fileName)
    }
    */
}
