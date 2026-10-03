import Foundation

/// Why a value could not be refreshed. Shown next to a stale bar.
public struct StaleInfo: Codable, Sendable, Equatable {
    public var since: Date
    public var reason: String

    public init(since: Date, reason: String) {
        self.since = since
        self.reason = reason
    }
}

/// Everything the menu bar, menu, and widget show for one provider.
public struct ProviderSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var provider: Provider
    public var accountKind: AccountKind
    public var planName: String?
    public var session: UsageWindow?
    public var weekly: UsageWindow?
    public var scoped: [UsageWindow]
    public var sessionSpend: Spend
    public var weeklySpend: Spend
    public var tools: [ToolSpend]
    public var models: [ModelSpend]
    public var windowsStale: StaleInfo?
    public var spendStale: StaleInfo?

    public var id: Provider { provider }

    public init(provider: Provider, accountKind: AccountKind, planName: String? = nil, session: UsageWindow? = nil, weekly: UsageWindow? = nil, scoped: [UsageWindow] = [], sessionSpend: Spend = .zero, weeklySpend: Spend = .zero, tools: [ToolSpend] = [], models: [ModelSpend] = [], windowsStale: StaleInfo? = nil, spendStale: StaleInfo? = nil) {
        self.provider = provider
        self.accountKind = accountKind
        self.planName = planName
        self.session = session
        self.weekly = weekly
        self.scoped = scoped
        self.sessionSpend = sessionSpend
        self.weeklySpend = weeklySpend
        self.tools = tools
        self.models = models
        self.windowsStale = windowsStale
        self.spendStale = spendStale
    }
}

/// The unit handed from the app to the widget through the App Group container.
public struct Snapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var generatedAt: Date
    public var providers: [ProviderSnapshot]

    public init(generatedAt: Date, providers: [ProviderSnapshot]) {
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.providers = providers
    }

    public func provider(_ provider: Provider) -> ProviderSnapshot? {
        providers.first { $0.provider == provider }
    }
}
