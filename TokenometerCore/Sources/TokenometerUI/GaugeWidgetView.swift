import SwiftUI
import TokenometerCore

/// The Gauge widget: half-circle gauges in provider cards. Small, medium, large; one, two, or three
/// providers (`providers` empty means all). Every size opens with a header row: what it shows (or, for
/// one provider, its logo and name) on the left, the snapshot time on the right. The view fills the
/// widget frame and draws its own padding; WidgetKit supplies the container background.
public struct GaugeWidgetView: View {
    public enum Size { case small, medium, large }

    let snapshot: Snapshot?
    let size: Size
    let providers: Set<Provider>
    let now: Date

    public init(snapshot: Snapshot?, size: Size, providers: Set<Provider> = [], now: Date = .now) {
        self.snapshot = snapshot?.stamped()
        self.size = size
        self.providers = providers
        self.now = now
    }

    private var shown: [ProviderSnapshot] {
        let all = snapshot?.providers ?? []
        return providers.isEmpty ? all : all.filter { providers.contains($0.provider) }
    }

    private var asOf: String {
        guard let snapshot else { return "" }
        return "as of \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))"
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.statusPalette, PaletteChoice(stored: snapshot?.palette).palette)
    }

    @ViewBuilder
    private var content: some View {
        let list = shown
        if list.isEmpty {
            Text(snapshot == nil || snapshot?.providers.isEmpty == true ? "Open Tokenometer to start collecting" : "No data for these providers yet")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).minimumScaleFactor(0.8)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if list.count == 1 {
            single(list[0])
        } else if list.count == 2 {
            double(list)
        } else {
            triple(list)
        }
    }

    // MARK: Frame and header

    /// The widget's frame: 11 pt over the header, 12 at the sides and bottom, 6 between header and body.
    private func frame<Header: View, Body: View>(@ViewBuilder header: () -> Header, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header()
            body().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 11).padding(.horizontal, 12).padding(.bottom, 12)
    }

    /// "Session" or "Session and weekly" with the snapshot time.
    private func header(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            asOfText
        }
        .padding(.horizontal, 2)
        .frame(height: 16)
    }

    /// One provider: its logo tile and short name in place of the title.
    private func providerHeader(_ p: ProviderSnapshot, small: Bool) -> some View {
        HStack(alignment: .center, spacing: 4) {
            HStack(spacing: small ? 4 : 5) {
                ProviderTile(p.provider, size: small ? 16 : 18)
                Text(p.shortName).font(.system(size: small ? 12.5 : 13, weight: .bold)).lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
            asOfText
        }
        .padding(.horizontal, small ? 0 : 2)
        .frame(height: 18)
    }

    private var asOfText: some View {
        Text(asOf).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
    }

    // MARK: Three providers

    @ViewBuilder
    private func triple(_ list: [ProviderSnapshot]) -> some View {
        switch size {
        case .small:
            frame { header("Session") } body: {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.offset) { index, p in
                        if index > 0 { Spacer(minLength: 0) }
                        GaugeSideRow(gaugeWidth: 68, gap: 4, whoSpacing: 3) {
                            nameLabel(p, tile: 18, size: 12.5, spacing: 5)
                        } reset: {
                            GaugeReset(window: primary(p), now: now, size: 10.5, iconSize: 10, spacing: 4)
                        } gauge: {
                            gauge(p, primary(p), width: 68, numberSize: 16)
                        }
                    }
                }
            }
        case .medium:
            frame { header("Session") } body: {
                HStack(spacing: 6) {
                    ForEach(list) { p in
                        VStack(spacing: 0) {
                            nameLabel(p, tile: 18, size: 12.5, spacing: 6)
                                .padding(.leading, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 0)
                            gauge(p, primary(p), width: 94, numberSize: 22)
                            Spacer(minLength: 0)
                            GaugeReset(window: primary(p), now: now, size: 10.5, iconSize: 10, spacing: 4)
                        }
                        .padding(.top, 8).padding(.horizontal, 4).padding(.bottom, 7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GaugeCard())
                    }
                }
            }
        case .large:
            frame { header("Session and weekly") } body: {
                VStack(spacing: 6) {
                    ForEach(list) { p in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 6) {
                                nameLabel(p, tile: 18, size: 13, spacing: 6)
                                spendColumn(p)
                            }
                            .frame(width: 74, alignment: .leading)
                            if p.session == nil && p.weekly == nil && !p.windowRows.isEmpty {
                                block(p, p.windowRows[0].window, caption: GaugeWindow(p.windowRows[0]).kind)
                                block(p, p.windowRows.dropFirst().first?.window, caption: p.windowRows.dropFirst().first.map { GaugeWindow($0).kind } ?? "")
                            } else if p.windowRows.isEmpty {
                                GaugeNoLimits(p, fontSize: 13).frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                block(p, p.session, caption: "Session")
                                block(p, p.weekly, caption: "Weekly")
                            }
                        }
                        .padding(.top, 6).padding(.bottom, 6).padding(.leading, 10).padding(.trailing, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GaugeCard())
                    }
                }
            }
        }
    }

    /// Large, three providers: a session or weekly gauge with its reset under it.
    @ViewBuilder
    private func block(_ p: ProviderSnapshot, _ window: UsageWindow?, caption: String) -> some View {
        VStack(spacing: 4) {
            if let window {
                gauge(p, window, width: 104, numberSize: 22, caption: caption, captionSize: 11)
                GaugeReset(window: window, now: now, size: 10.5, iconSize: 10, spacing: 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// "This week" over the week's tokens and dollars, for the large three-provider rows.
    private func spendColumn(_ p: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("This week").font(.system(size: 10.5)).foregroundStyle(.secondary)
            Text(Format.tokens(p.weeklySpend.tokens.total)).font(.system(size: 11.5, weight: .semibold))
            Text(Format.usd(p.weeklySpend)).font(.system(size: 11.5, weight: .semibold))
        }
        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
    }

    // MARK: Two providers

    @ViewBuilder
    private func double(_ list: [ProviderSnapshot]) -> some View {
        switch size {
        case .small:
            // Equal space under the header, between the rows, and under the bottom row.
            VStack(alignment: .leading, spacing: 0) {
                header("Session")
                ForEach(list) { p in
                    Spacer(minLength: 0)
                    GaugeSideRow(gaugeWidth: 70, gap: 4, whoSpacing: 1) {
                        nameLabel(p, tile: 20, size: 12.5, spacing: 5).padding(.bottom, 1)
                    } reset: {
                        GaugeReset(window: primary(p), now: now, size: 10.5, iconSize: 10, spacing: 3)
                    } gauge: {
                        gauge(p, primary(p), width: 70, numberSize: 18)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 11).padding(.horizontal, 12)
        case .medium:
            frame { header("Session") } body: {
                HStack(spacing: 6) {
                    ForEach(list) { p in
                        VStack(spacing: 0) {
                            nameLabel(p, tile: 18, size: 14, spacing: 6)
                                .padding(.leading, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Spacer(minLength: 0)
                            gauge(p, primary(p), width: 108, numberSize: 26)
                            Spacer(minLength: 0)
                            GaugeReset(window: primary(p), now: now, size: 11, iconSize: 10, spacing: 4, prefixed: true)
                        }
                        .padding(.vertical, 7).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GaugeCard())
                    }
                }
            }
        case .large:
            frame { header("Session and weekly") } body: {
                GeometryReader { geo in
                    let weights = list.map { Self.largeTwoWeight(count: GaugeWindow.all($0).count) }
                    let total = weights.reduce(0, +)
                    let available = geo.size.height - 6 * CGFloat(list.count - 1)
                    VStack(spacing: 6) {
                        ForEach(Array(list.enumerated()), id: \.offset) { index, p in
                            largeTwoCard(p).frame(height: available * weights[index] / total)
                        }
                    }
                }
            }
        }
    }

    private static func largeTwoGauge(count: Int) -> CGFloat { count == 3 ? 96 : count >= 4 ? 74 : 120 }
    private static func largeTwoWeight(count: Int) -> CGFloat { (largeTwoGauge(count: count) * 62 / 112 + 60).rounded() }

    /// Large, two providers: a gauge per window, the scope above when any window has one, the kind inside.
    private func largeTwoCard(_ p: ProviderSnapshot) -> some View {
        let windows = GaugeWindow.all(p)
        let n = windows.count
        let width = Self.largeTwoGauge(count: n)
        let numberSize: CGFloat = n >= 4 ? 16 : n == 3 ? 21 : 26
        let anyScope = windows.contains { $0.scope != nil }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                ProviderTile(p.provider, size: 22)
                Text(p.shortName).font(.system(size: 15, weight: .semibold)).lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                weekSpendLine(p, size: 11.5)
            }
            .frame(height: 22)
            if windows.isEmpty {
                GaugeNoLimits(p, fontSize: 15).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: n >= 4 ? 3 : 4) {
                    ForEach(windows) { w in
                        VStack(spacing: 5) {
                            if anyScope {
                                Text(w.scope ?? "All models").font(.system(size: n >= 4 ? 11.5 : 12, weight: .semibold))
                                    .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8).frame(height: 15)
                            }
                            gauge(p, w.window, width: width, numberSize: numberSize, caption: w.kind, captionSize: n >= 4 ? 10.5 : 11.5)
                            GaugeReset(window: w.window, now: now, size: n >= 4 ? 10.5 : 11.5, iconSize: n >= 4 ? 9.5 : 10, spacing: n >= 4 ? 3 : 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, n >= 4 ? -3 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 7).padding(.horizontal, 8).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GaugeCard())
    }

    /// "This week 22M · $38.10", the numbers in the primary color.
    private func weekSpendLine(_ p: ProviderSnapshot, size: CGFloat) -> some View {
        let figures = "\(Format.tokens(p.weeklySpend.tokens.total)) · \(Format.usd(p.weeklySpend))"
        return Text("This week \(Text(figures).fontWeight(.semibold).foregroundStyle(.primary))")
            .font(.system(size: size)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
    }

    // MARK: One provider

    @ViewBuilder
    private func single(_ p: ProviderSnapshot) -> some View {
        let windows = GaugeWindow.all(p)
        switch size {
        case .small:
            frame { providerHeader(p, small: true) } body: {
                if windows.isEmpty {
                    GaugeNoLimits(p, fontSize: 16).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let rows = windows.count > 3 ? Array(windows.prefix(2)) : windows
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, w in
                            if index > 0 { Spacer(minLength: 0) }
                            if rows.count == 3 {
                                GaugeSideRow(gaugeWidth: 60, gap: 4, whoSpacing: 1) {
                                    Text(w.label).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                                } reset: {
                                    GaugeReset(window: w.window, now: now, size: 10.5, iconSize: 10, spacing: 3)
                                } gauge: {
                                    gauge(p, w.window, width: 60, numberSize: 15)
                                }
                            } else {
                                HStack(alignment: .center, spacing: 4) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        if let scope = w.scope {
                                            Text(scope).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                                                .lineLimit(1).minimumScaleFactor(0.8)
                                        }
                                        Text(w.kind).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                    }
                                    Spacer(minLength: 0)
                                    VStack(spacing: 2) {
                                        gauge(p, w.window, width: 76, numberSize: 19)
                                        GaugeReset(window: w.window, now: now, size: 10.5, iconSize: 10, spacing: 3).fixedSize()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        case .medium:
            frame { providerHeader(p, small: false) } body: {
                if windows.isEmpty {
                    GaugeNoLimits(p, fontSize: 20).frame(maxWidth: .infinity, maxHeight: .infinity).background(GaugeCard())
                } else {
                    let cells = Array(windows.prefix(3))
                    let width: CGFloat = cells.count == 3 ? 94 : 108
                    HStack(spacing: 6) {
                        ForEach(cells) { w in
                            VStack(spacing: 0) {
                                Text(w.scope ?? w.kind).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                                gauge(p, w.window, width: width, numberSize: (width * 0.22).rounded(), caption: w.scope == nil ? nil : w.kind, captionSize: 11.5)
                                Spacer(minLength: 0)
                                GaugeReset(window: w.window, now: now, size: 11, iconSize: 10, spacing: 4, prefixed: cells.count < 3)
                            }
                            .padding(.vertical, 7).padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(GaugeCard())
                        }
                    }
                }
            }
        case .large:
            frame { providerHeader(p, small: false) } body: {
                if windows.isEmpty {
                    spendCard(p, tall: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    largeOne(p, windows)
                }
            }
        }
    }

    /// Large, one provider: a card per window plus a weekly spend card. With an even number of windows
    /// the spend card spans the width under them; with an odd number it takes the last free cell.
    private func largeOne(_ p: ProviderSnapshot, _ windows: [GaugeWindow]) -> some View {
        let n = windows.count
        let spanSpend = n % 2 == 0
        let width: CGFloat = n > 3 ? 100 : n == 2 ? 120 : 132
        let rows = stride(from: 0, to: n, by: 2).map { Array(windows[$0..<min($0 + 2, n)]) }
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row) { w in
                        VStack(spacing: 0) {
                            Text(w.label).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            gauge(p, w.window, width: width, numberSize: (width * 0.22).rounded())
                            Spacer(minLength: 0)
                            GaugeReset(window: w.window, now: now, size: 11.5, iconSize: 11, spacing: 4, prefixed: true)
                        }
                        .padding(.top, 9).padding(.horizontal, 11).padding(.bottom, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GaugeCard())
                    }
                    if row.count == 1 && !spanSpend { spendCard(p, tall: true) }
                }
                .frame(maxHeight: .infinity)
            }
            if spanSpend { spendCard(p, tall: false) }
        }
    }

    /// The week's spend: tall (dollars over tokens) in a grid cell, or one row across the width.
    @ViewBuilder
    private func spendCard(_ p: ProviderSnapshot, tall: Bool) -> some View {
        let tokens = Format.tokens(p.weeklySpend.tokens.total)
        let dollars = Format.usd(p.weeklySpend)
        if tall {
            VStack(alignment: .leading, spacing: 0) {
                Text("This week").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                spendFigure(dollars, "API price", size: 30)
                Spacer(minLength: 0)
                spendFigure(tokens, "tokens", size: 30)
            }
            .padding(.top, 9).padding(.horizontal, 11).padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(GaugeCard())
        } else {
            HStack(alignment: .center, spacing: 6) {
                Text("This week").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                spendInline(tokens, "tokens")
                Spacer(minLength: 4)
                spendInline(dollars, "API price")
            }
            .padding(.vertical, 8).padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .background(GaugeCard())
        }
    }

    private func spendFigure(_ value: String, _ unit: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: size, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(unit).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func spendInline(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit()
            Text(unit).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        .lineLimit(1).fixedSize()
    }

    // MARK: Shared pieces

    /// The window a one-gauge layout shows: the session, else the first window there is.
    private func primary(_ p: ProviderSnapshot) -> UsageWindow? { p.session ?? p.windowRows.first?.window }

    private func nameLabel(_ p: ProviderSnapshot, tile: CGFloat, size: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ProviderTile(p.provider, size: tile)
            Text(p.shortName).font(.system(size: size, weight: .semibold)).lineLimit(1).fixedSize()
        }
    }

    /// A window's gauge, dimmed when the provider's windows are stale. With no window (a metered
    /// account, or none reported) the gauge's box holds the week's spend instead.
    @ViewBuilder
    private func gauge(_ p: ProviderSnapshot, _ window: UsageWindow?, width: CGFloat, numberSize: CGFloat, caption: String? = nil, captionSize: CGFloat = 11) -> some View {
        if let window {
            GaugeArc(window: window, now: now, width: width, numberSize: numberSize, caption: caption, captionSize: captionSize)
                .opacity(p.windowsStale == nil ? 1 : 0.6)
        } else {
            GaugeNoLimits(p, fontSize: max(11, numberSize * 0.7))
                .frame(width: width, height: width * 62 / 112)
        }
    }
}

// MARK: - Helpers private to the Gauge widget

/// One window as the Gauge widget names it: "Gemini session" is scope "Gemini", kind "Session". The
/// all-models weekly window is plain "Weekly", as the mockups have it.
private struct GaugeWindow: Identifiable {
    var label: String
    var kind: String
    var scope: String?
    var window: UsageWindow
    var id: String

    init(_ row: WindowRow) {
        let label: String = switch row.role {
        case .session: row.window.label ?? "Session"
        case .weekly: row.window.label ?? "Weekly"
        case .scoped: row.label
        }
        self.label = label
        self.window = row.window
        self.id = row.id
        let lower = label.lowercased()
        if let kind = ["session", "weekly"].first(where: { lower == $0 || lower.hasSuffix(" " + $0) }) {
            self.kind = kind.prefix(1).uppercased() + kind.dropFirst()
            let scope = label.dropLast(kind.count).trimmingCharacters(in: .whitespaces)
            self.scope = scope.isEmpty ? nil : scope
        } else {
            self.kind = label
            self.scope = nil
        }
    }

    static func all(_ p: ProviderSnapshot) -> [GaugeWindow] { p.windowRows.map(GaugeWindow.init) }
}

/// `ArcGauge` with its caption set at the mockup's size. The gauge is given a blank caption, which
/// lifts the number by a caption line, and the real caption is drawn over that line.
private struct GaugeArc: View {
    let window: UsageWindow
    let now: Date
    let width: CGFloat
    let numberSize: CGFloat
    let caption: String?
    let captionSize: CGFloat

    var body: some View {
        let pace = window.elapsedFraction(now: now)
        if let caption {
            ArcGauge(percent: window.usedPercent, pace: pace, width: width, numberSize: numberSize, caption: " ", provider: window.provider)
                .overlay(alignment: .bottom) {
                    Text(caption).font(.system(size: captionSize, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize()
                }
        } else {
            ArcGauge(percent: window.usedPercent, pace: pace, width: width, numberSize: numberSize, provider: window.provider)
        }
    }
}

/// A clock and the reset time, bare ("12:38 PM") or prefixed ("Resets 12:38 PM", time in bold).
/// A window with no reset time keeps the line's height so cards line up, and shows nothing.
private struct GaugeReset: View {
    let window: UsageWindow?
    let now: Date
    let size: CGFloat
    let iconSize: CGFloat
    let spacing: CGFloat
    var prefixed = false

    /// Bare lines sit in narrow columns, so a reset more than a week out drops its time ("Oct 16").
    private var time: String? {
        guard let full = Format.resetTime(window?.resetsAt, now: now) else { return nil }
        return !prefixed && full.contains(",") ? Format.resetsCompact(window?.resetsAt, now: now) : full
    }

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: "clock").font(.system(size: iconSize))
            if prefixed {
                Text("Resets \(Text(time ?? "").fontWeight(.semibold).foregroundStyle(.primary))")
            } else {
                Text(time ?? " ")
            }
        }
        .font(.system(size: size))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .opacity(time == nil ? 0 : 1)
    }
}

/// A row of the small widgets: name (or label) over the reset on the left, the gauge on the right.
/// The name may run into the empty top-left corner of the gauge's box rather than truncate.
private struct GaugeSideRow<Name: View, Reset: View, Gauge: View>: View {
    let gaugeWidth: CGFloat
    let gap: CGFloat
    let whoSpacing: CGFloat
    @ViewBuilder let name: () -> Name
    @ViewBuilder let reset: () -> Reset
    @ViewBuilder let gauge: () -> Gauge

    var body: some View {
        ZStack(alignment: .leading) {
            gauge().frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: whoSpacing) {
                name()
                reset().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, gaugeWidth + gap)
            }
        }
    }
}

/// A provider with no windows: its weekly spend where the gauge would be, or a short muted note.
private struct GaugeNoLimits: View {
    let provider: ProviderSnapshot
    let fontSize: CGFloat

    init(_ provider: ProviderSnapshot, fontSize: CGFloat) {
        self.provider = provider
        self.fontSize = fontSize
    }

    var body: some View {
        let spend = provider.weeklySpend
        if spend.tokens.total > 0 || spend.costUSD > 0 {
            VStack(spacing: 1) {
                Text(Format.tokens(spend.tokens.total)).font(.system(size: fontSize, weight: .semibold))
                Text(Format.usd(spend)).font(.system(size: fontSize * 0.8, weight: .semibold)).foregroundStyle(.secondary)
            }
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        } else {
            Text(provider.accountKind == .metered ? "Metered, no limits" : "No limits yet")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// A card on the widget ground: lighter than it in dark mode. The light ground is near white, so a
/// lighter card would vanish; there the card is a faint shade darker instead.
private struct GaugeCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045))
    }
}
