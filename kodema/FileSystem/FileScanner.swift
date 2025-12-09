import Foundation

func buildFoldersToScan(from config: AppConfig) throws -> [URL] {
    let hasFolders = config.include?.folders?.isEmpty == false
    let hasFiles = config.include?.files?.isEmpty == false
    guard hasFolders || hasFiles else {
        throw ConfigError.missingFolders
    }
    if let folders = config.include?.folders {
        return folders.map { URL(fileURLWithPath: $0).expandedTilde() }
    }
    return []
}

func buildFilesToScan(from config: AppConfig) -> [URL] {
    if let files = config.include?.files {
        return files.map { URL(fileURLWithPath: $0).expandedTilde() }
    }
    return []
}

func scanFolder(url: URL, excludeHidden: Bool) -> [FileItem] {
    var files: [FileItem] = []
    let fileManager = FileManager.default
    let options: FileManager.DirectoryEnumerationOptions = excludeHidden ? [.skipsHiddenFiles] : []
    guard let enumerator = fileManager.enumerator(at: url,
                                                  includingPropertiesForKeys: [
                                                    .isRegularFileKey,
                                                    .isUbiquitousItemKey,
                                                    .ubiquitousItemDownloadingStatusKey,
                                                    .fileSizeKey,
                                                    .contentModificationDateKey
                                                  ],
                                                  options: options) else {
        return []
    }
    for case let fileURL as URL in enumerator {
        do {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                let status = checkFileStatus(url: fileURL)
                let size = fileSize(url: fileURL)
                let mtime = fileModificationDate(url: fileURL)
                files.append(FileItem(url: fileURL, status: status, size: size, modificationDate: mtime))
            }
        } catch {
            continue
        }
    }
    return files
}

func scanFile(url: URL) -> FileItem? {
    let fileManager = FileManager.default
    do {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        if values.isRegularFile == true {
            let status = checkFileStatus(url: url)
            let size = fileSize(url: url)
            let mtime = fileModificationDate(url: url)
            return FileItem(url: url, status: status, size: size, modificationDate: mtime)
        }
    } catch {
        // File doesn't exist or not accessible
    }
    return nil
}
