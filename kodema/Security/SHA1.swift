import Foundation
import CommonCrypto

func sha1HexStream(fileURL: URL, bufferSize: Int = 8 * 1024 * 1024) throws -> String {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var ctx = CC_SHA1_CTX()
    CC_SHA1_Init(&ctx)
    while true {
        let data = try handle.read(upToCount: bufferSize) ?? Data()
        if !data.isEmpty {
            data.withUnsafeBytes { buf in
                _ = CC_SHA1_Update(&ctx, buf.baseAddress, CC_LONG(data.count))
            }
        } else {
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1_Final(&digest, &ctx)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }
}
