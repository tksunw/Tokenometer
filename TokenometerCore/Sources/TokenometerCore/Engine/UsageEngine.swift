import Foundation

/// Per-provider visibility override from settings.
public enum ProviderVisibility: String, Codable, Sendable {
    case automatic
    case show
    case hide
}

public struct EngineSettings: Sendable, Equatable {
    public var visibility: [Provider: ProviderVisibility]
    public var accountOverrides: [Provider: AccountKind]
    public var budgets: [Provider: Budget]

    public init(visibility: [Provider: ProviderVisibility] = [:], accountOverrides: [Provider: AccountKind] = [:], budgets: [Provider: Budget] = [:]) {
        self.visibility = visibility
        self.accountOverrides = accountOverrides
        self.budgets = budgets
    }
}

/// Dollar budget per window for a metered account, so spend can be shown as a percent.
public struct Budget: Codable, Sendable, Equatable {
    public var sessionUSD: Double?
    public var weeklyUSD: Double?

    public init(sessionUSD: Double? = nil, weeklyUSD: Double? = nil) {
        self.sessionUSD = sessionUSD
        self.weeklyUSD = weeklyUSD
    }
}

/// Everything one refresh gathered, before it is shaped into a Snapshot. Kept as a value so the
/// shaping step is a pure function and the tests can feed it directly.
public struct RefreshInputs: Sendable {
    public var records: [UsageRecord]
    public var presentTools: Set<Tool>
    public var collectorFailures: [Tool: Int]
    public var codexRateLimits: CodexRateLimits?
    public var windows: [Provider: Result<ProviderWindows, any Error>]
    public var accounts: [Provider: AccountInfo]
    public var now: Date

    public init(records: [UsageRecord], presentTools: Set<Tool>, collectorFailures: [Tool: Int] = [:], codexRateLimits: CodexRateLimits? = nil, windows: [Provider: Result<ProviderWindows, any Error>] = [:], accounts: [Provider: AccountInfo] = [:], now: Date) {
        self.records = records
        self.presentTools = presentTools
        self.collectorFailures = collectorFailures
        self.codexRateLimits = codexRateLimits
        self.windows = windows
        self.accounts = accounts
        self.now = now
    }
}

public enum UsageEngine {
    /// Shapes one refresh into the snapshot the UI shows. `previous` supplies values to keep when a
    /// source failed this time, so a bar goes stale rather than blank.
    public static func snapshot(from inputs: RefreshInputs, settings: EngineSettings, previous: Snapshot?) -> Snapshot {
        var providers: [ProviderSnapshot] = []

        for provider in Provider.allCases {
            let tools = Tool.allCases.filter { $0.provider == provider }
            let present = tools.contains { inputs.presentTools.contains($0) }
            switch settings.visibility[provider] ?? .automatic {
            case .hide: continue
            case .automatic where !present: continue
            default: break
            }

            let old = previous?.provider(provider)
            var account = inputs.accounts[provider] ?? AccountInfo(kind: .plan)
            if let override = settings.accountOverrides[provider] { account.kind = override }

            // Windows: Codex from logs, others from their usage endpoint, else carried over as stale.
            var session: UsageWindow?
            var weekly: UsageWindow?
            var scoped: [UsageWindow] = []
            var surfaces: [SurfaceShare]?
            var grants: [CreditGrant]?
            var windowsStale: StaleInfo?
            if provider == .openAI, let limits = inputs.codexRateLimits {
                session = limits.session
                weekly = limits.weekly
                if account.planName == nil { account.planName = limits.planType }
            } else {
                switch inputs.windows[provider] {
                case .success(let fetched)?:
                    session = fetched.session
                    weekly = fetched.weekly
                    scoped = fetched.scoped
                    surfaces = fetched.surfaces.isEmpty ? nil : fetched.surfaces
                    grants = fetched.grants.isEmpty ? nil : fetched.grants
                    if let plan = fetched.planName { account.planName = plan }
                    // A source that reports from a file can fall behind the logs: say so rather than
                    // show an old number as current.
                    if let newest = inputs.records.lazy.filter({ $0.provider == provider }).map(\.timestamp).max(),
                       newest.timeIntervalSince(fetched.fetchedAt) > Self.reportLag {
                        windowsStale = StaleInfo(since: fetched.fetchedAt, reason: "Logs are newer than the last usage report; check the usage-reporter mod is loaded in Claude Code")
                    }
                case .failure(let error)?:
                    session = old?.session
                    weekly = old?.weekly
                    scoped = old?.scoped ?? []
                    surfaces = old?.surfaces
                    grants = old?.grants
                    windowsStale = StaleInfo(since: old?.windowsStale?.since ?? inputs.now, reason: describe(error))
                case nil:
                    session = old?.session
                    weekly = old?.weekly
                    scoped = old?.scoped ?? []
                    surfaces = old?.surfaces
                    grants = old?.grants
                    windowsStale = old?.windowsStale
                }
            }
            // Metered accounts have no provider windows; budgets stand in for them after spend is known.
            if account.kind == .metered {
                session = nil
                weekly = nil
                scoped = []
                surfaces = nil
                grants = nil
            }

            // A window whose reset time has passed rolled over; the provider will report the new one
            // on its next call. Until then show it empty rather than "resetting" forever.
            session = Self.expireIfPast(session, now: inputs.now)
            weekly = Self.expireIfPast(weekly, now: inputs.now)
            scoped = scoped.map { Self.expireIfPast($0, now: inputs.now) ?? $0 }

            let records = inputs.records.filter { $0.provider == provider }
            let bounds = UsageAggregator.Bounds(session: session, weekly: weekly, now: inputs.now)
            let usage = UsageAggregator.aggregate(records, bounds: bounds)

            if account.kind == .metered {
                let budget = settings.budgets[provider]
                session = budgetWindow(.session, spendUSD: usage.sessionSpend.costUSD, budget: budget?.sessionUSD, now: inputs.now, length: UsageAggregator.defaultSessionLength)
                weekly = budgetWindow(.weekly, spendUSD: usage.weeklySpend.costUSD, budget: budget?.weeklyUSD, now: inputs.now, length: UsageAggregator.defaultWeeklyLength)
                windowsStale = nil
            }

            var spendStale: StaleInfo?
            let failures = tools.reduce(0) { $0 + (inputs.collectorFailures[$1] ?? 0) }
            if failures > 0 {
                spendStale = StaleInfo(since: old?.spendStale?.since ?? inputs.now, reason: "\(failures) log file(s) could not be read")
            }

            providers.append(ProviderSnapshot(
                provider: provider,
                accountKind: account.kind,
                planName: account.planName,
                session: session,
                weekly: weekly,
                scoped: scoped,
                sessionSpend: usage.sessionSpend,
                weeklySpend: usage.weeklySpend,
                tools: usage.tools,
                models: usage.models,
                windowsStale: windowsStale,
                spendStale: spendStale,
                surfaces: surfaces,
                grants: grants
            ))
        }

        return Snapshot(generatedAt: inputs.now, providers: providers)
    }

    static func expireIfPast(_ window: UsageWindow?, now: Date) -> UsageWindow? {
        guard var window, let resets = window.resetsAt, resets <= now else { return window }
        window.usedPercent = 0
        window.resetsAt = nil
        return window
    }

    private static func budgetWindow(_ kind: WindowKind, spendUSD: Double?, budget: Double?, now: Date = .now, length: TimeInterval = 0) -> UsageWindow? {
        guard let spendUSD, let budget, budget > 0 else { return nil }
        return UsageWindow(kind: kind, usedPercent: min(100, spendUSD / budget * 100), resetsAt: nil, length: length)
    }

    /// How far the logs may run ahead of a usage report before the windows count as stale. The
    /// usage-reporter mod writes after every turn, so a gap this long means it is not running.
    static let reportLag: TimeInterval = 15 * 60

    private static func describe(_ error: any Error) -> String {
        if let described = error as? LocalizedError, let text = described.errorDescription { return text }
        return String(describing: error)
    }
}

/// Runs the collectors and window sources and hands the result to `UsageEngine.snapshot`.
public actor UsageRefresher {
    private let collectors: [any UsageCollector]
    private let windowSources: [Provider: any UsageWindowSource]
    private let locations: LogLocations
    private var previous: Snapshot?
    /// `~/.claude.json` runs to megabytes and is rewritten often; it is parsed again only when its
    /// size or mtime changes.
    private var claudeAccount: (stamp: FileStamp?, info: AccountInfo)?

    public init(collectors: [any UsageCollector], windowSources: [any UsageWindowSource], locations: LogLocations = .standard, previous: Snapshot? = nil) {
        self.collectors = collectors
        self.windowSources = Dictionary(uniqueKeysWithValues: windowSources.map { ($0.provider, $0) })
        self.locations = locations
        self.previous = previous
    }

    public func refresh(settings: EngineSettings, fetchWindows: Bool, now: Date = .now) async -> Snapshot {
        var records: [UsageRecord] = []
        var present: Set<Tool> = []
        var failures: [Tool: Int] = [:]
        var codexLimits: CodexRateLimits?

        let since = now.addingTimeInterval(-UsageAggregator.defaultWeeklyLength - 3600)
        for collector in collectors where collector.isPresent() {
            present.insert(collector.tool)
            let result = collector.collect(modifiedAfter: since)
            records += result.records
            if !result.failures.isEmpty { failures[collector.tool] = result.failures.count }
            if let limits = result.codexRateLimits { codexLimits = limits }
        }

        var windows: [Provider: Result<ProviderWindows, any Error>] = [:]
        await withTaskGroup(of: (Provider, Result<ProviderWindows, any Error>).self) { group in
            // A provider switched off in Settings is never asked; its login stays untouched.
            // `fetchWindows` paces the network sources; a source that reads a local file runs every time.
            for (provider, source) in windowSources
            where (fetchWindows || source.readsLocalFile) && settings.visibility[provider] != .hide && present.contains(where: { $0.provider == provider }) {
                group.addTask {
                    do { return (provider, .success(try await source.fetchWindows())) }
                    catch { return (provider, .failure(error)) }
                }
            }
            for await (provider, result) in group { windows[provider] = result }
        }

        let accounts: [Provider: AccountInfo] = [
            .anthropic: claudeAccountInfo(),
            .openAI: AccountDetector.codex(rateLimits: codexLimits),
            .google: AccountDetector.gemini(geminiHome: locations.geminiHome),
        ]

        let inputs = RefreshInputs(records: records, presentTools: present, collectorFailures: failures,
                                   codexRateLimits: codexLimits, windows: windows, accounts: accounts, now: now)
        let snapshot = UsageEngine.snapshot(from: inputs, settings: settings, previous: previous)
        previous = snapshot
        return snapshot
    }

    private func claudeAccountInfo() -> AccountInfo {
        let stamp = FileStamp(of: locations.claudeConfig)
        if let cached = claudeAccount, cached.stamp == stamp { return cached.info }
        let info = AccountDetector.claude(configURL: locations.claudeConfig)
        claudeAccount = (stamp, info)
        return info
    }
}
