import AppKit
import SwiftUI
import TokenometerCore

/// How the menu bar item draws usage.
public enum MenuBarStyle: String, Codable, Sendable, CaseIterable {
    /// A speedometer: one hand per provider, staggered long to short, pointing at session usage.
    case gauge
    /// One tiny vertical bar per provider.
    case bars
    /// A single horizontal session bar with its percent, for one provider at a time.
    case horizontal
}

/// Which provider the horizontal style shows.
public enum MenuBarProviderChoice: String, Codable, Sendable, CaseIterable {
    case cycle
    case anthropic
    case openAI
    case google

    public var provider: Provider? {
        switch self {
        case .cycle: nil
        case .anthropic: .anthropic
        case .openAI: .openAI
        case .google: .google
        }
    }
}

/// Draws the menu bar item as an NSImage. MenuBarExtra rasterizes a custom SwiftUI label into a
/// template image, which drops color and gives GeometryReader-based views no size; an NSImage with
/// `isTemplate = false` keeps the provider colors and a fixed size.
public enum MenuBarImage {
    public static let height: CGFloat = 18

    /// `focus`, `showsWeekly`, and `palette` apply to the horizontal style only; the gauge and bars
    /// keep the provider's color, which is all that tells their hands and bars apart.
    public static func render(_ providers: [ProviderSnapshot], style: MenuBarStyle, focus: ProviderSnapshot? = nil,
                              showsWeekly: Bool = true, palette: StatusPalette = .trafficLight, now: Date = .now) -> NSImage {
        switch style {
        case .gauge: gauge(providers)
        case .bars: bars(providers)
        case .horizontal: horizontal(focus ?? providers[0], showsWeekly: showsWeekly, palette: palette, now: now)
        }
    }

    // MARK: Horizontal

    /// The provider's logo tile, then the session bar (and under it the weekly bar, when shown) with the
    /// session percent beside them. The menu bar is transparent over the wallpaper, so the background
    /// can be anything from white to black: each track has a white outline with a dark edge and the
    /// digits are white over a dark outline, so they read on either. The fill is the status color of
    /// the chosen palette, which is the provider's own color under the Provider palette.
    public static func horizontal(_ provider: ProviderSnapshot, showsWeekly: Bool = true, palette: StatusPalette = .trafficLight, now: Date = .now) -> NSImage {
        let tile: CGFloat = 15
        let barWidth: CGFloat = 40
        let textWidth: CGFloat = 26
        let weekly = showsWeekly ? provider.weekly : nil
        let session = provider.session
        // The size and shape of the system battery indicator when alone; two thinner bars when stacked.
        let barHeight: CGFloat = weekly == nil ? 11 : 7
        let radius: CGFloat = weekly == nil ? 3.5 : 2.5
        let barsX = tile + 5
        let width = barsX + barWidth + 4 + textWidth

        func fill(for window: UsageWindow?) -> NSColor {
            let percent = min(max(window?.usedPercent ?? 0, 0), 100)
            let status = UsageStatus.of(percent: percent, pace: window?.elapsedFraction(now: now))
            // The menu bar's own look follows the wallpaper, so the dark-mode shades are the ones that read.
            return NSColor(palette.color(status, .dark, provider: provider.provider))
        }

        func drawBar(_ window: UsageWindow?, y: CGFloat) {
            let percent = min(max(window?.usedPercent ?? 0, 0), 100)
            let track = NSRect(x: barsX, y: y, width: barWidth, height: barHeight)
            NSColor(white: 0, alpha: 0.25).setFill()
            NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
            // A sliver stays at 0% so the bar still reads as a bar.
            let inset: CGFloat = weekly == nil ? 2 : 1.25
            let inner = track.insetBy(dx: inset, dy: inset)
            fill(for: window).setFill()
            NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: max(3, inner.width * percent / 100), height: inner.height), xRadius: max(0.5, radius - inset), yRadius: max(0.5, radius - inset)).fill()
            // Two-tone outline: a dark edge outside a white core, so the empty end of the track still
            // reads as bar on any background.
            let edge = NSBezierPath(roundedRect: track.insetBy(dx: -0.5, dy: -0.5), xRadius: radius + 0.5, yRadius: radius + 0.5)
            edge.lineWidth = 1
            NSColor(white: 0, alpha: 0.55).setStroke()
            edge.stroke()
            let outline = NSBezierPath(roundedRect: track.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
            outline.lineWidth = 1
            NSColor.white.setStroke()
            outline.stroke()
            // The pace tick is two-tone the same way. Stacked bars are one point apart, so it overhangs less.
            if let pace = window?.elapsedFraction(now: now) {
                let x = barsX + barWidth * pace
                let over: CGFloat = weekly == nil ? 2 : 0.5
                NSColor(white: 0, alpha: 0.6).setFill()
                NSBezierPath(rect: NSRect(x: x - 1.5, y: y - over - 0.5, width: 3, height: barHeight + 2 * over + 1)).fill()
                NSColor.white.setFill()
                NSBezierPath(rect: NSRect(x: x - 0.75, y: y - over, width: 1.5, height: barHeight + 2 * over)).fill()
            }
        }

        let percent = min(max(session?.usedPercent ?? 0, 0), 100)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            drawLogoTile(provider.provider, in: NSRect(x: 0, y: (height - tile) / 2, width: tile, height: tile))
            if weekly != nil {
                // Session above weekly, one point between, centered in the bar's height.
                let gap: CGFloat = 2
                let stack = barHeight * 2 + gap
                let bottom = (height - stack) / 2
                drawBar(weekly, y: bottom)
                drawBar(session, y: bottom + barHeight + gap)
            } else {
                drawBar(session, y: (height - barHeight) / 2)
            }
            // White digits over a dark outline of the same glyphs; a soft shadow washes out on a light bar.
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let label = Format.percent(percent)
            let size = NSAttributedString(string: label, attributes: [.font: font]).size()
            let origin = NSPoint(x: barsX + barWidth + 4 + textWidth - size.width, y: (height - size.height) / 2)
            NSAttributedString(string: label, attributes: [.font: font, .strokeColor: NSColor(white: 0, alpha: 0.6), .strokeWidth: 22.0]).draw(at: origin)
            NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white]).draw(at: origin)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The provider's color as a rounded tile with its glyph in white, so it reads on any wallpaper.
    private static func drawLogoTile(_ provider: Provider, in rect: NSRect) {
        let color = NSColor(provider.color)
        // A dark edge outside the tile, like the bars' outline.
        let edge = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), xRadius: rect.width * 0.29 + 0.5, yRadius: rect.width * 0.29 + 0.5)
        edge.lineWidth = 1
        NSColor(white: 0, alpha: 0.55).setStroke()
        edge.stroke()
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.29, yRadius: rect.width * 0.29).fill()

        let glyphSize = rect.width * 0.68
        let glyph = CGRect(x: rect.midX - glyphSize / 2, y: rect.midY - glyphSize / 2, width: glyphSize, height: glyphSize)
        // The shapes are drawn y-down in a 24 unit box; flip them into AppKit's y-up space.
        var flip = CGAffineTransform(translationX: 0, y: glyph.minY + glyph.maxY).scaledBy(x: 1, y: -1)
        let paths = ProviderGlyphPaths.make(provider, in: glyph)
        NSColor.white.set()
        if let fill = paths.fill, let flipped = fill.copy(using: &flip) { NSBezierPath(cgPath: flipped).fill() }
        if let stroke = paths.stroke, let flipped = stroke.copy(using: &flip) {
            let path = NSBezierPath(cgPath: flipped)
            path.lineWidth = paths.strokeWidth
            path.lineCapStyle = .round
            path.stroke()
        }
        if let prompt = paths.prompt, let flipped = prompt.copy(using: &flip) {
            color.setStroke()
            let path = NSBezierPath(cgPath: flipped)
            path.lineWidth = paths.promptWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    // MARK: Gauge

    /// Like the other styles, the rim and hub are white with a dark edge, so they read on any
    /// wallpaper whatever the app's appearance; the menu bar's own look follows the wallpaper.
    public static func gauge(_ providers: [ProviderSnapshot]) -> NSImage {
        let width: CGFloat = 24
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let edge = NSColor(white: 0, alpha: 0.55)
            let center = NSPoint(x: width / 2, y: 3.5)
            let radius: CGFloat = 9.5

            // Rim: provider-neutral up to 75%, amber to 90%, red to 100%. Angles run 180° (0%) to 0° (100%).
            func arc(from startPercent: Double, to endPercent: Double, color: NSColor, width: CGFloat = 2) {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius, startAngle: 180 - 180 * startPercent / 100, endAngle: 180 - 180 * endPercent / 100, clockwise: true)
                path.lineWidth = width
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
            arc(from: 0, to: 100, color: edge, width: 3.5)
            arc(from: 0, to: UsageLevel.warning, color: .white)
            arc(from: UsageLevel.warning, to: UsageLevel.critical, color: .systemOrange)
            arc(from: UsageLevel.critical, to: 100, color: .systemRed)

            // Hands, staggered long to short in provider order.
            let lengths: [CGFloat] = [8.5, 7, 5.5]
            for (index, provider) in providers.prefix(3).enumerated() {
                let percent = min(max(provider.session?.usedPercent ?? 0, 0), 100)
                let angle = (180 - 180 * percent / 100) * .pi / 180
                let length = lengths[min(index, lengths.count - 1)]
                let tip = NSPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length)
                let hand = NSBezierPath()
                hand.move(to: center)
                hand.line(to: tip)
                hand.lineWidth = 2
                hand.lineCapStyle = .round
                NSColor(provider.provider.color).setStroke()
                hand.stroke()
            }

            // Hub.
            edge.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.75, y: center.y - 1.75, width: 3.5, height: 3.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Bars

    static let barWidth: CGFloat = 6
    static let gap: CGFloat = 4

    /// One vertical session bar per provider. Like the horizontal style, each track has a white
    /// outline with a dark edge so it reads on any wallpaper, and the provider's color is the fill.
    public static func bars(_ providers: [ProviderSnapshot]) -> NSImage {
        // One point of margin each side for the outline's dark edge.
        let width = CGFloat(providers.count) * barWidth + CGFloat(max(0, providers.count - 1)) * gap + 2
        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 1
            for provider in providers {
                let percent = min(max(provider.session?.usedPercent ?? 0, 0), 100)
                let fill = NSColor(UsageLevel.tint(for: percent, base: provider.provider.color, pace: provider.session?.elapsedFraction()))
                let track = NSRect(x: x, y: 1, width: barWidth, height: height - 2)
                NSColor(white: 0, alpha: 0.25).setFill()
                NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
                fill.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: barWidth, height: max(2, (height - 2) * percent / 100)), xRadius: 2, yRadius: 2).fill()
                let edge = NSBezierPath(roundedRect: track.insetBy(dx: -0.5, dy: -0.5), xRadius: 2.5, yRadius: 2.5)
                edge.lineWidth = 1
                NSColor(white: 0, alpha: 0.55).setStroke()
                edge.stroke()
                let outline = NSBezierPath(roundedRect: track.insetBy(dx: 0.5, dy: 0.5), xRadius: 1.5, yRadius: 1.5)
                outline.lineWidth = 1
                NSColor.white.setStroke()
                outline.stroke()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
