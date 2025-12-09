import Foundation

func remoteFileName(for localURL: URL, remotePrefix: String?) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let localPath = localURL.path
    var relative = localPath
    if localPath.hasPrefix(home.path) {
        relative = String(localPath.dropFirst(home.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    } else {
        relative = localURL.lastPathComponent
    }
    if let prefix = remotePrefix, !prefix.isEmpty {
        return "\(prefix)/\(relative)".replacingOccurrences(of: "//", with: "/")
    } else {
        return relative
    }
}
