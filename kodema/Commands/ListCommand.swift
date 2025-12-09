import Foundation

// MARK: - iCloud Discovery

func findICloudDrive() -> URL? {
    // Try the standard iCloud Drive location
    let home = FileManager.default.homeDirectoryForCurrentUser
    let icloudDrive = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Mobile Documents")
        .appendingPathComponent("com~apple~CloudDocs")

    if FileManager.default.fileExists(atPath: icloudDrive.path) {
        return icloudDrive
    }
    return nil
}

func listICloudFolders() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let mobileDocsRoot = home
        .appendingPathComponent("Library")
        .appendingPathComponent("Mobile Documents")

    guard FileManager.default.fileExists(atPath: mobileDocsRoot.path) else {
        print("\(errorColor)❌ iCloud not found\(resetColor)")
        print("Make sure iCloud Drive is enabled in System Settings.")
        return
    }

    print("\n\(boldColor)☁️  iCloud Folders with Files:\(resetColor)")
    print("   \(dimColor)\(mobileDocsRoot.path)\(resetColor)")
    print("")

    let fileManager = FileManager.default

    // Apple system containers to skip
    let appleContainers = Set([
        "com~apple~CloudDocs",
        "com~apple~iCloudDrive",
        "com~apple~mail",
        "com~apple~Notes",
        "com~apple~Keynote",
        "com~apple~Pages",
        "com~apple~Numbers",
        "com~apple~TextEdit",
        "com~apple~Preview",
        "com~apple~ScriptEditor2",
        "com~apple~automator",
        "com~apple~shoebox",
        "com~apple~shortcuts"
    ])

    do {
        // Get all container directories
        let containers = try fileManager.contentsOfDirectory(
            at: mobileDocsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ).filter { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let name = url.lastPathComponent
            // Skip Apple containers
            return isDir && !appleContainers.contains(name)
        }.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }

        if containers.isEmpty {
            print("\(dimColor)No third-party iCloud containers found\(resetColor)")
            print("\(dimColor)(Apple system folders are hidden)\(resetColor)")
            return
        }

        print("\(boldColor)📦 Your Apps:\(resetColor)")
        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)\n")

        var totalContainersShown = 0

        for container in containers {
            let containerName = container.lastPathComponent

            // List folders in this container
            do {
                let folders = try fileManager.contentsOfDirectory(
                    at: container,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ).filter { url in
                    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                }.sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }

                // Count files in each folder to filter empty ones
                var foldersWithFiles: [(url: URL, fileCount: Int, totalSize: Int64)] = []

                for folder in folders {
                    var fileCount = 0
                    var totalSize: Int64 = 0

                    if let enumerator = fileManager.enumerator(
                        at: folder,
                        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                        options: [.skipsHiddenFiles]
                    ) {
                        var counted = 0
                        for case let fileURL as URL in enumerator {
                            if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                                fileCount += 1
                                if let size = fileSize(url: fileURL) {
                                    totalSize += size
                                }
                                counted += 1
                                if counted > 1000 { break } // Don't scan too deep
                            }
                        }
                    }

                    // Only include folders with files
                    if fileCount > 0 {
                        foldersWithFiles.append((url: folder, fileCount: fileCount, totalSize: totalSize))
                    }
                }

                // Skip this container if no folders with files
                if foldersWithFiles.isEmpty {
                    continue
                }

                totalContainersShown += 1

                // Decode app name from container ID (e.g., "iCloud~md~obsidian" -> "Obsidian")
                let displayName: String
                if containerName.hasPrefix("iCloud~") {
                    let appPart = containerName.replacingOccurrences(of: "iCloud~", with: "")
                        .replacingOccurrences(of: "~", with: ".")
                    displayName = "📱 \(appPart.capitalized)"
                } else {
                    displayName = containerName
                }

                print("  \(cloudColor)▶\(resetColor) \(boldColor)\(displayName)\(resetColor)")
                print("    \(dimColor)\(container.path)\(resetColor)")

                for (folder, fileCount, totalSize) in foldersWithFiles.prefix(10) {
                    let name = folder.lastPathComponent
                    print("    \(localColor)  •\(resetColor) \(name)")
                    print("      \(dimColor)Files: \(fileCount)\(fileCount >= 1000 ? "+" : "") | Size: \(formatBytes(totalSize))\(resetColor)")
                }

                if foldersWithFiles.count > 10 {
                    print("    \(dimColor)  ... and \(foldersWithFiles.count - 10) more folders\(resetColor)")
                }

                print("")

            } catch {
                // Skip containers we can't read
                continue
            }
        }

        if totalContainersShown == 0 {
            print("\(dimColor)No folders with files found\(resetColor)")
            print("\(dimColor)(Empty folders and Apple system apps are hidden)\(resetColor)\n")
            return
        }

        print("\(boldColor)═══════════════════════════════════════════════════════════════\(resetColor)")
        print("\n\(boldColor)💡 Tip:\(resetColor) Add folders to your config.yml:")
        print("\(dimColor)include:")
        print("  folders:")
        print("    # Example for Obsidian:")
        print("    - ~/Library/Mobile Documents/iCloud~md~obsidian/Documents")
        print("    # Or scan entire app container:")
        print("    - ~/Library/Mobile Documents/iCloud~md~obsidian")
        print("\n    # You can also add local folders:")
        print("    - ~/Documents")
        print("    - ~/Desktop\(resetColor)\n")

    } catch {
        print("\(errorColor)❌ Error reading iCloud:\(resetColor) \(error)")
    }
}
