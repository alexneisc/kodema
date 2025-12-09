import Foundation
import Yams

extension URL {
    func expandedTilde() -> URL {
        if path.hasPrefix("~") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let expanded = path.replacingOccurrences(of: "~", with: home)
            return URL(fileURLWithPath: expanded)
        }
        return self
    }
}

func readConfigURL(from arguments: [String]) -> URL {
    // Look for --config or -c flag
    for i in 0..<arguments.count {
        if (arguments[i] == "--config" || arguments[i] == "-c") && i + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[i + 1]).expandedTilde()
        }
    }

    // Default config path
    let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config")
        .appendingPathComponent("kodema")
        .appendingPathComponent("config.yml")
    return defaultPath
}

func hasDryRunFlag(from arguments: [String]) -> Bool {
    return arguments.contains("--dry-run") || arguments.contains("-n")
}

func loadConfig(from url: URL) throws -> AppConfig {
    let data = try Data(contentsOf: url)
    guard let yamlString = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 in config"])
    }
    let decoder = YAMLDecoder()
    return try decoder.decode(AppConfig.self, from: yamlString)
}

// MARK: - Timeout helpers (safe under strict concurrency)

enum TimeoutError: Error {
    case timedOut
}

enum ConfigError: Error, CustomStringConvertible {
    case missingFolders
    case noFoldersConfigured
    case validationFailed

    var description: String {
        switch self {
        case .missingFolders:
            return "No folders configured. Please specify folders to backup in config.yml under 'include.folders'"
        case .noFoldersConfigured:
            return "No folders configured in include.folders"
        case .validationFailed:
            return "Configuration validation failed"
        }
    }
}

enum EncryptionError: Error, CustomStringConvertible {
    case keyNotFound
    case invalidKey
    case encryptionFailed(String)
    case decryptionFailed(String)
    case keychainError(String)
    case passphraseRequired
    case invalidConfiguration(String)
    case filenameTooLong

    var description: String {
        switch self {
        case .keyNotFound:
            return "Encryption key not found"
        case .invalidKey:
            return "Invalid encryption key"
        case .encryptionFailed(let msg):
            return "Encryption failed: \(msg)"
        case .decryptionFailed(let msg):
            return "Decryption failed: \(msg)"
        case .keychainError(let msg):
            return "Keychain error: \(msg)"
        case .passphraseRequired:
            return "Passphrase required for encryption"
        case .invalidConfiguration(let msg):
            return "Invalid encryption configuration: \(msg)"
        case .filenameTooLong:
            return "Encrypted filename exceeds maximum length"
        }
    }
}

// These wrappers don't create concurrent tasks to avoid requiring Sendable for captured objects.
func withTimeoutVoid(_ seconds: TimeInterval, _ operation: () async throws -> Void) async throws {
    try await operation()
}

func withTimeoutDataResponse(_ seconds: TimeInterval, _ operation: () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
    try await operation()
}

func withTimeoutBool(_ seconds: TimeInterval, _ operation: () async -> Bool) async throws -> Bool {
    await operation()
}
