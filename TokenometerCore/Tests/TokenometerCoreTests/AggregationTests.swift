import Foundation
import Testing
@testable import TokenometerCore

private func record(_ tool: Tool, model: String, minutesAgo: Double, now: Date, input: Int = 1000, output: Int = 100) -> UsageRecord {
    UsageRecord(id: UUID().uuidString, tool: tool, model: model, timestamp: now.addingTimeInterval(-minutesAgo * 60),
                tokens: TokenCounts(input: input, output: output), sessionID: "s")
}

@Suite struct PricingTests {
    @Test func longestPrefixWins() {
        #expect(Pricing.rate(for: "claude-opus-5-5")?.input == 4)
        #expect(Pricing.rate(for: "claude-opus-5")?.input == 5)
        #expect(Pricing.rate(for: "claude-haiku-4-5-20251001")?.input == 1)
        #expect(Pricing.rate(for: "gpt-5.4-codex")?.input == 2.5)
        #expect(Pricing.rate(for: "gpt-6-astra")?.output == 50)
        #expect(Pricing.rate(for: "gpt-6-luna")?.input == 0.10)
        #expect(Pricing.rate(for: "gpt-6-sol")?.output == 10)
        #expect(Pricing.rate(for: "gemini-3.8-flash") == nil)
    }

    @Test func costUsesAllFourBuckets() throws {
        let tokens = TokenCounts(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite: 1_000_000)
        let cost = try #require(Pricing.cost(for: "claude-haiku-4-5", tokens: tokens))
        #expect(abs(cost - 7.35) < 1e-9)
    }
}

@Suite struct UsageAggregatorTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func rollingWindowsWhenProviderReportsNone() {
        let records = [
            record(.claudeCode, model: "claude-haiku-4-5", minutesAgo: 10, now: now),
            record(.claudeDesktop, model: "claude-haiku-4-5", minutesAgo: 6 * 60, now: now),
            record(.claudeCode, model: "claude-haiku-4-5", minutesAgo: 8 * 24 * 60, now: now),
        ]
        let result = UsageAggregator.aggregate(records, bounds: .init(session: nil, weekly: nil, now: now))
        #expect(result.sessionSpend.calls == 1)
        #expect(result.weeklySpend.calls == 2)
        #expect(result.tools.count == 2)
        #expect(result.sessionSpend.hasUnknownCost == false)
    }

    @Test func providerWindowAnchorsSessionStart() {
        // Session window resets in 1 hour and is 5 hours long, so it started 4 hours ago.
        let session = UsageWindow(kind: .session, usedPercent: 40, resetsAt: now.addingTimeInterval(3600), length: 5 * 3600)
        let records = [
            record(.codex, model: "gpt-5.4", minutesAgo: 3 * 60, now: now),
            record(.codex, model: "gpt-5.4", minutesAgo: 4.5 * 60, now: now),
        ]
        let result = UsageAggregator.aggregate(records, bounds: .init(session: session, weekly: nil, now: now))
        #expect(result.sessionSpend.calls == 1)
        #expect(result.weeklySpend.calls == 2)
    }

    @Test func unknownModelFlagsCost() {
        let records = [record(.geminiCLI, model: "gemini-3.8-flash", minutesAgo: 1, now: now)]
        let result = UsageAggregator.aggregate(records, bounds: .init(session: nil, weekly: nil, now: now))
        #expect(result.weeklySpend.hasUnknownCost)
        #expect(result.weeklySpend.costUSD == 0)
        #expect(result.weeklySpend.tokens.total == 1100)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let snapshot = Snapshot(generatedAt: now, providers: [
            ProviderSnapshot(provider: .openAI, accountKind: .plan, planName: "team",
                             session: UsageWindow(kind: .session, usedPercent: 12, resetsAt: now, length: 18000),
                             sessionSpend: Spend(tokens: TokenCounts(input: 5), costUSD: 0.01, calls: 1)),
        ])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(decoded == snapshot)
    }
}

@Suite struct CollectorTests {
    @Test func collectorsReadFixtureTrees() throws {
        let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        var locations = LogLocations(home: fixtures)
        locations.claudeCodeProjects = fixtures.appendingPathComponent("claude-code")
        locations.codexSessions = fixtures.appendingPathComponent("codex")
        locations.geminiTemp = fixtures.appendingPathComponent("gemini-cli/tmp")
        locations.antigravityConversations = fixtures.appendingPathComponent("antigravity")

        let claude = ClaudeCodeCollector(locations: locations).collect(modifiedAfter: nil)
        #expect(claude.records.contains { $0.id == "msg_a1" })
        #expect(claude.records.contains { $0.sessionID == "0b107a68-9fe2-4da0-9dab-78ca760e7ee0" }, "subagent transcripts are included")

        let codex = CodexCollector(locations: locations).collect(modifiedAfter: nil)
        #expect(codex.codexRateLimits?.planType == "team")

        let gemini = GeminiCLICollector(locations: locations).collect(modifiedAfter: nil)
        #expect(gemini.records.count == 3)

        let antigravity = AntigravityCollector(locations: locations).collect(modifiedAfter: nil)
        #expect(antigravity.records.count == 6)
        #expect(antigravity.failures.isEmpty)
    }
}

@Suite struct PaceTests {
    @Test func elapsedFractionFromResetAndLength() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let window = UsageWindow(kind: .session, usedPercent: 50, resetsAt: now.addingTimeInterval(3600), length: 5 * 3600)
        #expect(abs((window.elapsedFraction(now: now) ?? 0) - 0.8) < 1e-9)
        #expect(UsageWindow(kind: .weekly, usedPercent: 10).elapsedFraction(now: now) == nil)
    }
}
