import Foundation
import RNCryptor
import Security
import Darwin

class EncryptionManager {
    let config: EncryptionConfig
    private var cachedEncryptionKey: Data?
    private var cachedHmacKey: Data?
    private var cachedPassphrase: String?
    private let chunkSize = 8 * 1024 * 1024  // 8MB chunks

    init(config: EncryptionConfig) {
        self.config = config
    }

    // MARK: - Key Management

    // Get both encryption and HMAC keys (for key-based encryption)
    func getEncryptionKeys() throws -> (encryptionKey: Data, hmacKey: Data) {
        if let encKey = cachedEncryptionKey, let hmacKey = cachedHmacKey {
            return (encKey, hmacKey)
        }

        guard let keySource = config.keySource else {
            throw EncryptionError.invalidConfiguration("No key source specified")
        }

        let keys: (Data, Data)
        switch keySource {
        case .keychain:
            keys = try getKeysFromKeychain()
        case .file:
            keys = try getKeysFromFile()
        case .passphrase:
            // For passphrase, we'll use password-based encryption instead
            throw EncryptionError.invalidConfiguration("Use getPassphrase() for passphrase-based encryption")
        }

        cachedEncryptionKey = keys.0
        cachedHmacKey = keys.1
        return keys
    }

    // Get passphrase (for password-based encryption)
    func getPassphrase() throws -> String {
        if let cached = cachedPassphrase {
            return cached
        }

        guard config.keySource == .passphrase else {
            throw EncryptionError.invalidConfiguration("Passphrase only available with passphrase key source")
        }

        // Prompt user for passphrase
        print("Enter encryption passphrase: ", terminator: "")
        fflush(stdout)

        // Disable echo for password input
        var oldt = termios()
        tcgetattr(STDIN_FILENO, &oldt)
        var newt = oldt
        newt.c_lflag &= ~UInt(ECHO)
        tcsetattr(STDIN_FILENO, TCSANOW, &newt)

        defer {
            // Restore echo
            tcsetattr(STDIN_FILENO, TCSANOW, &oldt)
            print()  // New line after password
        }

        guard let passphrase = readLine(), !passphrase.isEmpty else {
            throw EncryptionError.passphraseRequired
        }

        cachedPassphrase = passphrase
        return passphrase
    }

    private func getKeysFromKeychain() throws -> (Data, Data) {
        let encAccount = config.keychainAccount ?? "kodema-encryption-key"
        let hmacAccount = (config.keychainAccount ?? "kodema-encryption-key") + "-hmac"

        // Get encryption key
        let encQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: encAccount,
            kSecReturnData as String: true
        ]

        var encResult: AnyObject?
        var status = SecItemCopyMatching(encQuery as CFDictionary, &encResult)

        guard status == errSecSuccess, let encKeyData = encResult as? Data else {
            if status == errSecItemNotFound {
                throw EncryptionError.keyNotFound
            }
            throw EncryptionError.keychainError("Failed to retrieve encryption key: \(status)")
        }

        // Get HMAC key
        let hmacQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hmacAccount,
            kSecReturnData as String: true
        ]

        var hmacResult: AnyObject?
        status = SecItemCopyMatching(hmacQuery as CFDictionary, &hmacResult)

        guard status == errSecSuccess, let hmacKeyData = hmacResult as? Data else {
            if status == errSecItemNotFound {
                throw EncryptionError.keyNotFound
            }
            throw EncryptionError.keychainError("Failed to retrieve HMAC key: \(status)")
        }

        return (encKeyData, hmacKeyData)
    }

    private func getKeysFromFile() throws -> (Data, Data) {
        guard let keyFile = config.keyFile else {
            throw EncryptionError.invalidConfiguration("Key file path not specified")
        }

        let expandedPath = NSString(string: keyFile).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EncryptionError.keyNotFound
        }

        let keyData = try Data(contentsOf: fileURL)
        // Expect 64 bytes: 32 for encryption key + 32 for HMAC key
        guard keyData.count == 64 else {
            throw EncryptionError.invalidKey
        }

        let encryptionKey = keyData.prefix(32)
        let hmacKey = keyData.suffix(32)

        return (Data(encryptionKey), Data(hmacKey))
    }

    func storeKeysInKeychain(encryptionKey: Data, hmacKey: Data) throws {
        let encAccount = config.keychainAccount ?? "kodema-encryption-key"
        let hmacAccount = (config.keychainAccount ?? "kodema-encryption-key") + "-hmac"

        // Store encryption key
        let encQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: encAccount,
            kSecValueData as String: encryptionKey
        ]

        var status = SecItemAdd(encQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: encAccount
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: encryptionKey
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to store encryption key: \(status)")
        }

        // Store HMAC key
        let hmacQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: hmacAccount,
            kSecValueData as String: hmacKey
        ]

        status = SecItemAdd(hmacQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: hmacAccount
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: hmacKey
            ]
            status = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        }

        guard status == errSecSuccess else {
            throw EncryptionError.keychainError("Failed to store HMAC key: \(status)")
        }
    }

    func generateAndStoreKeys() throws -> (Data, Data) {
        // Generate two random 256-bit keys
        var encryptionKey = Data(count: 32)
        var hmacKey = Data(count: 32)

        var result = encryptionKey.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }

        guard result == errSecSuccess else {
            throw EncryptionError.encryptionFailed("Failed to generate encryption key")
        }

        result = hmacKey.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }

        guard result == errSecSuccess else {
            throw EncryptionError.encryptionFailed("Failed to generate HMAC key")
        }

        // Store keys based on key source
        if config.keySource == .keychain {
            try storeKeysInKeychain(encryptionKey: encryptionKey, hmacKey: hmacKey)
        } else if config.keySource == .file {
            // Store in file (64 bytes: 32 encryption + 32 HMAC)
            guard let keyFile = config.keyFile else {
                throw EncryptionError.invalidConfiguration("Key file path not specified")
            }

            let expandedPath = NSString(string: keyFile).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: expandedPath)

            // Create directory if needed
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            // Combine both keys into single 64-byte file
            var combinedKeys = Data()
            combinedKeys.append(encryptionKey)
            combinedKeys.append(hmacKey)

            try combinedKeys.write(to: fileURL, options: .atomic)
        }

        cachedEncryptionKey = encryptionKey
        cachedHmacKey = hmacKey
        return (encryptionKey, hmacKey)
    }

    // MARK: - File Encryption/Decryption

    func encryptFile(inputURL: URL, outputURL: URL) throws -> Int64 {
        guard let inputStream = InputStream(url: inputURL) else {
            throw EncryptionError.encryptionFailed("Cannot open input file")
        }

        guard let outputStream = OutputStream(url: outputURL, append: false) else {
            throw EncryptionError.encryptionFailed("Cannot create output file")
        }

        inputStream.open()
        outputStream.open()

        defer {
            inputStream.close()
            outputStream.close()
        }

        // Encrypt based on key source
        var totalBytesWritten: Int64 = 0

        if config.keySource == .passphrase {
            // Password-based encryption
            let passphrase = try getPassphrase()
            let encryptor = RNCryptor.Encryptor(password: passphrase)
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: chunkSize)
                if bytesRead < 0 {
                    throw EncryptionError.encryptionFailed("Read error")
                } else if bytesRead == 0 {
                    break
                }

                let chunk = Data(bytes: buffer, count: bytesRead)
                let encryptedChunk = encryptor.update(withData: chunk)

                if !encryptedChunk.isEmpty {
                    let bytesWritten = encryptedChunk.withUnsafeBytes { ptr in
                        outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: encryptedChunk.count)
                    }
                    if bytesWritten < 0 {
                        throw EncryptionError.encryptionFailed("Write error")
                    }
                    totalBytesWritten += Int64(bytesWritten)
                }
            }

            // Finalize encryption
            let finalData = encryptor.finalData()
            if !finalData.isEmpty {
                let bytesWritten = finalData.withUnsafeBytes { ptr in
                    outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: finalData.count)
                }
                if bytesWritten < 0 {
                    throw EncryptionError.encryptionFailed("Write error on finalization")
                }
                totalBytesWritten += Int64(bytesWritten)
            }
        } else {
            // Key-based encryption
            let (encryptionKey, hmacKey) = try getEncryptionKeys()
            let encryptor = RNCryptor.EncryptorV3(encryptionKey: encryptionKey, hmacKey: hmacKey)
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: chunkSize)
                if bytesRead < 0 {
                    throw EncryptionError.encryptionFailed("Read error")
                } else if bytesRead == 0 {
                    break
                }

                let chunk = Data(bytes: buffer, count: bytesRead)
                let encryptedChunk = encryptor.update(withData: chunk)

                if !encryptedChunk.isEmpty {
                    let bytesWritten = encryptedChunk.withUnsafeBytes { ptr in
                        outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: encryptedChunk.count)
                    }
                    if bytesWritten < 0 {
                        throw EncryptionError.encryptionFailed("Write error")
                    }
                    totalBytesWritten += Int64(bytesWritten)
                }
            }

            // Finalize encryption
            let finalData = encryptor.finalData()
            if !finalData.isEmpty {
                let bytesWritten = finalData.withUnsafeBytes { ptr in
                    outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: finalData.count)
                }
                if bytesWritten < 0 {
                    throw EncryptionError.encryptionFailed("Write error on finalization")
                }
                totalBytesWritten += Int64(bytesWritten)
            }
        }

        return totalBytesWritten
    }

    func decryptFile(inputURL: URL, outputURL: URL) throws {
        guard let inputStream = InputStream(url: inputURL) else {
            throw EncryptionError.decryptionFailed("Cannot open input file")
        }

        guard let outputStream = OutputStream(url: outputURL, append: false) else {
            throw EncryptionError.decryptionFailed("Cannot create output file")
        }

        inputStream.open()
        outputStream.open()

        defer {
            inputStream.close()
            outputStream.close()
        }

        // Decrypt based on key source
        if config.keySource == .passphrase {
            // Password-based decryption
            let passphrase = try getPassphrase()
            let decryptor = RNCryptor.Decryptor(password: passphrase)
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: chunkSize)
                if bytesRead < 0 {
                    throw EncryptionError.decryptionFailed("Read error")
                } else if bytesRead == 0 {
                    break
                }

                let chunk = Data(bytes: buffer, count: bytesRead)
                do {
                    let decryptedChunk = try decryptor.update(withData: chunk)

                    if !decryptedChunk.isEmpty {
                        let bytesWritten = decryptedChunk.withUnsafeBytes { ptr in
                            outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: decryptedChunk.count)
                        }
                        if bytesWritten < 0 {
                            throw EncryptionError.decryptionFailed("Write error")
                        }
                    }
                } catch {
                    throw EncryptionError.decryptionFailed("Decryption error: \(error)")
                }
            }

            // Finalize decryption
            do {
                let finalData = try decryptor.finalData()
                if !finalData.isEmpty {
                    let bytesWritten = finalData.withUnsafeBytes { ptr in
                        outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: finalData.count)
                    }
                    if bytesWritten < 0 {
                        throw EncryptionError.decryptionFailed("Write error on finalization")
                    }
                }
            } catch {
                throw EncryptionError.decryptionFailed("Finalization error: \(error)")
            }
        } else {
            // Key-based decryption
            let (encryptionKey, hmacKey) = try getEncryptionKeys()
            let decryptor = RNCryptor.DecryptorV3(encryptionKey: encryptionKey, hmacKey: hmacKey)
            var buffer = [UInt8](repeating: 0, count: chunkSize)

            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: chunkSize)
                if bytesRead < 0 {
                    throw EncryptionError.decryptionFailed("Read error")
                } else if bytesRead == 0 {
                    break
                }

                let chunk = Data(bytes: buffer, count: bytesRead)
                do {
                    let decryptedChunk = try decryptor.update(withData: chunk)

                    if !decryptedChunk.isEmpty {
                        let bytesWritten = decryptedChunk.withUnsafeBytes { ptr in
                            outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: decryptedChunk.count)
                        }
                        if bytesWritten < 0 {
                            throw EncryptionError.decryptionFailed("Write error")
                        }
                    }
                } catch {
                    throw EncryptionError.decryptionFailed("Decryption error: \(error)")
                }
            }

            // Finalize decryption
            do {
                let finalData = try decryptor.finalData()
                if !finalData.isEmpty {
                    let bytesWritten = finalData.withUnsafeBytes { ptr in
                        outputStream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: finalData.count)
                    }
                    if bytesWritten < 0 {
                        throw EncryptionError.decryptionFailed("Write error on finalization")
                    }
                }
            } catch {
                throw EncryptionError.decryptionFailed("Finalization error: \(error)")
            }
        }
    }

    // MARK: - Filename Encryption/Decryption

    func encryptFilename(_ filename: String) throws -> String {
        let data = filename.data(using: .utf8) ?? Data()

        let encrypted: Data
        if config.keySource == .passphrase {
            // Use password-based encryption
            let passphrase = try getPassphrase()
            encrypted = RNCryptor.encrypt(data: data, withPassword: passphrase)
        } else {
            // Use key-based encryption
            let (encryptionKey, hmacKey) = try getEncryptionKeys()
            encrypted = RNCryptor.EncryptorV3(encryptionKey: encryptionKey, hmacKey: hmacKey).encrypt(data: data)
        }

        // Base64 encode with URL-safe characters
        let base64 = encrypted.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Check length (B2 has 1024 byte limit, we use 950 for safety)
        if base64.utf8.count > 900 {
            throw EncryptionError.filenameTooLong
        }

        return base64
    }

    func decryptFilename(_ encryptedFilename: String) throws -> String {
        // Restore Base64 padding and standard characters
        var base64 = encryptedFilename
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let encrypted = Data(base64Encoded: base64) else {
            throw EncryptionError.decryptionFailed("Invalid base64 encoding")
        }

        let decrypted: Data
        do {
            if config.keySource == .passphrase {
                // Use password-based decryption
                let passphrase = try getPassphrase()
                decrypted = try RNCryptor.decrypt(data: encrypted, withPassword: passphrase)
            } else {
                // Use key-based decryption
                let (encryptionKey, hmacKey) = try getEncryptionKeys()
                decrypted = try RNCryptor.DecryptorV3(encryptionKey: encryptionKey, hmacKey: hmacKey).decrypt(data: encrypted)
            }

            guard let filename = String(data: decrypted, encoding: .utf8) else {
                throw EncryptionError.decryptionFailed("Invalid UTF-8 in decrypted filename")
            }
            return filename
        } catch {
            throw EncryptionError.decryptionFailed("Filename decryption failed: \(error)")
        }
    }

    // MARK: - Data Encryption/Decryption (for manifests, small data)

    func encryptData(_ data: Data) throws -> Data {
        if config.keySource == .passphrase {
            // Use password-based encryption
            let passphrase = try getPassphrase()
            return RNCryptor.encrypt(data: data, withPassword: passphrase)
        } else {
            // Use key-based encryption
            let (encryptionKey, hmacKey) = try getEncryptionKeys()
            return RNCryptor.EncryptorV3(encryptionKey: encryptionKey, hmacKey: hmacKey).encrypt(data: data)
        }
    }

    func decryptData(_ data: Data) throws -> Data {
        do {
            if config.keySource == .passphrase {
                // Use password-based decryption
                let passphrase = try getPassphrase()
                return try RNCryptor.decrypt(data: data, withPassword: passphrase)
            } else {
                // Use key-based decryption
                let (encryptionKey, hmacKey) = try getEncryptionKeys()
                return try RNCryptor.DecryptorV3(encryptionKey: encryptionKey, hmacKey: hmacKey).decrypt(data: data)
            }
        } catch {
            throw EncryptionError.decryptionFailed("Data decryption failed: \(error)")
        }
    }
}
