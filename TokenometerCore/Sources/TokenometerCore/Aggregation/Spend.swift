import Foundation

/// Tokens and API-equivalent cost over some set of records. `hasUnknownCost` means at least one
/// model had no rate, so `costUSD` is a floor and the UI should mark it.
public struct Spend: Codable, Sendable, Equatable {
    public var tokens: TokenCounts
    public var costUSD: Double
    public var hasUnknownCost: Bool
    public var calls: Int

    public init(tokens: TokenCounts = .zero, costUSD: Double = 0, hasUnknownCost: Bool = false, calls: Int = 0) {
        self.tokens = tokens
        self.costUSD = costUSD
        self.hasUnknownCost = hasUnknownCost
        self.calls = calls
    }

    public static let zero = Spend()

    public mutating func add(_ record: UsageRecord) {
        tokens += record.tokens
        calls += 1
        if let cost = Pricing.cost(for: record.model, tokens: record.tokens) {
            costUSD += cost
        } else {
            hasUnknownCost = true
        }
    }

    public static func of<S: Sequence>(_ records: S) -> Spend where S.Element == UsageRecord {
        var spend = Spend()
        for record in records { spend.add(record) }
        return spend
    }
}

public struct ToolSpend: Codable, Sendable, Equatable, Identifiable {
    public var tool: Tool
    public var session: Spend
    public var weekly: Spend

    public init(tool: Tool, session: Spend, weekly: Spend) {
        self.tool = tool
        self.session = session
        self.weekly = weekly
    }

    public var id: Tool { tool }
}

public struct ModelSpend: Codable, Sendable, Equatable, Identifiable {
    public var model: String
    public var weekly: Spend

    public init(model: String, weekly: Spend) {
        self.model = model
        self.weekly = weekly
    }

    public var id: String { model }
}
