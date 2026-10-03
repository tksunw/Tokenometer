import Foundation

/// Token counts for one model call. `thinking` is the reasoning share of `output`, not an extra bucket.
public struct TokenCounts: Codable, Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite: Int
    public var thinking: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, thinking: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.thinking = thinking
    }

    public static let zero = TokenCounts()

    /// Every token the provider counted, cache traffic included.
    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            thinking: lhs.thinking + rhs.thinking
        )
    }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs = lhs + rhs
    }
}

/// One model call as a tool logged it. The unit every parser produces; windows and spend are built from these.
public struct UsageRecord: Codable, Sendable, Equatable, Identifiable {
    /// Stable within a tool: the log's own message or step id, so re-reads dedupe.
    public var id: String
    public var tool: Tool
    public var model: String
    public var timestamp: Date
    public var tokens: TokenCounts
    public var sessionID: String
    /// Leaf of the working directory the session ran in, when the log records one.
    public var project: String?

    public init(id: String, tool: Tool, model: String, timestamp: Date, tokens: TokenCounts, sessionID: String, project: String? = nil) {
        self.id = id
        self.tool = tool
        self.model = model
        self.timestamp = timestamp
        self.tokens = tokens
        self.sessionID = sessionID
        self.project = project
    }

    public var provider: Provider { tool.provider }
}
