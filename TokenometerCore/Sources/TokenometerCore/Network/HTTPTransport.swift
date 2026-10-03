import Foundation

/// Minimal injection seam so the Antigravity localhost client can be tested without a server.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.badResponse }
        return (data, http)
    }
}

public enum UsageClientError: Error, LocalizedError, Equatable {
    case noCredentials(String)
    case badResponse
    case http(Int)
    case noReport(String)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .noCredentials(let what): "No credentials: \(what)"
        case .badResponse: "Unexpected response"
        case .http(let code): "HTTP \(code) from usage endpoint"
        case .noReport(let why): why
        case .malformed(let what): "Could not read \(what)"
        }
    }
}
