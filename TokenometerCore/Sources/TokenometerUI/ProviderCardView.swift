import SwiftUI
import TokenometerCore

/// One provider's card in the menu: logo, name, plan, and live or stale; the session window as the
/// hero (percent, bar, reset, and the share of its time already elapsed); the weekly and scoped windows
/// as small cards in a two-column grid; the two spend cards; one disclosure for tools, models, surfaces,
/// and credits. Shared with the mockup renderer so the README screenshots are real.
public struct ProviderCardView: View {
    let snapshot: ProviderSnapshot
    let now: Date
    @State private var showDetail: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.statusPalette) private var palette

    public init(snapshot: ProviderSnapshot, now: Date = .now, expanded: Bool = false) {
        self.snapshot = snapshot
        self.now = now
        _showDetail = State(initialValue: expanded)
    }

    /// Two-up tiles share this height in every card so the rows line up across providers.
    private static let tileHeight: CGFloat = 108

    private var inset: Color { scheme == .dark ? Color.black.opacity(0.22) : Color.primary.opacity(0.05) }

    private func statusColor(_ window: UsageWindow) -> Color {
        palette.color(UsageStatus.of(percent: window.usedPercent, pace: window.elapsedFraction(now: now)), scheme, provider: snapshot.provider)
    }

    /// A grant past its expiry is gone; one past a reset is shown until the next report replaces it.
    private var grants: [CreditGrant] {
        (snapshot.grants ?? []).filter { !($0.ends == .expiry && ($0.endsAt ?? .distantFuture) <= now) }
    }

    private var hero: WindowRow? { snapshot.windowRows.first { $0.role == .session } }

    var body_tiles: [Tile] { Tile.build(from: snapshot.windowRows.filter { $0.id != hero?.id }) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let hero { heroBlock(hero) }
            if let stale = snapshot.windowsStale, !snapshot.windowRows.isEmpty {
                Label("Stale since \(Format.age(stale.since, now: now)): \(stale.reason)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if snapshot.windowRows.isEmpty {
                Text(snapshot.accountKind == .metered ? "Set a budget in Settings to see a bar" : (snapshot.windowsStale?.reason ?? "Usage limits unavailable"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            tileGrid
            spendCards
            if let stale = snapshot.spendStale {
                Label(stale.reason, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            details
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06)))
        .opacity(snapshot.windowsStale == nil ? 1 : 0.92)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            ProviderTile(snapshot.provider, size: 28)
            Text(snapshot.provider.cardName).font(.system(size: 15, weight: .semibold))
            if let plan = snapshot.planName {
                chip(plan.prefix(1).uppercased() + plan.dropFirst())
            }
            if snapshot.accountKind == .metered { chip("metered") }
            Spacer(minLength: 4)
            if let stale = snapshot.windowsStale {
                Label("stale", systemImage: "exclamationmark.triangle.fill").labelStyle(.titleAndIcon)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    .help("Stale since \(Format.age(stale.since, now: now)): \(stale.reason)")
            } else {
                HStack(spacing: 5) {
                    Circle().fill(palette.color(.ok, scheme, provider: snapshot.provider)).frame(width: 6, height: 6)
                    Text("live").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(palette.color(.ok, scheme, provider: snapshot.provider))
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    // MARK: Session hero

    private func heroBlock(_ row: WindowRow) -> some View {
        let window = row.window
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label).font(.system(size: 13, weight: .medium))
                Spacer()
                percentLabel(window, size: 24)
            }
            StatusBar(percent: window.usedPercent, pace: window.elapsedFraction(now: now), height: 8, provider: snapshot.provider)
            HStack(spacing: 5) {
                resetText(window, size: 12.5, withRemaining: true)
                Spacer(minLength: 4)
                elapsedText(window, size: 12)
            }
        }
    }

    private func percentLabel(_ window: UsageWindow, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(Int(min(max(window.usedPercent, 0), 100).rounded()))").font(.system(size: size, weight: .semibold).monospacedDigit())
            Text("%").font(.system(size: size * 0.5, weight: .medium)).opacity(0.8)
        }
        .foregroundStyle(statusColor(window))
    }

    @ViewBuilder
    private func resetText(_ window: UsageWindow, size: CGFloat, withRemaining: Bool = false, word: Bool = true) -> some View {
        if let time = Format.resetTime(window.resetsAt, now: now) {
            HStack(spacing: 5) {
                Image(systemName: "clock").font(.system(size: size - 1))
                let remaining = withRemaining ? (Format.remaining(window, now: now).map { " · \($0)" } ?? "") : ""
                Text("\(word ? "Resets " : "")\(Text(time).fontWeight(.semibold).foregroundColor(.primary))\(remaining)")
                    .font(.system(size: size)).lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
    }

    /// The share of the window's time already gone: the number the pace tick marks on the bar.
    @ViewBuilder
    private func elapsedText(_ window: UsageWindow, size: CGFloat) -> some View {
        if let elapsed = Format.elapsed(window, now: now) {
            Text(elapsed).font(.system(size: size, weight: .semibold).monospacedDigit())
                .help("\(elapsed) of this window has passed")
        }
    }

    // MARK: Weekly and scoped windows

    /// A weekly or scoped window as a tile, or a group of one scope's session and weekly as one tile.
    enum Tile {
        case window(WindowRow)
        case group(name: String, session: WindowRow, weekly: WindowRow)

        static func build(from rows: [WindowRow]) -> [Tile] {
            var tiles: [Tile] = []
            var consumed = Set<String>()
            for row in rows where !consumed.contains(row.id) {
                guard row.role == .scoped, let scope = scopeName(row.label) else {
                    tiles.append(.window(row))
                    continue
                }
                let pair = rows.first { $0.id != row.id && $0.role == .scoped && scopeName($0.label) == scope && isSession($0.label) != isSession(row.label) }
                if let pair {
                    consumed.insert(pair.id)
                    tiles.append(.group(name: scope, session: isSession(row.label) ? row : pair, weekly: isSession(row.label) ? pair : row))
                } else {
                    tiles.append(.window(row))
                }
            }
            return tiles
        }

        private static func isSession(_ label: String) -> Bool { label.hasSuffix(" session") }
        private static func scopeName(_ label: String) -> String? {
            for suffix in [" session", " weekly"] where label.hasSuffix(suffix) { return String(label.dropLast(suffix.count)) }
            return nil
        }
    }

    @ViewBuilder
    private var tileGrid: some View {
        let tiles = body_tiles
        if !tiles.isEmpty {
            VStack(spacing: 8) {
                ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                    let pair = Array(tiles[start..<min(start + 2, tiles.count)])
                    if pair.count == 2 {
                        HStack(spacing: 8) {
                            tileView(pair[0]).frame(maxWidth: .infinity).frame(height: Self.tileHeight)
                            tileView(pair[1]).frame(maxWidth: .infinity).frame(height: Self.tileHeight)
                        }
                    } else {
                        tileView(pair[0]).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tileView(_ tile: Tile) -> some View {
        switch tile {
        case .window(let row): windowTile(row)
        case .group(let name, let session, let weekly): groupTile(name, session, weekly)
        }
    }

    private func tileLabel(_ row: WindowRow) -> String {
        row.role == .scoped && row.label.hasSuffix(" weekly") ? String(row.label.dropLast(" weekly".count)) : (row.role == .weekly ? (row.window.label ?? "Weekly") : row.label)
    }

    private func windowTile(_ row: WindowRow) -> some View {
        let window = row.window
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(tileLabel(row)).font(.system(size: 13, weight: .semibold))
                Spacer()
                percentLabel(window, size: 16)
            }
            HStack { Spacer(); elapsedText(window, size: 12) }.frame(height: 14)
            Spacer(minLength: 2)
            StatusBar(percent: window.usedPercent, pace: window.elapsedFraction(now: now), height: 5, provider: snapshot.provider)
            Spacer(minLength: 2)
            resetText(window, size: 11.5, word: false)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(inset))
    }

    private func groupTile(_ name: String, _ session: WindowRow, _ weekly: WindowRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 2)
            miniRow("Session", session.window)
            miniRow("Weekly", weekly.window)
            Spacer(minLength: 2)
            resetText(session.window, size: 11.5, word: false)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(inset))
    }

    private func miniRow(_ label: String, _ window: UsageWindow) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
            StatusBar(percent: window.usedPercent, pace: window.elapsedFraction(now: now), height: 5, provider: snapshot.provider)
            Text(Format.percent(window.usedPercent)).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(statusColor(window)).frame(width: 34, alignment: .trailing)
        }
    }

    // MARK: Spend

    private var spendCards: some View {
        HStack(spacing: 8) {
            spendCard("Session", snapshot.sessionSpend)
            spendCard("Week", snapshot.weeklySpend)
        }
    }

    private func spendCard(_ title: String, _ spend: Spend) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Text("\(Format.tokens(spend.tokens.total)) · \(Format.usd(spend))")
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit()).lineLimit(1)
                .help(snapshot.accountKind == .plan ? "API-equivalent cost; your subscription is the real bill" : "Estimated cost at API rates")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(inset))
    }

    // MARK: Details

    @ViewBuilder
    private var details: some View {
        let hasSurfaces = !(snapshot.surfaces ?? []).isEmpty
        if !snapshot.tools.isEmpty || hasSurfaces || !grants.isEmpty {
            DisclosureGroup(isExpanded: $showDetail) {
                VStack(alignment: .leading, spacing: 4) {
                    if !snapshot.tools.isEmpty {
                        sectionTitle("This Mac, this week")
                        ForEach(snapshot.tools) { DetailRow(name: $0.tool.displayName, spend: $0.weekly) }
                        if snapshot.models.count > 1 || snapshot.tools.count == 1 {
                            Divider().padding(.vertical, 2)
                            ForEach(snapshot.models) { DetailRow(name: $0.model, spend: $0.weekly) }
                        }
                    }
                    if let surfaces = snapshot.surfaces, !surfaces.isEmpty {
                        // The rows above are this Mac's logs. These are the provider's own figures
                        // for the whole account, so chat and other devices are in them.
                        Divider().padding(.vertical, 2)
                        sectionTitle("Whole account, by surface")
                            .help("As the provider reports it for this week: each surface's share of the week's usage, on every device.")
                        ForEach(surfaces, id: \.key) { surface in
                            HStack {
                                Text(surface.label).lineLimit(1)
                                Spacer()
                                Text(Format.percent(surface.percent)).monospacedDigit()
                            }
                            .font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }
                    }
                    if !grants.isEmpty {
                        Divider().padding(.vertical, 2)
                        sectionTitle("Credits")
                        ForEach(grants, id: \.id) { CreditRow(grant: $0, color: snapshot.provider.color) }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(grants.isEmpty ? "Tools and models" : "Tools, models, credits").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.5).foregroundStyle(.tertiary)
    }
}

/// One credit in the Credits section: name, dollars used of the limit, a bar when there is a limit,
/// and when it resets or expires.
struct CreditRow: View {
    let grant: CreditGrant
    let color: Color

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: grant.currency).precision(.fractionLength(value == value.rounded() ? 0 : 2)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(grant.label).lineLimit(1)
                Spacer()
                Text(grant.limit.map { "\(money(grant.used)) of \(money($0))" } ?? "\(money(grant.used)) used").monospacedDigit()
            }
            .font(.system(size: 12.5)).foregroundStyle(.secondary)
            if let limit = grant.limit, limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.12))
                        Capsule().fill(color).frame(width: max(5, geo.size.width * min(max(grant.used / limit, 0), 1)))
                    }
                }
                .frame(height: 5)
            }
            if let endsAt = grant.endsAt {
                let when = endsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                Text(grant.ends == .expiry ? "Expires \(when)" : grant.ends == .reset ? "Resets \(when)" : "Ends \(when)")
                    .font(.system(size: 11.5)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct DetailRow: View {
    let name: String
    let spend: Spend

    var body: some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer()
            Text(Format.tokens(spend.tokens.total)).monospacedDigit()
            Text(Format.usd(spend)).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
        .font(.system(size: 12.5)).foregroundStyle(.secondary)
    }
}

extension Provider {
    /// The name on a menu card: the product, as the logo reads. Widgets use `shortName`.
    var cardName: String {
        switch self {
        case .anthropic: "Claude"
        case .openAI: "Codex"
        case .google: "Antigravity"
        }
    }
}
