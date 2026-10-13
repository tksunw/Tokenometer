import SwiftUI
import TokenometerCore

/// A usage bar bent into a half circle, open at the bottom: the same rounded track and fill, the same
/// vertical pace tick, the percent set inside the arc. The fill is the status color (see `UsageStatus`).
/// Drawn in a 112 x 62 box scaled to `width`, so line weight and the tick scale with it.
public struct ArcGauge: View {
    let percent: Double
    let pace: Double?
    let width: CGFloat
    let numberSize: CGFloat
    let caption: String?
    let provider: Provider?
    @Environment(\.statusPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    public init(percent: Double, pace: Double?, width: CGFloat, numberSize: CGFloat, caption: String? = nil, provider: Provider? = nil) {
        self.percent = min(max(percent, 0), 100)
        self.pace = pace
        self.width = width
        self.numberSize = numberSize
        self.caption = caption
        self.provider = provider
    }

    private var height: CGFloat { width * 62 / 112 }
    private var fill: Color { palette.color(UsageStatus.of(percent: percent, pace: pace), scheme, provider: provider) }

    /// Left end to right end over the top; SwiftUI's arc direction is flipped by its y-down space.
    private func arc(_ fraction: Double) -> Path {
        let s = width / 112
        var p = Path()
        p.addArc(center: CGPoint(x: 56 * s, y: 56 * s), radius: 46 * s, startAngle: .degrees(180), endAngle: .degrees(180 + 180 * fraction), clockwise: false)
        return p
    }

    public var body: some View {
        let s = width / 112
        ZStack(alignment: .bottom) {
            ZStack {
                arc(1).stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
                arc(max(percent / 100, 0.0001)).stroke(fill, style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
                if let pace {
                    Path { p in
                        let a = Double.pi * (1 + min(max(pace, 0), 1))
                        let c = CGPoint(x: 56 * s, y: 56 * s)
                        p.move(to: CGPoint(x: c.x + cos(a) * 38 * s, y: c.y + sin(a) * 38 * s))
                        p.addLine(to: CGPoint(x: c.x + cos(a) * 54 * s, y: c.y + sin(a) * 54 * s))
                    }
                    .stroke(Color.primary.opacity(0.9), style: StrokeStyle(lineWidth: 2.4 * s, lineCap: .round))
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            VStack(spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int(percent.rounded()))").font(.system(size: numberSize, weight: .semibold).monospacedDigit())
                    Text("%").font(.system(size: numberSize * 0.5, weight: .medium)).opacity(0.8)
                }
                .foregroundStyle(fill)
                if let caption {
                    Text(caption).font(.system(size: max(9, numberSize * 0.42), weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(width: width, height: height + (caption == nil ? 0 : 0), alignment: .bottom)
    }
}

/// The status-colored bar for windows: a capsule track, a whole-fill in the status color, and the
/// vertical pace tick overhanging it.
public struct StatusBar: View {
    let percent: Double
    let pace: Double?
    let height: CGFloat
    let provider: Provider?
    @Environment(\.statusPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    public init(percent: Double, pace: Double?, height: CGFloat = 6, provider: Provider? = nil) {
        self.percent = min(max(percent, 0), 100)
        self.pace = pace
        self.height = height
        self.provider = provider
    }

    public var body: some View {
        let fill = palette.color(UsageStatus.of(percent: percent, pace: pace), scheme, provider: provider)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                // A sliver at 0% keeps the dot the mockups show, so an empty window still reads as a bar.
                Capsule().fill(fill).frame(width: max(height, geo.size.width * percent / 100))
            }
            .overlay(alignment: .leading) {
                if let pace {
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.9))
                        .frame(width: 2, height: height + 6)
                        .offset(x: geo.size.width * min(max(pace, 0), 1) - 1)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height + 6)
    }
}
