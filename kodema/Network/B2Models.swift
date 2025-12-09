import Foundation

// MARK: - B2 API Models

struct B2AuthorizeResponse: Decodable {
    let absoluteMinimumPartSize: Int
    let accountId: String
    let apiUrl: String
    let authorizationToken: String
    let downloadUrl: String
    let recommendedPartSize: Int
}

struct B2Bucket: Decodable {
    let accountId: String
    let bucketId: String
    let bucketName: String
    let bucketType: String
}

struct B2ListBucketsResponse: Decodable {
    let buckets: [B2Bucket]
}

struct B2GetUploadUrlResponse: Decodable {
    let bucketId: String
    let uploadUrl: String
    let authorizationToken: String
}

struct B2StartLargeFileResponse: Decodable {
    let fileId: String
}

struct B2GetUploadPartUrlResponse: Decodable {
    let fileId: String
    let uploadUrl: String
    let authorizationToken: String
}

struct B2FinishLargeFileResponse: Decodable {
    let fileId: String
    let fileName: String
}

struct B2FileInfo: Decodable {
    let fileId: String
    let fileName: String
    let contentLength: Int64
    let uploadTimestamp: Int64?

    enum CodingKeys: String, CodingKey {
        case fileId
        case fileName
        case contentLength
        case uploadTimestamp
    }
}

struct B2ListFileNamesResponse: Decodable {
    let files: [B2FileInfo]
    let nextFileName: String?
}
