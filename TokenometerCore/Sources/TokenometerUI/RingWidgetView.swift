import SwiftUI
import TokenometerCore

/// The rings widget: one session ring per provider, percent inside, name and reset time under it.
/// The large adds a second row of weekly rings. With one provider chosen, the small draws its
/// session ring large and the medium and large add its weekly ring beside it.
///
/// Every size has the same bones: a 12pt header line on the top padding (the provider's name for
/// one provider, the row's window otherwise), the rings 6pt under it so they start at the same y
/// in every variant, and in the medium and large an "as of" footer at the bottom right. The
/// medium's 132pt holds header, a 64pt ring with name and reset, and the footer with 6pt over;
/// a 72pt ring does not fit, so every medium ring is 64.
/// Shared by the extension and the mockup renderer.
public struct RingWidgetView: View {
    public enum Size { case small, medium, large }

    let snapshot: Snapshot?
    let size: Size
    /// The providers to show; empty means every provider in the snapshot.
    let providers: Set<Provider>
    let style: SessionRingStyle
    let now: Date

    public init(snapshot: Snapshot?, size: Size, providers: Set<Provider> = [], style: SessionRingStyle = .ring, now: Date = .now) {
        self.snapshot = snapshot
        self.size = size
        self.providers = providers
        self.style = style
        self.now = now
    }

    private var shown: [ProviderSnapshot] {
        (snapshot?.providers ?? []).filter { providers.isEmpty || providers.contains($0.provider) }
    }

    public var body: some View {
        if shown.isEmpty {
            VStack {
                Image(systemName: "gauge.with.dots.needle.33percent").font(.title2)
                Text(providers.isEmpty ? "Open Tokenometer" : "No \(providers.sorted { $0.rawValue < $1.rawValue }.map(\.displayName).joined(separator: ", ")) data")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } else if shown.count == 1, let only = shown.first {
            single(only)
        } else if size == .large {
            rows(shown)
        } else {
            row(shown)
        }
    }

    /// Ring diameter for a row of `columns` rings at this size.
    private func ring(columns: Int) -> CGFloat {
        switch (size, columns) {
        case (.small, 1): 88
        case (.small, 2): 52
        case (.small, _): 40
        default: 64
        }
    }

    /// One provider: its session ring, large; the medium and large pair it with the weekly ring.
    private func single(_ provider: ProviderSnapshot) -> some View {
        let small = size == .small
        // The large has the height for two 120pt rings; the others take the two-column size.
        let diameter: CGFloat = size == .large ? 120 : ring(columns: small ? 1 : 2)
        return VStack(spacing: 0) {
            header {
                Circle().fill(provider.provider.color).frame(width: 7, height: 7)
                Text(provider.provider.displayName).font(.system(size: 12, weight: .semibold))
                if !small, let plan = provider.planName {
                    Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: small ? 0 : 48) {
                column(provider.session, label: small ? nil : "Session", provider: provider, ring: diameter, resets: true)
                if !small {
                    column(provider.weekly, label: "Weekly", provider: provider, ring: diameter, resets: true)
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
            if !small { footer }
        }
    }

    /// Two or three providers side by side under a "Session" row label, product names in the
    /// small, company names in the medium. Three columns in the small are 44pt each, too narrow
    /// for a reset time.
    private func row(_ providers: [ProviderSnapshot]) -> some View {
        let small = size == .small
        let diameter = ring(columns: providers.count)
        return VStack(spacing: 0) {
            header { Text("Session").font(.system(size: 10)).foregroundStyle(.secondary) }
            HStack(alignment: .top, spacing: small ? 6 : 24) {
                ForEach(providers) { provider in
                    column(provider.session, label: small ? provider.provider.shortName : provider.provider.displayName,
                           provider: provider, ring: diameter, resets: !small || providers.count < 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
            if !small { footer }
        }
    }

    /// The large with several providers: a row of session rings over a row of weekly rings, the
    /// provider named under its session ring, each row labelled at the left.
    private func rows(_ providers: [ProviderSnapshot]) -> some View {
        VStack(spacing: 0) {
            ringRow("Session", providers: providers, window: \.session, named: true)
            Spacer(minLength: 0)
            ringRow("Weekly", providers: providers, window: \.weekly, named: false)
            Spacer(minLength: 0)
            footer
        }
    }

    private func ringRow(_ title: String, providers: [ProviderSnapshot], window: KeyPath<ProviderSnapshot, UsageWindow?>, named: Bool) -> some View {
        VStack(spacing: 6) {
            header { Text(title).font(.system(size: 10)).foregroundStyle(.secondary) }
            HStack(alignment: .top, spacing: 12) {
                ForEach(providers) { provider in
                    column(provider[keyPath: window], label: named ? provider.provider.displayName : nil, provider: provider, ring: ring(columns: providers.count), resets: true)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// The line on the top padding: left-aligned, 12pt whatever it holds, so the rings under it
    /// start at the same y in every variant.
    private func header<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 4) {
            content()
            Spacer(minLength: 0)
        }
        .frame(height: 12)
    }

    /// A ring with the percent inside, then the label and optionally the reset time under it.
    /// Type follows the ring: percent 10 to 28pt, captions 9pt under a 52pt ring and 10pt above.
    private func column(_ window: UsageWindow?, label: String?, provider: ProviderSnapshot, ring: CGFloat, resets: Bool) -> some View {
        let tint = UsageLevel.tint(for: window?.usedPercent ?? 0, base: provider.provider.color, pace: window?.elapsedFraction(now: now))
        let percent: CGFloat = switch ring { case ..<52: 10; case ..<64: 13; case ..<72: 15; case ..<88: 17; case ..<120: 20; default: 28 }
        let caption: CGFloat = ring < 64 ? 9 : 10
        return VStack(spacing: 4) {
            SessionRing(window: window, base: provider.provider.color, style: style, lineWidth: ring > 60 ? 7 : 5, now: now) {
                Text(window.map { Format.percent($0.usedPercent) } ?? "—")
                    .font(.system(size: percent, weight: .semibold).monospacedDigit())
                    .foregroundStyle(window == nil ? Color.secondary : tint)
            }
            .frame(width: ring, height: ring)
            .opacity(provider.windowsStale == nil ? 1 : 0.6)
            if let label {
                Text(label).font(.system(size: caption + 1, weight: .semibold)).lineLimit(1)
            }
            if resets {
                Text(Format.resetsShort(window?.resetsAt, now: now) ?? " ")
                    .font(.system(size: caption)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("as of \((snapshot?.generatedAt ?? now).formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
