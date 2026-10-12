import SwiftUI
import TokenometerCore

/// The Bars widget: status-colored bars in provider cards. Small, medium, large; one, two, or three
/// providers (`providers` empty means all). Every size opens with a header row: what it shows on the
/// left ("Session", "Session and weekly", or the one provider's logo and name), "as of" on the right.
/// Fixed sizes and columns from the approved mockup, no `ViewThatFits`; the widget supplies the frame
/// and the container background, this view draws its own padding.
public struct BarsWidgetView: View {
    public enum Size { case small, medium, large }

    let snapshot: Snapshot?
    let size: Size
    let providers: Set<Provider>
    let now: Date

    public init(snapshot: Snapshot?, size: Size, providers: Set<Provider> = [], now: Date = .now) {
        self.snapshot = snapshot
        self.size = size
        self.providers = providers
        self.now = now
    }

    private var shown: [ProviderSnapshot] {
        guard let snapshot else { return [] }
        return snapshot.providers.filter { providers.isEmpty || providers.contains($0.provider) }
    }

    public var body: some View {
        Group {
            if let snapshot, !shown.isEmpty {
                BarsLayout(snapshot: snapshot, shown: shown, size: size, now: now)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 22))
                    Text("Open Tokenometer to start collecting")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.statusPalette, PaletteChoice(rawValue: snapshot?.palette ?? "")?.palette ?? .standard)
    }
}

// MARK: - Layouts

private struct BarsLayout: View {
    let snapshot: Snapshot
    let shown: [ProviderSnapshot]
    let size: BarsWidgetView.Size
    let now: Date
    @Environment(\.statusPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    private static let cardFill = Color.primary.opacity(0.07)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 11)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch (size, shown.count) {
        case (.small, 1): small1(shown[0])
        case (.small, 2): small2
        case (.small, _): small3
        case (.medium, 1): medium1(shown[0])
        case (.medium, 2): mediumTable(two: true)
        case (.medium, _): mediumTable(two: false)
        case (.large, 1): large1(shown[0])
        case (.large, 2): large2
        case (.large, _): large3
        }
    }

    // MARK: Header

    private var asOf: some View {
        Text("as of \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
            .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
    }

    @ViewBuilder
    private var header: some View {
        if shown.count == 1 {
            let p = shown[0]
            let compact = size == .small
            HStack(spacing: compact ? 6 : 8) {
                HStack(spacing: compact ? 4 : 5) {
                    ProviderTile(p.provider, size: compact ? 16 : 18)
                    Text(p.shortName).font(.system(size: compact ? 12.5 : 13, weight: .bold)).lineLimit(1).fixedSize()
                }
                Spacer(minLength: 0)
                asOf
            }
            .frame(height: 18)
            .padding(.horizontal, compact ? 0 : 2)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(size == .small ? "Session" : "Session and weekly").font(.system(size: 13, weight: .bold)).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                asOf
            }
            .frame(height: 16)
            .padding(.horizontal, 2)
        }
    }

    // MARK: Small

    /// Three providers: name and session percent, then the bar with a bare reset time.
    private var small3: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, p in
                if index > 0 { Spacer(minLength: 0) }
                let row = sessionRow(p)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        ProviderTile(p.provider, size: 18)
                        Text(p.shortName).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let row { pct(row.window, size: 14) }
                    }
                    .frame(height: 18)
                    HStack(spacing: 6) {
                        if let row {
                            bar(row.window, p, height: 6)
                            BarsReset(date: row.window.resetsAt, now: now, size: 10.5, icon: 11, gap: 3).fixedSize()
                        } else {
                            noLimits(p, size: 10.5)
                        }
                    }
                    .frame(height: 16)
                }
            }
        }
        .padding(.top, 2)
    }

    /// Two providers: the same rows, larger, with "Resets" spelled out.
    private var small2: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, p in
                if index > 0 { Spacer(minLength: 0) }
                let row = sessionRow(p)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        ProviderTile(p.provider, size: 18)
                        Text(p.shortName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let row { pct(row.window, size: 18) }
                    }
                    .frame(height: 22)
                    if let row {
                        bar(row.window, p, height: 10).padding(.vertical, 2)
                        BarsReset(date: row.window.resetsAt, now: now, size: 11.5, icon: 12, gap: 4, prefixed: true)
                    } else {
                        noLimits(p, size: 11.5).padding(.top, 4)
                    }
                }
            }
        }
    }

    /// One provider: each window on its own row, three at most; two rows get the roomier type.
    @ViewBuilder
    private func small1(_ p: ProviderSnapshot) -> some View {
        let all = p.windowRows
        let rows = all.count > 3 ? Array(all.prefix(2)) : all
        let roomy = rows.count <= 2
        if rows.isEmpty {
            spendBlock(p).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            label(row.label, size: roomy ? 13.5 : 12.5)
                            Spacer(minLength: 0)
                            pct(row.window, size: roomy ? 18 : 14)
                        }
                        if roomy {
                            bar(row.window, p, height: 9).padding(.vertical, 2)
                            BarsReset(date: row.window.resetsAt, now: now, size: 11, icon: 12, gap: 4, prefixed: true)
                        } else {
                            HStack(spacing: 6) {
                                bar(row.window, p, height: 7)
                                BarsReset(date: row.window.resetsAt, now: now, size: 10.5, icon: 11, gap: 3)
                                    .frame(minWidth: 72, alignment: .trailing).fixedSize()
                            }
                            .frame(height: 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: Medium

    /// Two or three providers: a header line, then a card per provider with session and weekly columns.
    private func mediumTable(two: Bool) -> some View {
        let nameWidth: CGFloat = two ? 96 : 88
        let inset: CGFloat = two ? 10 : 8
        return VStack(alignment: .leading, spacing: two ? 4 : 3) {
            HStack(spacing: 12) {
                Text("Provider").frame(width: nameWidth, alignment: .leading)
                Text("Session").frame(maxWidth: .infinity, alignment: .leading)
                Text("Weekly").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            .frame(height: 13)
            .padding(.horizontal, inset)
            ForEach(shown) { p in
                HStack(spacing: 12) {
                    Group {
                        if two {
                            VStack(alignment: .leading, spacing: 3) {
                                providerName(p, nameSize: 14, gap: 6)
                                Text("Week \(spendText(p))")
                                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                            }
                        } else {
                            providerName(p, nameSize: 12.5, gap: 6)
                        }
                    }
                    .frame(width: nameWidth, alignment: .leading)
                    if p.windowRows.isEmpty {
                        noLimits(p, size: two ? 11 : 10.5).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        mediumCell(p.windowRows.first { $0.role == .session }, p, two: two)
                        mediumCell(p.windowRows.first { $0.role == .weekly }, p, two: two)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.vertical, two ? 4 : 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.cardFill))
            }
        }
    }

    @ViewBuilder
    private func mediumCell(_ row: WindowRow?, _ p: ProviderSnapshot, two: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            if let row {
                HStack(spacing: 6) {
                    bar(row.window, p, height: two ? 8 : 6).padding(.top, two ? 1 : 0)
                    pct(row.window, size: two ? 15 : 12.5).frame(minWidth: two ? 36 : 31, alignment: .trailing).fixedSize()
                }
                BarsReset(date: row.window.resetsAt, now: now, size: two ? 11 : 10.5, icon: 11, gap: two ? 4 : 5)
            } else {
                Text("None").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// One provider: a cell per window. Two windows are two big cells; three put the first big on
    /// the left and the other two stacked on the right; four are a two by two grid of small cells.
    @ViewBuilder
    private func medium1(_ p: ProviderSnapshot) -> some View {
        let rows = p.windowRows
        switch rows.count {
        case 0:
            spendBlock(p).padding(.horizontal, 11).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).background(card)
        case 1:
            bigCell(rows[0], p)
        case 2:
            BarsColumns { bigCell(rows[0], p); bigCell(rows[1], p) }
        case 3:
            BarsColumns {
                bigCell(rows[0], p)
                VStack(spacing: 6) { smallCell(rows[1], p, labelSize: 12); smallCell(rows[2], p, labelSize: 12) }
            }
        default:
            VStack(spacing: 6) {
                BarsColumns { smallCell(rows[0], p, labelSize: 11.5); smallCell(rows[1], p, labelSize: 11.5) }
                BarsColumns { smallCell(rows[2], p, labelSize: 11.5); smallCell(rows[3], p, labelSize: 11.5) }
            }
        }
    }

    private func bigCell(_ row: WindowRow, _ p: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                label(row.label, size: 13.5)
                pct(row.window, size: 30).frame(height: 30)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                bar(row.window, p, height: 10).padding(.top, -3).padding(.bottom, 3)
                BarsReset(date: row.window.resetsAt, now: now, size: 11.5, icon: 12, gap: 4, prefixed: true)
                if row.role == .session, let remaining = Format.remaining(row.window, now: now) {
                    Text(remaining).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card)
    }

    private func smallCell(_ row: WindowRow, _ p: ProviderSnapshot, labelSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                label(row.label, size: labelSize)
                Spacer(minLength: 0)
                pct(row.window, size: 15)
            }
            HStack(spacing: 6) {
                bar(row.window, p, height: 7).padding(.vertical, 1)
                BarsReset(date: row.window.resetsAt, now: now, size: 10.5, icon: 11, gap: 4)
                    .frame(minWidth: 74, alignment: .trailing).fixedSize()
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(card)
    }

    // MARK: Large

    /// Cards share the height in proportion to their weight, as the mockup's flex-grow does.
    private func proportional(_ weights: [Double], @ViewBuilder card: @escaping (Int) -> some View) -> some View {
        GeometryReader { geo in
            let total = weights.reduce(0, +)
            let free = geo.size.height - 6 * CGFloat(max(weights.count - 1, 0))
            VStack(spacing: 6) {
                ForEach(weights.indices, id: \.self) { index in
                    card(index).frame(height: max(0, free * weights[index] / total))
                }
            }
        }
    }

    /// Three providers: every window as a one-line row, weekly spend on the card.
    private var large3: some View {
        proportional(shown.map { Double(max($0.windowRows.count, 1) + 1) }) { index in
            let p = shown[index]
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                largeCardHeader(p, nameSize: 13, spendSize: 11, height: 20)
                ForEach(p.windowRows) { row in
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Text(row.label).font(.system(size: 11.5)).lineLimit(1).minimumScaleFactor(0.85)
                            .frame(width: 116, alignment: .leading)
                        bar(row.window, p, height: 6)
                        pct(row.window, size: 12).frame(minWidth: 30, alignment: .trailing).fixedSize()
                        BarsReset(date: row.window.resetsAt, now: now, size: 10.5, icon: 11, gap: 5)
                            .frame(width: 86, alignment: .trailing)
                    }
                    .frame(height: 18)
                }
                if p.windowRows.isEmpty {
                    Spacer(minLength: 0)
                    noLimits(p, size: 11.5, showSpend: false).frame(maxWidth: .infinity, alignment: .leading).frame(height: 18)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            .padding(.horizontal, 10)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(card)
        }
    }

    /// Two providers: every window as a two-line row; roomier type when there are six rows or fewer.
    private var large2: some View {
        let roomy = shown.reduce(0) { $0 + $1.windowRows.count } <= 6
        return proportional(shown.map { Double(max($0.windowRows.count, 1)) + 0.8 }) { index in
            let p = shown[index]
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                largeCardHeader(p, nameSize: 14, spendSize: 11.5, height: 22)
                ForEach(p.windowRows) { row in
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(row.label).font(.system(size: roomy ? 13.5 : 12.5, weight: roomy ? .semibold : .medium))
                                .lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 0)
                            pct(row.window, size: roomy ? 16 : 13.5)
                        }
                        .frame(height: roomy ? 20 : 16)
                        HStack(spacing: 10) {
                            bar(row.window, p, height: roomy ? 9 : 7)
                            BarsReset(date: row.window.resetsAt, now: now, size: roomy ? 11.5 : 11, icon: 11, gap: 4)
                                .frame(width: 86, alignment: .trailing)
                        }
                        .frame(height: roomy ? 16 : 14)
                    }
                }
                if p.windowRows.isEmpty {
                    Spacer(minLength: 0)
                    noLimits(p, size: 12, showSpend: false).frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .padding(.horizontal, 11)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(card)
        }
    }

    private func largeCardHeader(_ p: ProviderSnapshot, nameSize: CGFloat, spendSize: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 7) {
            providerName(p, nameSize: nameSize, gap: 7)
            Spacer(minLength: 6)
            Text("This week \(Text(spendText(p)).fontWeight(.semibold).foregroundStyle(.primary))")
                .font(.system(size: spendSize).monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(height: height)
    }

    /// One provider: a card per window plus a weekly spend card. With an even number of windows the
    /// spend card spans the bottom; with an odd number it takes the last cell and the type grows.
    @ViewBuilder
    private func large1(_ p: ProviderSnapshot) -> some View {
        let rows = p.windowRows
        let spanSpend = !rows.isEmpty && rows.count % 2 == 0
        let tall = !spanSpend
        let cells: [BarsLargeCell] = rows.map { .window($0) } + (spanSpend ? [] : [.spend])
        VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { start in
                BarsColumns {
                    largeCell(cells[start], p, tall: tall)
                    if start + 1 < cells.count { largeCell(cells[start + 1], p, tall: tall) }
                }
                .frame(maxHeight: .infinity)
            }
            if spanSpend { wideSpendCard(p) }
        }
    }

    @ViewBuilder
    private func largeCell(_ cell: BarsLargeCell, _ p: ProviderSnapshot, tall: Bool) -> some View {
        switch cell {
        case .window(let row):
            VStack(alignment: .leading, spacing: 0) {
                label(row.label, size: 13)
                Spacer(minLength: 0)
                pct(row.window, size: tall ? 42 : 30).frame(height: tall ? 42 : 30)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    bar(row.window, p, height: tall ? 12 : 11).padding(.vertical, 3)
                    BarsReset(date: row.window.resetsAt, now: now, size: 11.5, icon: 12, gap: 4, prefixed: true)
                }
            }
            .padding(.top, 9).padding(.horizontal, 11).padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(card)
        case .spend:
            VStack(alignment: .leading, spacing: 0) {
                Text("This week").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                if p.windowRows.isEmpty {
                    Text(p.accountKind == .metered ? "Metered, no limits" : "No usage limits")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                spendFigure(Format.usd(p.weeklySpend), caption: "API price", size: tall ? 30 : 24)
                Spacer(minLength: 0)
                spendFigure(Format.tokens(p.weeklySpend.tokens.total), caption: "tokens", size: tall ? 30 : 24)
            }
            .padding(.top, 9).padding(.horizontal, 11).padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(card)
        }
    }

    private func spendFigure(_ value: String, caption: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: size, weight: .semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func wideSpendCard(_ p: ProviderSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("This week").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.tokens(p.weeklySpend.tokens.total)).font(.system(size: 20, weight: .semibold).monospacedDigit())
                Text("tokens").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.usd(p.weeklySpend)).font(.system(size: 20, weight: .semibold).monospacedDigit())
                Text("API price").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .padding(.vertical, 8)
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .background(card)
    }

    // MARK: Pieces

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.cardFill)
    }

    /// The session window, or the first window there is when a provider reports no session.
    private func sessionRow(_ p: ProviderSnapshot) -> WindowRow? {
        p.windowRows.first { $0.role == .session } ?? p.windowRows.first
    }

    private func providerName(_ p: ProviderSnapshot, nameSize: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            ProviderTile(p.provider, size: 18)
            Text(p.shortName).font(.system(size: nameSize, weight: .semibold)).lineLimit(1)
        }
    }

    private func label(_ text: String, size: CGFloat) -> some View {
        Text(text).font(.system(size: size, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
    }

    private func pct(_ window: UsageWindow, size: CGFloat) -> some View {
        Text(Format.percent(window.usedPercent))
            .font(.system(size: size, weight: .semibold).monospacedDigit())
            .foregroundStyle(palette.color(UsageStatus.of(percent: window.usedPercent, pace: window.elapsedFraction(now: now)), scheme))
            .lineLimit(1).fixedSize()
    }

    /// Stale windows keep their last value, dimmed.
    private func bar(_ window: UsageWindow, _ p: ProviderSnapshot, height: CGFloat) -> some View {
        StatusBar(percent: window.usedPercent, pace: window.elapsedFraction(now: now), height: height)
            .opacity(p.windowsStale == nil ? 1 : 0.6)
    }

    private func hasSpend(_ p: ProviderSnapshot) -> Bool {
        p.weeklySpend.tokens.total > 0 || p.weeklySpend.costUSD > 0
    }

    /// "22M · $38.10"; "$?" when nothing was priceable.
    private func spendText(_ p: ProviderSnapshot) -> String {
        "\(Format.tokens(p.weeklySpend.tokens.total)) · \(Format.usd(p.weeklySpend))"
    }

    /// A provider with no windows (a metered account): its weekly spend in place of the bars.
    private func noLimits(_ p: ProviderSnapshot, size: CGFloat, showSpend: Bool = true) -> some View {
        let text = showSpend && hasSpend(p) ? "This week \(spendText(p))" : (p.accountKind == .metered ? "Metered, no limits" : "No usage limits")
        return Text(text).font(.system(size: size).monospacedDigit()).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.85)
    }

    private func spendBlock(_ p: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.accountKind == .metered ? "Metered, no limits" : "No usage limits")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            if hasSpend(p) {
                Text("This week").font(.system(size: 11.5)).foregroundStyle(.secondary)
                Text(spendText(p)).font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

/// Columns of equal width that fill the proposed size, like the mockup's `1fr 1fr` grid: content
/// never widens one column at the other's expense.
private struct BarsColumns: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                          proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

private enum BarsLargeCell {
    case window(WindowRow)
    case spend
}

/// A clock glyph and the reset time: bare ("12:38 PM", "Wed 7:49 PM") or "Resets 12:38 PM" with the
/// time in bold. Nothing when the window has no reset time.
private struct BarsReset: View {
    let date: Date?
    let now: Date
    let size: CGFloat
    let icon: CGFloat
    let gap: CGFloat
    var prefixed = false

    var body: some View {
        if let time = Format.resetTime(date, now: now) {
            HStack(spacing: gap) {
                Image(systemName: "clock").font(.system(size: icon - 1))
                if prefixed {
                    Text("Resets \(Text(time).fontWeight(.semibold).foregroundStyle(.primary))")
                } else {
                    Text(time)
                }
            }
            .font(.system(size: size).monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }
}
