import SwiftUI
import TokenometerCore

/// The rings widget: one session ring per provider, percent inside, name and reset time under it.
/// The large adds a second row of weekly rings. With one provider chosen, the small draws its
/// session ring large and the medium and large add its weekly ring beside it.
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

    /// One provider: its session ring, large; the medium and large pair it with the weekly ring.
    /// Title at the left like every other provider name, "as of" at the bottom right like every
    /// other footer; the medium's rings are 72pt so both fit.
    private func single(_ provider: ProviderSnapshot) -> some View {
        let small = size == .small
        let ring: CGFloat = switch size { case .small: 88; case .medium: 72; case .large: 120 }
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(provider.provider.color).frame(width: 7, height: 7)
                Text(provider.provider.displayName).font(.system(size: 12, weight: .semibold))
                if !small, let plan = provider.planName {
                    Text(plan).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: small ? 0 : 48) {
                column(provider.session, label: small ? nil : "Session", provider: provider, ring: ring, percent: ring > 100 ? 28 : ring > 80 ? 20 : 17, caption: ring > 80 ? 11 : 10, resets: true)
                if !small {
                    column(provider.weekly, label: "Weekly", provider: provider, ring: ring, percent: ring > 100 ? 28 : 17, caption: 10, resets: true)
                }
            }
            Spacer(minLength: 0)
            if !small { HStack { Spacer(); asOf } }
        }
    }

    /// The large with several providers: a row of session rings over a row of weekly rings, the
    /// provider named under its session ring, the row named at the left.
    private func rows(_ providers: [ProviderSnapshot]) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ringRow("Session", providers: providers, window: \.session, named: true)
            Spacer(minLength: 0)
            ringRow("Weekly", providers: providers, window: \.weekly, named: false)
            Spacer(minLength: 0)
            HStack { Spacer(); asOf }
        }
    }

    private func ringRow(_ title: String, providers: [ProviderSnapshot], window: KeyPath<ProviderSnapshot, UsageWindow?>, named: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                ForEach(providers) { provider in
                    column(provider[keyPath: window], label: named ? provider.provider.displayName : nil, provider: provider, ring: 72, percent: 17, caption: 10, resets: true)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Two or three providers side by side, product names in the small, company names in the
    /// medium. Three columns in the small are 44pt each, too narrow for a reset time.
    private func row(_ providers: [ProviderSnapshot]) -> some View {
        let small = size == .small
        let ring: CGFloat = small ? (providers.count == 2 ? 52 : 40) : 64
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: small ? 6 : 24) {
                ForEach(providers) { provider in
                    column(provider.session, label: small ? provider.provider.shortName : provider.provider.displayName,
                           provider: provider, ring: ring, percent: small ? 10 : 15, caption: small ? 9 : 10, resets: !small || providers.count < 3)
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            if !small { HStack { Spacer(); asOf } }
        }
    }

    /// A ring with the percent inside, then the label and optionally the reset time under it.
    private func column(_ window: UsageWindow?, label: String?, provider: ProviderSnapshot, ring: CGFloat, percent: CGFloat, caption: CGFloat, resets: Bool) -> some View {
        let tint = UsageLevel.tint(for: window?.usedPercent ?? 0, base: provider.provider.color, pace: window?.elapsedFraction(now: now))
        return VStack(spacing: ring > 60 ? 6 : 3) {
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

    private var asOf: some View {
        Text("as of \((snapshot?.generatedAt ?? now).formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
    }
}
