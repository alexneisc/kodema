import Foundation
import Darwin

private func expandTilde(in pattern: String) -> String {
    guard pattern.hasPrefix("~") else { return pattern }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return pattern.replacingOccurrences(of: "~", with: home)
}

private func containsGlobMeta(_ s: String) -> Bool {
    // Basic glob meta detection: *, ?, [abc]
    return s.contains("*") || s.contains("?") || s.contains("[")
}

private func shouldExclude(url: URL, patterns: [String]) -> Bool {
    let path = url.path

    for raw in patterns {
        // 1) Expand ~
        var pattern = expandTilde(in: raw)

        // Normalize repeated slashes, etc. (but do not remove wildcard characters)
        // Using NSString to avoid touching wildcard syntax.
        pattern = (pattern as NSString).standardizingPath

        // 2) Directory shorthands
        //   - ends with "/**" => treat as "exclude everything under this prefix"
        if pattern.hasSuffix("/**") {
            let base = String(pattern.dropLast(3)) // remove "/**"
            if path.hasPrefix(base.hasSuffix("/") ? base : base + "/") {
                return true
            }
            continue
        }
        //   - ends with "/" => same as "exclude everything under this prefix"
        if pattern.hasSuffix("/") {
            let base = pattern
            if path.hasPrefix(base) {
                return true
            }
            continue
        }

        // 3) If no glob meta => treat as exact file or directory prefix
        if !containsGlobMeta(pattern) {
            // exact file
            if path == pattern { return true }
            // directory prefix
            if path.hasPrefix(pattern + "/") { return true }
            continue
        }

        // 4) Fallback to fnmatch for real globs
        let matched: Bool = pattern.withCString { pat in
            path.withCString { str in
                // FNM_CASEFOLD for case-insensitive match on typical macOS filesystems.
                // Not using FNM_PATHNAME so that '*' may match '/' (more flexible for "**" style).
                fnmatch(pat, str, FNM_CASEFOLD) == 0
            }
        }
        if matched { return true }
    }
    return false
}

func applyFilters(_ items: [FileItem], filters: FiltersConfig?) -> [FileItem] {
    var result = items
    if let minSize = filters?.minSizeBytes {
        result = result.filter { ($0.size ?? 0) >= minSize }
    }
    if let maxSize = filters?.maxSizeBytes {
        result = result.filter { ($0.size ?? 0) <= maxSize }
    }
    if let patterns = filters?.excludeGlobs, !patterns.isEmpty {
        result = result.filter { !shouldExclude(url: $0.url, patterns: patterns) }
    }
    return result
}
