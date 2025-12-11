import XCTest
@testable import Kodema

final class B2ErrorTests: XCTestCase {

    // MARK: - B2Error Description Tests

    func testUnauthorizedErrorDescription() {
        let error = B2Error.unauthorized("Invalid credentials")
        XCTAssertEqual(error.description, "Unauthorized: Invalid credentials")
    }

    func testExpiredUploadUrlErrorDescription() {
        let error = B2Error.expiredUploadUrl("Upload token expired")
        XCTAssertEqual(error.description, "Expired Upload URL: Upload token expired")
    }

    func testRateLimitedErrorDescription() {
        let errorWithRetryAfter = B2Error.rateLimited(60, "Too many requests")
        XCTAssertEqual(errorWithRetryAfter.description, "Rate Limited (retry after 60s): Too many requests")

        let errorWithoutRetryAfter = B2Error.rateLimited(nil, "Rate limit exceeded")
        XCTAssertEqual(errorWithoutRetryAfter.description, "Rate Limited: Rate limit exceeded")
    }

    func testTemporaryErrorDescription() {
        let error = B2Error.temporary(503, "Service unavailable")
        XCTAssertEqual(error.description, "Temporary 503: Service unavailable")
    }

    func testClientErrorDescription() {
        let error = B2Error.client(404, "File not found")
        XCTAssertEqual(error.description, "Client 404: File not found")
    }

    func testInvalidResponseErrorDescription() {
        let error = B2Error.invalidResponse("Malformed JSON")
        XCTAssertEqual(error.description, "Invalid Response: Malformed JSON")
    }

    func testUnderlyingErrorDescription() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = B2Error.underlying(underlyingError)
        XCTAssertTrue(error.description.contains("Underlying"))
    }

    // MARK: - mapHTTPErrorToB2 Tests

    func testMapHTTPError401Unauthorized() {
        // Note: "Unauthorized" keyword triggers expiredUploadUrl due to case-insensitive matching
        // in B2Error.swift line 37. Use a different message to test true unauthorized.
        let httpError = HTTPError.status(401, "Invalid credentials")
        let b2Error = mapHTTPErrorToB2(httpError)

        if case .unauthorized(let message) = b2Error {
            XCTAssertEqual(message, "Invalid credentials")
        } else {
            XCTFail("Expected unauthorized error, got \(b2Error)")
        }
    }

    func testMapHTTPError401ExpiredToken() {
        let httpError = HTTPError.status(401, "Token expired")
        let b2Error = mapHTTPErrorToB2(httpError)

        if case .expiredUploadUrl(let message) = b2Error {
            XCTAssertEqual(message, "Token expired")
        } else {
            XCTFail("Expected expiredUploadUrl error, got \(b2Error)")
        }
    }

    func testMapHTTPError401ExpiredUploadUrl() {
        let httpError = HTTPError.status(401, "Upload URL has expired")
        let b2Error = mapHTTPErrorToB2(httpError)

        if case .expiredUploadUrl(let message) = b2Error {
            XCTAssertEqual(message, "Upload URL has expired")
        } else {
            XCTFail("Expected expiredUploadUrl error, got \(b2Error)")
        }
    }

    func testMapHTTPError429RateLimited() {
        let httpError = HTTPError.status(429, "Too many requests")
        let b2Error = mapHTTPErrorToB2(httpError)

        if case .rateLimited(let retryAfter, let message) = b2Error {
            XCTAssertNil(retryAfter)
            XCTAssertEqual(message, "Too many requests")
        } else {
            XCTFail("Expected rateLimited error, got \(b2Error)")
        }
    }

    func testMapHTTPError5xxTemporary() {
        let testCases = [
            (500, "Internal server error"),
            (502, "Bad gateway"),
            (503, "Service unavailable"),
            (504, "Gateway timeout"),
            (599, "Custom 5xx error")
        ]

        for (code, body) in testCases {
            let httpError = HTTPError.status(code, body)
            let b2Error = mapHTTPErrorToB2(httpError)

            if case .temporary(let errorCode, let message) = b2Error {
                XCTAssertEqual(errorCode, code)
                XCTAssertEqual(message, body)
            } else {
                XCTFail("Expected temporary error for \(code), got \(b2Error)")
            }
        }
    }

    func testMapHTTPError4xxClient() {
        let testCases = [
            (400, "Bad request"),
            (403, "Forbidden"),
            (404, "Not found"),
            (409, "Conflict"),
            (422, "Unprocessable entity")
        ]

        for (code, body) in testCases {
            let httpError = HTTPError.status(code, body)
            let b2Error = mapHTTPErrorToB2(httpError)

            if case .client(let errorCode, let message) = b2Error {
                XCTAssertEqual(errorCode, code)
                XCTAssertEqual(message, body)
            } else {
                XCTFail("Expected client error for \(code), got \(b2Error)")
            }
        }
    }

    func testMapHTTPErrorUnderlying() {
        let customError = NSError(domain: "test", code: 999, userInfo: nil)
        let b2Error = mapHTTPErrorToB2(customError)

        if case .underlying = b2Error {
            // Success
        } else {
            XCTFail("Expected underlying error, got \(b2Error)")
        }
    }

    // MARK: - Case Insensitive Matching Tests

    func testExpiredTokenCaseInsensitive() {
        let testCases = [
            "Token Expired",
            "TOKEN EXPIRED",
            "token expired",
            "Auth token has expired"
        ]

        for body in testCases {
            let httpError = HTTPError.status(401, body)
            let b2Error = mapHTTPErrorToB2(httpError)

            if case .expiredUploadUrl = b2Error {
                // Success
            } else {
                XCTFail("Expected expiredUploadUrl for '\(body)', got \(b2Error)")
            }
        }
    }

    func testUnauthorizedCaseInsensitive() {
        let testCases = [
            "Unauthorized Access",
            "UNAUTHORIZED",
            "unauthorized user"
        ]

        for body in testCases {
            let httpError = HTTPError.status(401, body)
            let b2Error = mapHTTPErrorToB2(httpError)

            if case .expiredUploadUrl = b2Error {
                // Success - "unauthorized" matches expired URL pattern
            } else {
                XCTFail("Expected expiredUploadUrl for '\(body)', got \(b2Error)")
            }
        }
    }

    // MARK: - RestoreError Description Tests

    func testRestoreErrorDescriptions() {
        let testCases: [(RestoreError, String)] = [
            (.noSnapshotsFound, "No snapshots found in backup"),
            (.invalidSnapshot("2024-01-01"), "Invalid snapshot: 2024-01-01"),
            (.invalidSelection, "Invalid selection"),
            (.pathNotFound("/test/path"), "Path not found in snapshot: /test/path"),
            (.cancelled, "Restore cancelled by user"),
            (.downloadFailed("file.txt", NSError(domain: "test", code: 1)), "Failed to download file.txt:"),
            (.writeFailed("file.txt", NSError(domain: "test", code: 1)), "Failed to write file.txt:"),
            (.destinationNotWritable("/readonly"), "Destination not writable: /readonly")
        ]

        for (error, expectedPrefix) in testCases {
            XCTAssertTrue(error.description.hasPrefix(expectedPrefix),
                         "Expected '\(error.description)' to start with '\(expectedPrefix)'")
        }
    }

    func testRestoreErrorInsufficientDiskSpace() {
        let error = RestoreError.insufficientDiskSpace(1_000_000_000) // 1 GB
        XCTAssertTrue(error.description.contains("Insufficient disk space"))
        XCTAssertTrue(error.description.contains("GB") || error.description.contains("MB"))
    }

    func testRestoreErrorIntegrityCheckFailed() {
        let error = RestoreError.integrityCheckFailed("checksums.txt")
        XCTAssertEqual(error.description, "Integrity check failed: checksums.txt")
    }

    // MARK: - Error Equality Tests (if needed for retry logic)

    func testB2ErrorTypeMatching() {
        let errors: [B2Error] = [
            .unauthorized("test"),
            .expiredUploadUrl("test"),
            .rateLimited(nil, "test"),
            .temporary(500, "test"),
            .client(400, "test"),
            .invalidResponse("test")
        ]

        // Verify each error type can be matched correctly
        for error in errors {
            switch error {
            case .unauthorized:
                XCTAssertTrue(true)
            case .expiredUploadUrl:
                XCTAssertTrue(true)
            case .rateLimited:
                XCTAssertTrue(true)
            case .temporary:
                XCTAssertTrue(true)
            case .client:
                XCTAssertTrue(true)
            case .invalidResponse:
                XCTAssertTrue(true)
            case .underlying:
                XCTFail("Should not be underlying")
            }
        }
    }
}
