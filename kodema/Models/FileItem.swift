import Foundation

struct FileItem {
    let url: URL
    let status: String   // "Local" | "Cloud" | "Error"
    let size: Int64?
    let modificationDate: Date?
}
