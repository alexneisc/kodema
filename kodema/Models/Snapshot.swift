import Foundation

struct FileVersionInfo: Codable {
    let path: String           // relative path from scan root (original path if encrypted)
    let size: Int64            // original file size (before encryption)
    let modificationDate: Date
    let versionTimestamp: String  // "2024-11-27_143022"
    let encrypted: Bool?       // true if file content is encrypted
    let encryptedPath: String? // encrypted path in B2 (if encryptFilenames enabled)
    let encryptedSize: Int64?  // encrypted file size (after encryption)
}

struct SnapshotManifest: Codable {
    let timestamp: String      // "2024-11-27_143022"
    let createdAt: Date
    let files: [FileVersionInfo]
    let totalFiles: Int
    let totalBytes: Int64
}
