import Foundation

/// Usage windows as a provider reports them, fetched from its usage endpoint (ADR-0001).
public struct ProviderWindows: Sendable, Equatable {
    public var session: UsageWindow?
    public var weekly: UsageWindow?
    /// Extra weekly windows scoped to a model family, labeled.
    public var scoped: [UsageWindow]
    public var planName: String?
    public var fetchedAt: Date
    /// The weekly window split by surface, when the provider reports one.
    public var surfaces: [SurfaceShare] = []

    public init(session: UsageWindow? = nil, weekly: UsageWindow? = nil, scoped: [UsageWindow] = [], planName: String? = nil, fetchedAt: Date) {
        self.session = session
        self.weekly = weekly
        self.scoped = scoped
        self.planName = planName
        self.fetchedAt = fetchedAt
    }
}

public protocol UsageWindowSource: Sendable {
    var provider: Provider { get }
    func fetchWindows() async throws -> ProviderWindows
    /// True when a fetch is a file read: no rate limit to respect, so it runs on every refresh.
    var readsLocalFile: Bool { get }
}

public extension UsageWindowSource {
    var readsLocalFile: Bool { false }
}
