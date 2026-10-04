import Foundation

/// Minimal injection seam so the Antigravity localhost client can be tested without a server.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    let refusesRedirects: Bool

    public init(session: URLSession = .shared, refusesRedirects: Bool = false) {
        self.session = session
        self.refusesRedirects = refusesRedirects
    }

    /// For calls to 127.0.0.1: no system proxy, and redirects come back as the 3xx response instead of
    /// being followed, so a local listener cannot send the request, CSRF header included, off the machine.
    public static let loopback: URLSessionTransport = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSessionTransport(session: URLSession(configuration: configuration), refusesRedirects: true)
    }()

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request, delegate: refusesRedirects ? RefuseRedirects() : nil)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.badResponse }
        return (data, http)
    }
}

private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
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
