import SwiftUI
import TokenometerCore

/// One provider's block in the menu: header, usage bars, spend lines, and a disclosure with
/// per-tool and per-model rows. Shared with the mockup renderer so the README screenshots are real.
public struct ProviderSectionView: View {
    let snapshot: ProviderSnapshot
    let now: Date
    @State private var showDetail: Bool

    public init(snapshot: ProviderSnapshot, now: Date = .now, expanded: Bool = false) {
        self.snapshot = snapshot
        self.now = now
        _showDetail = State(initialValue: expanded)
    }

    private var color: Color { snapshot.provider.color }
    private var weeklyLabel: String {
        if let label = snapshot.weekly?.label { return label }
        return snapshot.scoped.isEmpty ? "Weekly" : "All models weekly"
    }
    private var sessionLabel: String { snapshot.session?.label ?? "Session" }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(snapshot.provider.displayName).font(.headline)
                if let plan = snapshot.planName {
                    Text(plan.prefix(1).uppercased() + plan.dropFirst()).font(.caption).foregroundStyle(.secondary)
                }
                if snapshot.accountKind == .metered {
                    Text("metered").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let session = snapshot.session {
                UsageBarView(label: sessionLabel, window: session, base: color, stale: snapshot.windowsStale, now: now)
            }
            if let weekly = snapshot.weekly {
                UsageBarView(label: weeklyLabel, window: weekly, base: color, stale: snapshot.windowsStale, now: now)
            }
            ForEach(Array(snapshot.scoped.enumerated()), id: \.offset) { _, window in
                UsageBarView(label: window.label ?? "Scoped", window: window, base: color, stale: snapshot.windowsStale, now: now)
            }
            if snapshot.session == nil && snapshot.weekly == nil {
                Text(snapshot.accountKind == .metered ? "Set a budget in Settings to see a bar" : (snapshot.windowsStale?.reason ?? "Usage limits unavailable"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SpendLine(title: "Session", spend: snapshot.sessionSpend, plan: snapshot.accountKind == .plan)
            SpendLine(title: "Week", spend: snapshot.weeklySpend, plan: snapshot.accountKind == .plan)
            if let stale = snapshot.spendStale {
                Label(stale.reason, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.secondary)
            }
            if !snapshot.tools.isEmpty {
                DisclosureGroup(isExpanded: $showDetail) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snapshot.tools) { tool in
                            DetailRow(name: tool.tool.displayName, spend: tool.weekly)
                        }
                        if snapshot.models.count > 1 || snapshot.tools.count == 1 {
                            Divider().padding(.vertical, 2)
                            ForEach(snapshot.models) { model in
                                DetailRow(name: model.model, spend: model.weekly)
                            }
                        }
                    }
                    .padding(.top, 2)
                } label: {
                    Text("Tools and models this week").font(.caption)
                }
                .font(.caption)
            }
        }
    }
}

public struct SpendLine: View {
    let title: String
    let spend: Spend
    let plan: Bool

    public init(title: String, spend: Spend, plan: Bool) {
        self.title = title
        self.spend = spend
        self.plan = plan
    }

    public var body: some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("\(Format.tokens(spend.tokens.total)) tokens").font(.caption.monospacedDigit())
            Text(Format.usd(spend)).font(.caption.monospacedDigit())
                .help(plan ? "API-equivalent cost; your subscription is the real bill" : "Estimated cost at API rates")
        }
    }
}

public struct DetailRow: View {
    let name: String
    let spend: Spend

    public init(name: String, spend: Spend) {
        self.name = name
        self.spend = spend
    }

    public var body: some View {
        HStack {
            Text(name).font(.caption2).lineLimit(1)
            Spacer()
            Text(Format.tokens(spend.tokens.total)).font(.caption2.monospacedDigit())
            Text(Format.usd(spend)).font(.caption2.monospacedDigit()).frame(width: 52, alignment: .trailing)
        }
        .foregroundStyle(.secondary)
    }
}

/// The widget's per-provider block, by family. Shared with the mockup renderer.
public struct WidgetProviderView: View {
    public enum Size { case small, medium, large }

    let snapshot: ProviderSnapshot
    let size: Size
    let showsResets: Bool
    let now: Date
    @Environment(\.widgetScale) private var scale

    public init(snapshot: ProviderSnapshot, size: Size, showsResets: Bool = false, now: Date = .now) {
        self.snapshot = snapshot
        self.size = size
        self.showsResets = showsResets
        self.now = now
    }

    private var color: Color { snapshot.provider.color }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6 * scale, height: 6 * scale)
                Text(snapshot.provider.displayName).font(.widget(scale).bold())
                Spacer()
                if size == .small, let session = snapshot.session {
                    Text(Format.percent(session.usedPercent)).font(.widget(scale).monospacedDigit())
                }
            }
            if let session = snapshot.session {
                if size == .small {
                    MiniHorizontalBar(percent: session.usedPercent, base: color, pace: session.elapsedFraction(now: now))
                } else {
                    UsageBarView(label: session.label ?? "Session", window: session, base: color, stale: snapshot.windowsStale, compact: true, showsReset: showsResets, now: now)
                }
            }
            if size != .small, let weekly = snapshot.weekly {
                UsageBarView(label: weekly.label ?? "Weekly", window: weekly, base: color, stale: snapshot.windowsStale, compact: true, showsReset: showsResets, now: now)
            }
            if size == .large {
                ForEach(Array(snapshot.scoped.enumerated()), id: \.offset) { _, window in
                    UsageBarView(label: window.label ?? "Scoped", window: window, base: color, stale: snapshot.windowsStale, compact: true, showsReset: showsResets, now: now)
                }
                HStack {
                    Text("Session \(Format.tokens(snapshot.sessionSpend.tokens.total)) · \(Format.usd(snapshot.sessionSpend))")
                    Spacer()
                    Text("Week \(Format.tokens(snapshot.weeklySpend.tokens.total)) · \(Format.usd(snapshot.weeklySpend))")
                }
                .font(.widget(scale).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

public struct MiniHorizontalBar: View {
    let percent: Double
    let base: Color
    let pace: Double?
    @Environment(\.widgetScale) private var scale

    public init(percent: Double, base: Color, pace: Double? = nil) {
        self.percent = percent
        self.base = base
        self.pace = pace
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(UsageLevel.tint(for: percent, base: base, pace: pace))
                    .frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
                Capsule().strokeBorder(Color.primary.opacity(0.4), lineWidth: 0.5)
                if let pace {
                    RoundedRectangle(cornerRadius: 0.5).fill(percent / 100 >= pace ? Color.primary : base)
                        .frame(width: 1.5, height: geo.size.height + 3)
                        .offset(x: geo.size.width * pace - 0.75, y: -1.5)
                }
            }
        }
        .frame(height: 4 * scale)
    }
}

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
                UsageWindow(kind: .weekly, usedPercent: 0, resetsAt: now.addingTimeInterval(6.9 * 86400), length: 7 * 86400, label: "Claude & GPT weekly"),
                UsageWindow(kind: .session, usedPercent: 0, resetsAt: now.addingTimeInterval(4 * 3600 + 600), length: 5 * 3600, label: "Claude & GPT session"),
            ],
            sessionSpend: Spend(tokens: TokenCounts(input: 1_900_000, output: 60_000, thinking: 12_000), costUSD: 0, hasUnknownCost: true, calls: 88),
            weeklySpend: Spend(tokens: TokenCounts(input: 5_600_000, output: 210_000, thinking: 40_000), costUSD: 0, hasUnknownCost: true, calls: 240),
            tools: [ToolSpend(tool: .antigravity, session: .zero, weekly: Spend(tokens: TokenCounts(input: 5_600_000, output: 210_000), costUSD: 0, hasUnknownCost: true, calls: 240))],
            models: [ModelSpend(model: "gemini-3.8-flash", weekly: Spend(tokens: TokenCounts(input: 5_600_000, output: 210_000), costUSD: 0, hasUnknownCost: true, calls: 240))]
        )
        return Snapshot(generatedAt: now.addingTimeInterval(-40), providers: [anthropic, openAI, google])
    }
}
