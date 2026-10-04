import SwiftUI
import TokenometerCore

/// Horizontal percent bar with label, percent, reset time, and a pace marker showing how far through
/// the window the clock is. Used by the menu and the widget.
public struct UsageBarView: View {
    let label: String
    let window: UsageWindow
    let base: Color
    let stale: StaleInfo?
    let compact: Bool
    let showsReset: Bool
    let now: Date
    @Environment(\.widgetScale) private var scale

    public init(label: String, window: UsageWindow, base: Color, stale: StaleInfo? = nil, compact: Bool = false, showsReset: Bool = false, now: Date = .now) {
        self.label = label
        self.window = window
        self.base = base
        self.stale = stale
        self.compact = compact
        self.showsReset = showsReset
        self.now = now
    }

    private var pace: Double? { window.elapsedFraction(now: now) }
    /// "Claude & GPT session" -> "Claude & GPT 5h", "Gemini weekly" -> "Gemini wk". Widget rows only.
    private var compactLabel: String {
        label.replacingOccurrences(of: " session", with: " 5h").replacingOccurrences(of: " weekly", with: " wk")
    }
    private var fill: Color { UsageLevel.tint(for: window.usedPercent, base: base, pace: pace) }

    public var body: some View {
        if compact {
            // One row per window: label, bar, percent, and optionally the reset time. Widgets have
            // no room for stacked rows, so the reset costs width rather than height.
            HStack(spacing: 6) {
                Text(compactLabel).font(.widget(scale)).lineLimit(1).frame(width: 86 * scale, alignment: .leading)
                // The minimum keeps a larger type size from squeezing the bar to nothing; a scale
                // that cannot afford it does not fit, and the widget steps down.
                bar.frame(minWidth: 64, idealWidth: 64).frame(height: 5 * scale)
                Text(Format.percent(window.usedPercent)).font(.widget(scale).monospacedDigit().bold())
                    .foregroundStyle(fill).frame(width: 34 * scale, alignment: .trailing)
                if showsReset {
                    Text(Format.resetsCompact(window.resetsAt, now: now) ?? "")
                        .font(.widget(scale)).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 52 * scale, alignment: .trailing)
                }
            }
            .opacity(stale == nil ? 1 : 0.6)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label).font(.caption)
                    if stale != nil {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.secondary)
                            .help(stale.map { "Stale since \(Format.age($0.since)): \($0.reason)" } ?? "")
                    }
                    Spacer()
                    Text(Format.percent(window.usedPercent)).font(.caption.monospacedDigit().bold()).foregroundStyle(fill)
                }
                bar.frame(height: 6).padding(.vertical, 2)
                    .opacity(stale == nil ? 1 : 0.6)
                if let resets = Format.resets(window.resetsAt, now: now) {
                    Text(resets).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // The track and its outline are the label color, so the empty part reads in light and
                // dark whatever the provider's color; the color is the fill only.
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(fill)
                    .frame(width: geo.size.width * min(max(window.usedPercent, 0), 100) / 100)
                Capsule().strokeBorder(Color.primary.opacity(0.4), lineWidth: 0.5)
                if let pace {
                    // Label color (black in light, white in dark) once the fill has passed the tick; provider color while ahead.
                    RoundedRectangle(cornerRadius: 1)
                        .fill(window.usedPercent / 100 >= pace ? Color.primary : base)
                        .frame(width: 2, height: geo.size.height + 4)
                        .offset(x: geo.size.width * pace - 1, y: -2)
                        .help("\(Int((pace * 100).rounded()))% of the window has elapsed")
                }
            }
        }
    }
}

/// The menu bar's tiny vertical bar: one per provider, session window percent.
public struct MiniBar: View {
    let percent: Double
    let base: Color

    public init(percent: Double, base: Color) {
        self.percent = percent
        self.base = base
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1).fill(base.opacity(0.25))
                RoundedRectangle(cornerRadius: 1).fill(UsageLevel.tint(for: percent, base: base))
                    .frame(height: max(1, geo.size.height * min(max(percent, 0), 100) / 100))
            }
        }
        .frame(width: 5)
    }
}

extension EnvironmentValues {
    /// How much larger than its base size a widget draws its type and metrics. Widgets try the
    /// largest scale that fits (see `WidgetContentView`); everything else draws at 1.
    @Entry var widgetScale: CGFloat = 1
}

extension Font {
    /// Widget text: 10pt, the size of `.caption` on macOS, times the widget's scale.
    static func widget(_ scale: CGFloat) -> Font { .system(size: 10 * scale) }
}
