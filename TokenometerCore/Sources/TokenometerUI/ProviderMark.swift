import SwiftUI
import TokenometerCore

/// Neutral stand-ins for the providers' logos: a burst for Claude, a cloud with a prompt for Codex,
/// a four-point star for Gemini. Drawn as shapes so they scale, take the provider color, and carry
/// no trademarked artwork.
public struct ProviderGlyph: View {
    let provider: Provider

    public init(provider: Provider) { self.provider = provider }

    public var body: some View {
        switch provider {
        case .anthropic: BurstShape().stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round)).aspectRatio(1, contentMode: .fit)
        case .google: SparkleShape().fill().aspectRatio(1, contentMode: .fit)
        case .openAI: CloudPromptGlyph()
        }
    }
}

/// Eight rays from a small hole, in a 24 x 24 box; the stroke width scales with the view.
private struct BurstShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var p = Path()
        for i in 0..<8 {
            let a = Double(i) * .pi / 4
            let dx = cos(a), dy = sin(a)
            p.move(to: CGPoint(x: rect.minX + (12 + dx * 4.4) * s, y: rect.minY + (12 + dy * 4.4) * s))
            p.addLine(to: CGPoint(x: rect.minX + (12 + dx * 9) * s, y: rect.minY + (12 + dy * 9) * s))
        }
        return p
    }
}

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.move(to: pt(12, 2))
        p.addCurve(to: pt(22, 12), control1: pt(12.8, 8), control2: pt(16, 11.2))
        p.addCurve(to: pt(12, 22), control1: pt(16, 12.8), control2: pt(12.8, 16))
        p.addCurve(to: pt(2, 12), control1: pt(11.2, 16), control2: pt(8, 12.8))
        p.addCurve(to: pt(12, 2), control1: pt(8, 11.2), control2: pt(11.2, 8))
        p.closeSubpath()
        return p
    }
}

/// Seven overlapping circles make the cloud; a `>_` prompt is cut out of it.
private struct CloudPromptGlyph: View {
    private struct Cloud: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 24
            var p = Path()
            func circle(_ x: Double, _ y: Double, _ r: Double) {
                p.addEllipse(in: CGRect(x: rect.minX + (x - r) * s, y: rect.minY + (y - r) * s, width: 2 * r * s, height: 2 * r * s))
            }
            circle(12, 12, 7)
            for (x, y) in [(12.0, 6.4), (16.85, 9.2), (16.85, 14.8), (12.0, 17.6), (7.15, 14.8), (7.15, 9.2)] { circle(x, y, 4.2) }
            return p
        }
    }
    private struct Prompt: Shape {
        func path(in rect: CGRect) -> Path {
            let s = rect.width / 24
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
            var p = Path()
            p.move(to: pt(8.2, 9.6)); p.addLine(to: pt(11.2, 12.2)); p.addLine(to: pt(8.2, 14.8))
            p.move(to: pt(13, 15)); p.addLine(to: pt(16.4, 15))
            return p
        }
    }
    var body: some View {
        ZStack {
            Cloud().fill()
            GeometryReader { geo in
                Prompt().stroke(style: StrokeStyle(lineWidth: 1.8 * geo.size.width / 24, lineCap: .round, lineJoin: .round))
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A provider's logo tile: the glyph in the provider's color on a tint of it, rounded.
public struct ProviderTile: View {
    let provider: Provider
    let size: CGFloat

    public init(_ provider: Provider, size: CGFloat = 28) {
        self.provider = provider
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(provider.color.opacity(0.22))
            .frame(width: size, height: size)
            .overlay {
                ProviderGlyph(provider: provider)
                    .foregroundStyle(provider.color)
                    .frame(width: size * 0.6, height: size * 0.6)
            }
    }
}
