import Foundation
import TokenometerCore

/// Sample data for previews, mockups, and the README screenshots.
public enum SampleData {
    public static func snapshot(now: Date = .now) -> Snapshot {
        func spend(_ input: Int, _ output: Int, _ cacheRead: Int, cost: Double, calls: Int) -> Spend {
            Spend(tokens: TokenCounts(input: input, output: output, cacheRead: cacheRead), costUSD: cost, calls: calls)
        }
        let anthropic = ProviderSnapshot(
            provider: .anthropic, accountKind: .plan, planName: "Max 5x",
            session: UsageWindow(kind: .session, usedPercent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 1500), length: 5 * 3600),
            weekly: UsageWindow(kind: .weekly, usedPercent: 61, resetsAt: now.addingTimeInterval(2.4 * 86400), length: 7 * 86400),
            scoped: [UsageWindow(kind: .weekly, usedPercent: 73, resetsAt: now.addingTimeInterval(2.4 * 86400), length: 7 * 86400, label: "Fable weekly")],
            sessionSpend: spend(120_000, 48_000, 6_200_000, cost: 9.84, calls: 61),
            weeklySpend: spend(410_000, 190_000, 21_400_000, cost: 38.10, calls: 312),
            tools: [
                ToolSpend(tool: .claudeCode, session: spend(120_000, 48_000, 6_200_000, cost: 9.84, calls: 61), weekly: spend(380_000, 170_000, 19_800_000, cost: 34.20, calls: 280)),
                ToolSpend(tool: .claudeDesktop, session: .zero, weekly: spend(30_000, 20_000, 1_600_000, cost: 3.90, calls: 32)),
            ],
            models: [
                ModelSpend(model: "claude-fable-5-1", weekly: spend(300_000, 150_000, 17_000_000, cost: 31.60, calls: 210)),
                ModelSpend(model: "claude-opus-5-5", weekly: spend(110_000, 40_000, 4_400_000, cost: 6.50, calls: 102)),
            ],
            surfaces: [
                SurfaceShare(key: "claude_code", label: "Claude Code", percent: 82),
                SurfaceShare(key: "chat", label: "Chats", percent: 13),
                SurfaceShare(key: "cowork", label: "Cowork", percent: 5),
                SurfaceShare(key: "other", label: "Other", percent: 0),
            ],
            grants: [
                CreditGrant(id: "extra_usage", label: "Extra usage", used: 0, limit: 100),
                CreditGrant(id: "iguana_necktie", label: "Cloud sessions", used: 1.86, limit: 250, endsAt: now.addingTimeInterval(32 * 86400)),
                CreditGrant(id: "harbor_lantern", label: "Project setup", used: 19.81, limit: 100, endsAt: now.addingTimeInterval(22 * 3600), ends: .expiry),
            ]
        )
        let openAI = ProviderSnapshot(
            provider: .openAI, accountKind: .plan, planName: "Team",
            session: UsageWindow(kind: .session, usedPercent: 18, resetsAt: now.addingTimeInterval(3 * 3600 + 900), length: 5 * 3600),
            weekly: UsageWindow(kind: .weekly, usedPercent: 7, resetsAt: now.addingTimeInterval(5.1 * 86400), length: 7 * 86400),
            sessionSpend: spend(15_000, 2_800, 140_000, cost: 0.44, calls: 6),
            weeklySpend: spend(90_000, 21_000, 1_100_000, cost: 3.05, calls: 23),
            tools: [ToolSpend(tool: .codex, session: spend(15_000, 2_800, 140_000, cost: 0.44, calls: 6), weekly: spend(90_000, 21_000, 1_100_000, cost: 3.05, calls: 23))],
            models: [ModelSpend(model: "gpt-6-astra", weekly: spend(88_000, 20_000, 1_080_000, cost: 3.05, calls: 20)), ModelSpend(model: "codex-auto-review", weekly: spend(2_000, 1_000, 20_000, cost: 0, calls: 3))]
        )
        let google = ProviderSnapshot(
            provider: .google, accountKind: .plan, planName: "Pro",
            session: UsageWindow(kind: .session, usedPercent: 4, resetsAt: now.addingTimeInterval(4 * 3600 + 600), length: 5 * 3600, label: "Gemini session"),
            weekly: UsageWindow(kind: .weekly, usedPercent: 3, resetsAt: now.addingTimeInterval(6.9 * 86400), length: 7 * 86400, label: "Gemini weekly"),
            scoped: [
                UsageWindow(kind: .session, usedPercent: 0, resetsAt: now.addingTimeInterval(4 * 3600 + 600), length: 5 * 3600, label: "Claude & GPT session"),
                UsageWindow(kind: .weekly, usedPercent: 0, resetsAt: now.addingTimeInterval(6.9 * 86400), length: 7 * 86400, label: "Claude & GPT weekly"),
            ],
            sessionSpend: Spend(tokens: TokenCounts(input: 1_900_000, output: 60_000, thinking: 12_000), costUSD: 0, hasUnknownCost: true, calls: 88),
            weeklySpend: Spend(tokens: TokenCounts(input: 5_600_000, output: 210_000, thinking: 40_000), costUSD: 0, hasUnknownCost: true, calls: 240),
            tools: [ToolSpend(tool: .antigravity, session: .zero, weekly: Spend(tokens: TokenCounts(input: 5_600_000, output: 210_000), costUSD: 0, hasUnknownCost: true, calls: 240))],
            models: [ModelSpend(model: "gemini-3.8-flash", weekly: Spend(tokens: TokenCounts(input: 5_600_000, output: 210_000), costUSD: 0, hasUnknownCost: true, calls: 240))]
        )
        return Snapshot(generatedAt: now.addingTimeInterval(-40), providers: [anthropic, openAI, google])
    }
}
