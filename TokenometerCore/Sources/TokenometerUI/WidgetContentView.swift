import SwiftUI
import TokenometerCore

/// The whole widget body for each family. Shared by the extension and the mockup renderer.
/// Each size draws at the largest type scale that fits, and the large size drops its reset times
/// before it gives up; `ViewThatFits` does the choosing.
public struct WidgetContentView: View {
    public enum Size { case small, medium, large }

    let snapshot: Snapshot?
    let size: Size
    let now: Date

    public init(snapshot: Snapshot?, size: Size, now: Date = .now) {
        self.snapshot = snapshot
        self.size = size
        self.now = now
    }

    /// Type scales tried largest first. A widget with one provider or few windows has room to
    /// spare, and 10pt type in it reads small beside the system's own widgets.
    static let scales: [CGFloat] = [1.4, 1.3, 1.2, 1.1, 1]

    public var body: some View {
        if let snapshot, !snapshot.providers.isEmpty {
            // First that fits, on both axes: the roomy layout at the largest scale that holds it,
            // then the tighter layout, which is also what draws when nothing fits.
            ViewThatFits {
                ForEach(Self.scales, id: \.self) { layout(snapshot, roomy: true, scale: $0) }
                layout(snapshot, roomy: false, scale: 1)
            }
        } else {
            VStack {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.title2)
                Text("Open Tokenometer").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// `roomy` is each size's preferred layout: reset times shown, on their own line in the medium.
    @ViewBuilder
    private func layout(_ snapshot: Snapshot, roomy: Bool, scale: CGFloat) -> some View {
        Group {
            switch size {
            case .small: small(snapshot, resets: true, scale: scale)
            case .medium: medium(snapshot, resets: .below, scale: scale)
            case .large: large(snapshot, resets: roomy, scale: scale)
            }
        }
        .environment(\.widgetScale, scale)
    }

    /// Name, session percent, a thin session bar, and optionally its reset time.
    private func small(_ snapshot: Snapshot, resets: Bool, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Spacer(minLength: 0)
            ForEach(snapshot.providers) { provider in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Circle().fill(provider.provider.color).frame(width: 6 * scale, height: 6 * scale)
                        Text(provider.provider.displayName).font(.widget(scale).bold()).lineLimit(1).fixedSize()
                        Spacer()
                        if let session = provider.session {
                            Text(Format.percent(session.usedPercent)).font(.widget(scale).monospacedDigit().bold())
                                .foregroundStyle(tint(session, provider))
                        }
                    }
                    if let session = provider.session {
                        MiniHorizontalBar(percent: session.usedPercent, base: provider.provider.color, pace: session.elapsedFraction(now: now))
                        if resets, let text = Format.resetsShort(session.resetsAt, now: now) {
                            Text(text).font(.widget(scale)).foregroundStyle(.secondary).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            footer(snapshot, scale: scale)
        }
    }

    enum MediumResets { case below, inline, none }

    /// One row per provider: name, session bar, weekly bar, with column titles once at the top.
    /// Reset times go on a second line under each column when the height allows, else beside the percent.
    private func medium(_ snapshot: Snapshot, resets: MediumResets, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: resets == .below ? 4 : 6) {
            HStack(spacing: 8) {
                Text("").frame(width: 72 * scale, alignment: .leading)
                Text("Session").font(.widget(scale)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Text("Weekly").font(.widget(scale)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            ForEach(snapshot.providers) { provider in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .center, spacing: 8) {
                        HStack(spacing: 4) {
                            Circle().fill(provider.provider.color).frame(width: 6 * scale, height: 6 * scale)
                            Text(provider.provider.displayName).font(.widget(scale).bold()).lineLimit(1)
                        }
                        .frame(width: 72 * scale, alignment: .leading)
                        cell(provider.session, provider: provider, resets: resets == .inline, scale: scale)
                        cell(provider.weekly, provider: provider, resets: resets == .inline, scale: scale)
                    }
                    if resets == .below {
                        HStack(spacing: 8) {
                            Text("").frame(width: 72 * scale)
                            resetLine(provider.session, beside: provider.weekly, scale: scale)
                            resetLine(provider.weekly, beside: provider.session, scale: scale)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            footer(snapshot, scale: scale)
        }
    }

    private func resetLine(_ window: UsageWindow?, beside other: UsageWindow?, scale: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            // The two columns split the width equally, so each must hold the wider of the two texts.
            // A hidden copy of the other one lets the fit test see that and step the scale down.
            Text(Format.resetsShort(other?.resetsAt, now: now) ?? " ").hidden()
            Text(Format.resetsShort(window?.resetsAt, now: now) ?? " ")
        }
        .font(.widget(scale)).foregroundStyle(.secondary).lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func cell(_ window: UsageWindow?, provider: ProviderSnapshot, resets: Bool, scale: CGFloat) -> some View {
        HStack(spacing: 5) {
            if let window {
                MiniHorizontalBar(percent: window.usedPercent, base: provider.provider.color, pace: window.elapsedFraction(now: now))
                    .frame(minWidth: 30, idealWidth: 30)
                Text(Format.percent(window.usedPercent)).font(.widget(scale).monospacedDigit().bold())
                    .foregroundStyle(tint(window, provider))
                    .frame(width: 28 * scale, alignment: .trailing)
                if resets, let text = Format.resetsCompact(window.resetsAt, now: now) {
                    Text(text).font(.widget(scale)).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 44 * scale, alignment: .trailing)
                }
            } else {
                Text("—").font(.widget(scale)).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Every window as a compact labeled row with its reset time, plus spend.
    private func large(_ snapshot: Snapshot, resets: Bool, scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            ForEach(snapshot.providers) { provider in
                WidgetProviderView(snapshot: provider, size: .large, showsResets: resets, now: now)
                Spacer(minLength: 0)
            }
            footer(snapshot, scale: scale)
        }
    }

    private func tint(_ window: UsageWindow, _ provider: ProviderSnapshot) -> Color {
        UsageLevel.tint(for: window.usedPercent, base: provider.provider.color, pace: window.elapsedFraction(now: now))
    }

    private func footer(_ snapshot: Snapshot, scale: CGFloat) -> some View {
        HStack {
            Spacer()
            Text("as of \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))").font(.widget(scale)).foregroundStyle(.secondary)
        }
    }
}
