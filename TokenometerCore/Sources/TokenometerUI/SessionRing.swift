import SwiftUI
import TokenometerCore

/// A circular session gauge, like the battery widget's rings: a track, the provider's color
/// filling it clockwise from the top, and the pace tick on the ring where the window's clock is.
/// `.ring` is the full circle; `.gauge` is a 240° arc open at the bottom, the speedometer's shape.
public enum SessionRingStyle { case ring, gauge }

public struct SessionRing<Center: View>: View {

    let window: UsageWindow?
    let base: Color
    let style: SessionRingStyle
    let lineWidth: CGFloat
    let now: Date
    let center: Center

    public init(window: UsageWindow?, base: Color, style: SessionRingStyle = .ring, lineWidth: CGFloat = 5, now: Date = .now, @ViewBuilder center: () -> Center) {
        self.window = window
        self.base = base
        self.style = style
        self.lineWidth = lineWidth
        self.now = now
        self.center = center()
    }

    private var percent: Double { min(max(window?.usedPercent ?? 0, 0), 100) }
    private var pace: Double? { window?.elapsedFraction(now: now) }
    private var fill: Color { UsageLevel.tint(for: percent, base: base, pace: pace) }
    /// Fraction of the circle the arc covers, and where it starts, clockwise from 3 o'clock: the
    /// ring at the top, the gauge at 7 o'clock so its opening is centered at the bottom.
    private var sweep: Double { style == .ring ? 1 : 2.0 / 3 }
    private var start: Angle { style == .ring ? .degrees(-90) : .degrees(150) }

    public var body: some View {
        ZStack {
            ZStack {
                Circle().trim(from: 0, to: sweep)
                    .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                // A sliver stays at 0% so the color is there to say whose ring it is.
                Circle().trim(from: 0, to: max(0.02, sweep * percent / 100))
                    .stroke(fill, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if let pace {
                    // Drawn at 3 o'clock (the arc's zero) and turned about the ring's center. Label
                    // color once the fill has passed the tick, provider color while ahead; as on the bars.
                    GeometryReader { geo in
                        Capsule()
                            .fill(percent / 100 >= pace ? Color.primary : base)
                            .frame(width: lineWidth + 4, height: 2)
                            .position(x: geo.size.width, y: geo.size.height / 2)
                    }
                    .rotationEffect(.degrees(360 * sweep * pace))
                }
            }
            .rotationEffect(start)
            center
        }
        .padding(lineWidth / 2)
        .aspectRatio(1, contentMode: .fit)
    }
}
