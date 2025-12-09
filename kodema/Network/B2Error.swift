import Foundation

// MARK: - B2 Errors and retry policy

enum B2Error: Error, CustomStringConvertible {
    case unauthorized(String)
    case expiredUploadUrl(String)
    case rateLimited(Int?, String)  // 429 Too Many Requests with optional retry-after seconds
    case temporary(Int, String)
    case client(Int, String)
    case invalidResponse(String)
    case underlying(Error)

    var description: String {
        switch self {
        case .unauthorized(let m): return "Unauthorized: \(m)"
        case .expiredUploadUrl(let m): return "Expired Upload URL: \(m)"
        case .rateLimited(let retryAfter, let m):
            if let after = retryAfter {
                return "Rate Limited (retry after \(after)s): \(m)"
            } else {
                return "Rate Limited: \(m)"
            }
        case .temporary(let code, let m): return "Temporary \(code): \(m)"
        case .client(let code, let m): return "Client \(code): \(m)"
        case .invalidResponse(let m): return "Invalid Response: \(m)"
        case .underlying(let e): return "Underlying: \(e)"
        }
    }
}

func mapHTTPErrorToB2(_ error: Error) -> B2Error {
    if case let HTTPError.status(code, body) = error {
        if code == 401 {
            if body.localizedCaseInsensitiveContains("expired") ||
               body.localizedCaseInsensitiveContains("token") ||
               body.localizedCaseInsensitiveContains("unauthorized") {
                return .expiredUploadUrl(body)
            } else {
                return .unauthorized(body)
            }
        } else if code == 429 {
            // Rate limit exceeded - B2 returns 429 when API limits are hit
            return .rateLimited(nil, body)
        } else if (500...599).contains(code) {
            return .temporary(code, body)
        } else if (400...499).contains(code) {
            return .client(code, body)
        }
    }
    return .underlying(error)
}

// MARK: - Restore Errors

enum RestoreError: Error, CustomStringConvertible {
    case noSnapshotsFound
    case invalidSnapshot(String)
    case invalidSelection
    case pathNotFound(String)
    case cancelled
    case downloadFailed(String, Error)
    case writeFailed(String, Error)
    case destinationNotWritable(String)
    case insufficientDiskSpace(Int64)
    case integrityCheckFailed(String)

    var description: String {
        switch self {
        case .noSnapshotsFound: return "No snapshots found in backup"
        case .invalidSnapshot(let ts): return "Invalid snapshot: \(ts)"
        case .invalidSelection: return "Invalid selection"
        case .pathNotFound(let p): return "Path not found in snapshot: \(p)"
        case .cancelled: return "Restore cancelled by user"
        case .downloadFailed(let f, let e): return "Failed to download \(f): \(e)"
        case .writeFailed(let f, let e): return "Failed to write \(f): \(e)"
        case .destinationNotWritable(let p): return "Destination not writable: \(p)"
        case .insufficientDiskSpace(let needed): return "Insufficient disk space (need \(formatBytes(needed)))"
        case .integrityCheckFailed(let f): return "Integrity check failed: \(f)"
        }
    }
}
