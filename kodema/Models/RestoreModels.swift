import Foundation

struct RestoreOptions {
    var snapshotTimestamp: String?
    var paths: [String]               // File/folder filters
    var outputDirectory: URL?
    var force: Bool
    var listSnapshots: Bool
}

struct FileConflict {
    let relativePath: String
    let existingURL: URL
    let existingSize: Int64?
    let existingMtime: Date?
    let restoreSize: Int64
    let restoreMtime: Date
}
