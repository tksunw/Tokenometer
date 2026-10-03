import Foundation

/// Folds usage records into per-window spend. Window bounds come from the provider's reported
/// reset time and length when known, else a rolling 5 hours and 7 days ending now.
public enum UsageAggregator {
    public static let defaultSessionLength: TimeInterval = 5 * 3600
    public static let defaultWeeklyLength: TimeInterval = 7 * 86400

    public struct Bounds: Sendable, Equatable {
        public var sessionStart: Date
        public var weeklyStart: Date
        public var end: Date

        public init(session: UsageWindow?, weekly: UsageWindow?, now: Date) {
            end = now
            sessionStart = session?.startsAt ?? now.addingTimeInterval(-defaultSessionLength)
            weeklyStart = weekly?.startsAt ?? now.addingTimeInterval(-defaultWeeklyLength)
            // A reported window that has already reset contributes no bound.
            if let resets = session?.resetsAt, resets < now { sessionStart = now.addingTimeInterval(-defaultSessionLength) }
            if let resets = weekly?.resetsAt, resets < now { weeklyStart = now.addingTimeInterval(-defaultWeeklyLength) }
        }
    }

    public struct Result: Sendable, Equatable {
        public var sessionSpend: Spend
        public var weeklySpend: Spend
        public var tools: [ToolSpend]
        public var models: [ModelSpend]
    }

    public static func aggregate(_ records: [UsageRecord], bounds: Bounds) -> Result {
        var session = Spend()
        var weekly = Spend()
        var byTool: [Tool: ToolSpend] = [:]
        var byModel: [String: ModelSpend] = [:]

        for record in records where record.timestamp >= bounds.weeklyStart && record.timestamp <= bounds.end {
            weekly.add(record)
            byTool[record.tool, default: ToolSpend(tool: record.tool, session: .zero, weekly: .zero)].weekly.add(record)
            byModel[record.model, default: ModelSpend(model: record.model, weekly: .zero)].weekly.add(record)
            if record.timestamp >= bounds.sessionStart {
                session.add(record)
                byTool[record.tool]!.session.add(record)
            }
        }

        return Result(
            sessionSpend: session,
            weeklySpend: weekly,
            tools: byTool.values.sorted { $0.weekly.tokens.total > $1.weekly.tokens.total },
            models: byModel.values.sorted { $0.weekly.tokens.total > $1.weekly.tokens.total }
        )
    }
}
