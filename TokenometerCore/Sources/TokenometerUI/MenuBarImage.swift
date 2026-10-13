import AppKit
import SwiftUI
import TokenometerCore

/// Which provider the menu bar item shows: the next one every 10 seconds, or one you pick.
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

    /// The menu bar item for one provider (`focus`, the first when nil). `showsWeekly` stacks the weekly
    /// bar under the session bar; `palette` colors the fills.
    public static func render(_ providers: [ProviderSnapshot], focus: ProviderSnapshot? = nil,
                              showsWeekly: Bool = true, palette: StatusPalette = .trafficLight, now: Date = .now) -> NSImage {
        horizontal(focus ?? providers[0], showsWeekly: showsWeekly, palette: palette, now: now)
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
        // "5H" and "7D" sit between the logo and the bars, so each bar says which window it is.
        let labelWidth: CGFloat = 13
        let barsX = tile + 4 + labelWidth + 3
        let width = barsX + barWidth + 4 + textWidth

        func fill(for window: UsageWindow?) -> NSColor {
            let percent = min(max(window?.usedPercent ?? 0, 0), 100)
            let status = UsageStatus.of(percent: percent, pace: window?.elapsedFraction(now: now))
            // The menu bar's own look follows the wallpaper, so the dark-mode shades are the ones that read.
            return NSColor(palette.color(status, .dark, provider: provider.provider))
        }

        /// "5H" for a window five hours long, "7D" for seven days; the usual lengths when it has none.
        func windowLabel(_ window: UsageWindow?, session: Bool) -> String {
            if session {
                let hours = window?.length.map { Int(($0 / 3600).rounded()) } ?? 5
                return "\(hours)H"
            }
            let days = window?.length.map { Int(($0 / 86400).rounded()) } ?? 7
            return "\(days)D"
        }

        func drawLabel(_ text: String, y: CGFloat) {
            let font = NSFont.systemFont(ofSize: weekly == nil ? 7.5 : 6.5, weight: .bold)
            let size = NSAttributedString(string: text, attributes: [.font: font]).size()
            let origin = NSPoint(x: tile + 4 + labelWidth - size.width, y: y + (barHeight - size.height) / 2)
            NSAttributedString(string: text, attributes: [.font: font, .strokeColor: NSColor(white: 0, alpha: 0.6), .strokeWidth: 18.0]).draw(at: origin)
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.white]).draw(at: origin)
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
                drawLabel(windowLabel(weekly, session: false), y: bottom)
                drawLabel(windowLabel(session, session: true), y: bottom + barHeight + gap)
            } else {
                drawBar(session, y: (height - barHeight) / 2)
                drawLabel(windowLabel(session, session: true), y: (height - barHeight) / 2)
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
}
