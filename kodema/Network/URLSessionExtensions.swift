import Foundation

enum HTTPError: Error, CustomStringConvertible {
    case invalidURL
    case unexpectedResponse(String)
    case status(Int, String)

    var description: String {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .unexpectedResponse(let s): return "Unexpected response: \(s)"
        case .status(let code, let body): return "HTTP \(code): \(body)"
        }
    }
}

extension URLSession {
    func data(for request: URLRequest, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        // Relies on timeouts from session configuration; no additional concurrent wrappers here.
        let (data, response) = try await self.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError.unexpectedResponse("No HTTP response")
        }
        if !(200...299).contains(http.statusCode) {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw HTTPError.status(http.statusCode, text)
        }
        return (data, http)
    }
}
