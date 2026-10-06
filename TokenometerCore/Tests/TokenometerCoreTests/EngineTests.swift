import Foundation
import Testing
@testable import TokenometerCore

@Suite struct UsageEngineTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(_ tool: Tool, minutesAgo: Double) -> UsageRecord {
        UsageRecord(id: UUID().uuidString, tool: tool, model: "claude-haiku-4-5", timestamp: now.addingTimeInterval(-minutesAgo * 60),
                    tokens: TokenCounts(input: 1_000_000), sessionID: "s")
    }

    @Test func absentProvidersVanishUnlessForced() {
        let inputs = RefreshInputs(records: [], presentTools: [.claudeCode], now: now)
        let auto = UsageEngine.snapshot(from: inputs, settings: EngineSettings(), previous: nil)
        #expect(auto.providers.map(\.provider) == [.anthropic])

        let forced = UsageEngine.snapshot(from: inputs, settings: EngineSettings(visibility: [.google: .show, .anthropic: .hide]), previous: nil)
        #expect(forced.providers.map(\.provider) == [.google])
    }

    @Test func codexWindowsComeFromLogs() {
        let limits = CodexRateLimits(session: UsageWindow(kind: .session, usedPercent: 33, resetsAt: now.addingTimeInterval(3600), length: 18000),
                                     weekly: UsageWindow(kind: .weekly, usedPercent: 7), planType: "team", limitID: "codex", observedAt: now)
        let inputs = RefreshInputs(records: [record(.codex, minutesAgo: 5)], presentTools: [.codex], codexRateLimits: limits,
                                   accounts: [.openAI: AccountDetector.codex(rateLimits: limits)], now: now)
        let snapshot = UsageEngine.snapshot(from: inputs, settings: EngineSettings(), previous: nil)
        let openAI = snapshot.provider(.openAI)!
        #expect(openAI.session?.usedPercent == 33)
        #expect(openAI.planName == "team")
        #expect(openAI.accountKind == .plan)
        #expect(openAI.sessionSpend.calls == 1)
    }

    @Test func reportOlderThanTheLogsIsStale() {
        func snapshot(reportedMinutesAgo: Double) -> ProviderSnapshot? {
            let fetched = ProviderWindows(session: UsageWindow(kind: .session, usedPercent: 50), fetchedAt: now.addingTimeInterval(-reportedMinutesAgo * 60))
            return UsageEngine.snapshot(
                from: RefreshInputs(records: [record(.claudeCode, minutesAgo: 1)], presentTools: [.claudeCode], windows: [.anthropic: .success(fetched)],
                                    accounts: [.anthropic: AccountInfo(kind: .plan)], now: now),
                settings: EngineSettings(), previous: nil).provider(.anthropic)
        }
        #expect(snapshot(reportedMinutesAgo: 6)?.windowsStale == nil)
        let lagging = snapshot(reportedMinutesAgo: 30)
        #expect(lagging?.session?.usedPercent == 50)
        #expect(lagging?.windowsStale?.since == now.addingTimeInterval(-30 * 60))
    }

    @Test func failedWindowFetchKeepsPreviousValueAsStale() {
        struct Boom: Error {}
        var fetched = ProviderWindows(session: UsageWindow(kind: .session, usedPercent: 50), weekly: UsageWindow(kind: .weekly, usedPercent: 20), planName: "max", fetchedAt: now)
        fetched.surfaces = [SurfaceShare(key: "chat", label: "Chats", percent: 12)]
        fetched.grants = [CreditGrant(id: "extra_usage", label: "Extra usage", used: 4, limit: 100)]
        let first = UsageEngine.snapshot(
            from: RefreshInputs(records: [], presentTools: [.claudeCode], windows: [.anthropic: .success(fetched)], accounts: [.anthropic: AccountInfo(kind: .plan)], now: now),
            settings: EngineSettings(), previous: nil)
        #expect(first.provider(.anthropic)?.session?.usedPercent == 50)
        #expect(first.provider(.anthropic)?.windowsStale == nil)

        let later = now.addingTimeInterval(600)
        let second = UsageEngine.snapshot(
            from: RefreshInputs(records: [], presentTools: [.claudeCode], windows: [.anthropic: .failure(Boom())], accounts: [.anthropic: AccountInfo(kind: .plan)], now: later),
            settings: EngineSettings(), previous: first)
        let anthropic = second.provider(.anthropic)!
        #expect(anthropic.session?.usedPercent == 50)
        #expect(anthropic.surfaces == fetched.surfaces)
        #expect(anthropic.grants == fetched.grants)
        #expect(anthropic.windowsStale?.since == later)
        #expect(anthropic.windowsStale?.reason.contains("Boom") == true)
    }

    @Test func enterpriseSpendLimitIsTheBudget() {
        // usage-reporter 0.5.2 on an Enterprise login: no windows, a monthly spend limit as the extra usage grant.
        var fetched = ProviderWindows(fetchedAt: now)
        fetched.grants = [CreditGrant(id: "extra_usage", label: "Extra usage", used: 200, limit: 800)]
        func snapshot(budget: Double?) -> ProviderSnapshot? {
            var settings = EngineSettings()
            settings.budgets[.anthropic] = Budget(sessionUSD: budget)
            return UsageEngine.snapshot(
                from: RefreshInputs(records: [record(.claudeCode, minutesAgo: 1)], presentTools: [.claudeCode], windows: [.anthropic: .success(fetched)],
                                    accounts: [.anthropic: AccountInfo(kind: .metered, planName: "Enterprise")], now: now),
                settings: settings, previous: nil).provider(.anthropic)
        }
        // The provider's limit wins over a budget typed into Settings, and the grant stays for its dollars.
        for anthropic in [snapshot(budget: nil), snapshot(budget: 0.5)] {
            #expect(anthropic?.session?.usedPercent == 25)
            #expect(anthropic?.session?.label == "Monthly budget")
            #expect(anthropic?.grants == [CreditGrant(id: "extra_usage", label: "Monthly budget", used: 200, limit: 800)])
        }
    }

    @Test func meteredAccountsShowBudgetPercentOrNothing() {
        // 1M input tokens of Haiku 4.5 = $1.00
        let inputs = RefreshInputs(records: [record(.claudeCode, minutesAgo: 1)], presentTools: [.claudeCode],
                                   accounts: [.anthropic: AccountInfo(kind: .metered)], now: now)
        let noBudget = UsageEngine.snapshot(from: inputs, settings: EngineSettings(), previous: nil)
        #expect(noBudget.provider(.anthropic)?.session == nil)
        #expect(noBudget.provider(.anthropic)?.sessionSpend.costUSD == 1.0)

        let budgeted = UsageEngine.snapshot(from: inputs, settings: EngineSettings(budgets: [.anthropic: Budget(sessionUSD: 4, weeklyUSD: 10)]), previous: nil)
        #expect(budgeted.provider(.anthropic)?.session?.usedPercent == 25)
        #expect(budgeted.provider(.anthropic)?.weekly?.usedPercent == 10)
    }

    @Test func expiredWindowsReadAsFresh() {
        let limits = CodexRateLimits(session: UsageWindow(kind: .session, usedPercent: 45, resetsAt: now.addingTimeInterval(-600), length: 18000),
                                     weekly: UsageWindow(kind: .weekly, usedPercent: 8, resetsAt: now.addingTimeInterval(86400), length: 604800), planType: "team", limitID: "codex", observedAt: now)
        let inputs = RefreshInputs(records: [], presentTools: [.codex], codexRateLimits: limits, now: now)
        let openAI = UsageEngine.snapshot(from: inputs, settings: EngineSettings(), previous: nil).provider(.openAI)!
        #expect(openAI.session?.usedPercent == 0)
        #expect(openAI.session?.resetsAt == nil)
        #expect(openAI.weekly?.usedPercent == 8)
    }

    @Test func collectorFailuresMarkSpendStale() {
        let inputs = RefreshInputs(records: [], presentTools: [.geminiCLI], collectorFailures: [.geminiCLI: 2], now: now)
        let snapshot = UsageEngine.snapshot(from: inputs, settings: EngineSettings(), previous: nil)
        #expect(snapshot.provider(.google)?.spendStale?.reason.hasPrefix("2 log file") == true)
    }
}

@Suite struct AccountDetectorTests {
    @Test func claudeLoginIsPlanAndApiKeyIsMetered() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = dir.appendingPathComponent(".claude.json")
        try #"{"oauthAccount":{"emailAddress":"x","organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#.write(to: config, atomically: true, encoding: .utf8)
        #expect(AccountDetector.claude(configURL: config, environment: [:]) == AccountInfo(kind: .plan, planName: "Max 5x"))
        #expect(AccountDetector.claudePlanName(subscription: "pro", tier: nil) == "Pro")
        #expect(AccountDetector.claudePlanName(subscription: "max", tier: "default_claude_max") == "Max")
        #expect(AccountDetector.claude(configURL: config, environment: ["ANTHROPIC_API_KEY": "sk"]).kind == .metered)
        #expect(AccountDetector.claude(configURL: dir.appendingPathComponent("missing.json"), environment: [:]).kind == .metered)
    }

    @Test func geminiAuthTypeDecides() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try #"{"security":{"auth":{"selectedType":"gemini-api-key"}}}"#.write(to: home.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        #expect(AccountDetector.gemini(geminiHome: home).kind == .metered)
    }

    @Test func localFileSourceIsReadEvenWhenNetworkSourcesArePaced() async {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? #"{"oauthAccount":{"organizationType":"claude_max"}}"#.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        let refresher = UsageRefresher(collectors: [PresentCollector(tool: .claudeCode)], windowSources: [LocalSource()], locations: LogLocations(home: home))
        let snapshot = await refresher.refresh(settings: EngineSettings(), fetchWindows: false)
        #expect(snapshot.provider(.anthropic)?.session?.usedPercent == 42)
    }

    @Test func hiddenProviderIsNotFetched() async {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let refresher = UsageRefresher(collectors: [PresentCollector(tool: .claudeCode)], windowSources: [TrippingSource(provider: .anthropic)],
                                       locations: LogLocations(home: home))
        _ = await refresher.refresh(settings: EngineSettings(visibility: [.anthropic: .hide]), fetchWindows: true)
    }
}

private struct LocalSource: UsageWindowSource {
    let provider: Provider = .anthropic
    let readsLocalFile = true
    func fetchWindows() async throws -> ProviderWindows { ProviderWindows(session: UsageWindow(kind: .session, usedPercent: 42), fetchedAt: .now) }
}

private struct PresentCollector: UsageCollector {
    let tool: Tool
    func isPresent() -> Bool { true }
    func collect(modifiedAfter since: Date?) -> CollectorResult { CollectorResult() }
}

private struct TrippingSource: UsageWindowSource {
    let provider: Provider
    func fetchWindows() async throws -> ProviderWindows {
        Issue.record("usage endpoint called for a hidden provider")
        throw UsageClientError.badResponse
    }
}

@Suite struct ClaudeAccountCacheTests {
    private func home(config: String, modified: Date) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let url = home.appendingPathComponent(".claude.json")
        try config.write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return home
    }

    private let max5x = #"{"oauthAccount":{"organizationType":"claude_max","organizationRateLimitTier":"default_claude_max_5x"}}"#

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?.isEmpty != false))
    func unchangedConfigIsNotParsedAgain() async throws {
        let modified = Date(timeIntervalSince1970: 1_790_000_000)
        let home = try home(config: max5x, modified: modified)
        defer { try? FileManager.default.removeItem(at: home) }
        let refresher = UsageRefresher(collectors: [PresentCollector(tool: .claudeCode)], windowSources: [], locations: LogLocations(home: home))
        #expect(await refresher.refresh(settings: EngineSettings(), fetchWindows: false).provider(.anthropic)?.planName == "Max 5x")

        // Same size and mtime, different bytes: only a cache hit still reports the plan.
        let url = home.appendingPathComponent(".claude.json")
        try String(repeating: " ", count: max5x.utf8.count).write(to: url, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        #expect(await refresher.refresh(settings: EngineSettings(), fetchWindows: false).provider(.anthropic)?.planName == "Max 5x")

        // A real change is picked up.
        try #"{"oauthAccount":{"organizationType":"claude_enterprise"}}"#.write(to: url, atomically: false, encoding: .utf8)
        let after = await refresher.refresh(settings: EngineSettings(), fetchWindows: false).provider(.anthropic)
        #expect(after?.accountKind == .metered)
        #expect(after?.planName == "Enterprise")
    }
}

@Suite struct SnapshotContentTests {
    @Test func generatedAtAloneIsNotAChange() {
        let provider = ProviderSnapshot(provider: .anthropic, accountKind: .plan, planName: "Max",
                                        session: UsageWindow(kind: .session, usedPercent: 10), weekly: nil, scoped: [],
                                        sessionSpend: Spend(), weeklySpend: Spend(), tools: [], models: [])
        let first = Snapshot(generatedAt: Date(timeIntervalSince1970: 1_790_000_000), providers: [provider])
        var later = first
        later.generatedAt = first.generatedAt.addingTimeInterval(60)
        #expect(later.hasSameContent(as: first))
        #expect(!later.hasSameContent(as: nil))

        later.providers[0].session?.usedPercent = 11
        #expect(!later.hasSameContent(as: first))
    }
}
