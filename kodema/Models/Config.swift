import Foundation
import Yams

struct B2Config: Decodable {
    let keyID: String
    let applicationKey: String
    let bucketName: String
    let bucketId: String?
    let remotePrefix: String?
    let partSizeMB: Int?
    let maxRetries: Int?
    let uploadConcurrency: Int?
}

struct TimeoutsConfig: Decodable {
    let icloudDownloadSeconds: Int?
    let networkSeconds: Int?
    let overallUploadSeconds: Int?
}

struct IncludeConfig: Decodable {
    let folders: [String]?
    let files: [String]?
}

struct FiltersConfig: Decodable {
    let excludeHidden: Bool?
    let minSizeBytes: Int64?
    let maxSizeBytes: Int64?
    let excludeGlobs: [String]?
}

struct RetentionConfig: Decodable {
    let hourly: Int?    // keep all versions for last N hours
    let daily: Int?     // keep daily versions for last N days
    let weekly: Int?    // keep weekly versions for last N weeks
    let monthly: Int?   // keep monthly versions for last N months
}

struct BackupConfig: Decodable {
    let remotePrefix: String?
    let retention: RetentionConfig?
    let manifestUpdateInterval: Int?  // Update manifest every N files
}

struct MirrorConfig: Decodable {
    let remotePrefix: String?
}

enum EncryptionKeySource: String, Decodable {
    case keychain
    case file
    case passphrase
}

struct EncryptionConfig: Decodable {
    let enabled: Bool?
    let keySource: EncryptionKeySource?
    let keyFile: String?            // Path to key file (if keySource == .file)
    let keychainAccount: String?    // Keychain account name (if keySource == .keychain)
    let encryptFilenames: Bool?     // Encrypt file names in addition to content
}

struct AppConfig: Decodable {
    let b2: B2Config
    let timeouts: TimeoutsConfig?
    let include: IncludeConfig?
    let filters: FiltersConfig?
    let backup: BackupConfig?
    let mirror: MirrorConfig?
    let encryption: EncryptionConfig?
}
