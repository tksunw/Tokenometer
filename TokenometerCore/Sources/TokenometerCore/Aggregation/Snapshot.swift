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

/// One surface's part of the provider's weekly usage, account-wide, as the provider reports it
/// (for Claude: Claude Code, Chats, Cowork, Other). Unlike the tool and model rows, which are
/// summed from this Mac's logs, it covers every device and claude.ai chat too.
public struct SurfaceShare: Codable, Sendable, Equatable {
    public var key: String
    public var label: String
    public var percent: Double

    public init(key: String, label: String, percent: Double) {
        self.key = key
        self.label = label
        self.percent = percent
    }
}

/// One dollar credit or grant on the account, as the provider reports it (for Claude: extra usage,
/// cloud sessions, the Projects setup credit, and any grant added later). The list is passed through
/// whole, so a new kind appears without a release here.
public struct CreditGrant: Codable, Sendable, Equatable {
    public enum Ends: String, Codable, Sendable { case reset, expiry }

    /// Stable source key, for example `extra_usage` or a provider codename.
    public var id: String
    public var label: String
    public var used: Double
    /// Nil when there is no limit, or none was reported.
    public var limit: Double?
    public var currency: String
    public var endsAt: Date?
    /// Whether `endsAt` is a reset or an expiry; nil when the provider's meaning is not known.
    public var ends: Ends?

    public init(id: String, label: String, used: Double, limit: Double? = nil, currency: String = "USD", endsAt: Date? = nil, ends: Ends? = nil) {
        self.id = id
        self.label = label
        self.used = used
        self.limit = limit
        self.currency = currency
        self.endsAt = endsAt
        self.ends = ends
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
    /// Optional so a snapshot written before this field existed still decodes.
    public var surfaces: [SurfaceShare]?
    /// Optional for the same reason.
    public var grants: [CreditGrant]?

    public var id: Provider { provider }

    public init(provider: Provider, accountKind: AccountKind, planName: String? = nil, session: UsageWindow? = nil, weekly: UsageWindow? = nil, scoped: [UsageWindow] = [], sessionSpend: Spend = .zero, weeklySpend: Spend = .zero, tools: [ToolSpend] = [], models: [ModelSpend] = [], windowsStale: StaleInfo? = nil, spendStale: StaleInfo? = nil, surfaces: [SurfaceShare]? = nil, grants: [CreditGrant]? = nil) {
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
        self.surfaces = surfaces
        self.grants = grants
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

    /// Equal apart from `generatedAt`: nothing the menu or widget draws differs except the "as of"
    /// time, so the widget need not be reloaded.
    public func hasSameContent(as other: Snapshot?) -> Bool {
        guard let other else { return false }
        return version == other.version && providers == other.providers
    }
}
