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

    /// `focus` is the provider the horizontal style shows; ignored by the other styles.
    public static func render(_ providers: [ProviderSnapshot], style: MenuBarStyle, darkMenuBar: Bool, focus: ProviderSnapshot? = nil) -> NSImage {
        switch style {
        case .gauge: gauge(providers, darkMenuBar: darkMenuBar)
        case .bars: bars(providers)
        case .horizontal: horizontal(focus ?? providers[0], darkMenuBar: darkMenuBar)
        }
    }

    // MARK: Horizontal

    /// A 40pt bar with pace tick and the percent beside it. The menu bar is transparent over the
    /// wallpaper, so the background can be anything from white to black: the outline and the digits
    /// are white with a dark edge and read on either, and the provider's color is in the fill only.
    public static func horizontal(_ provider: ProviderSnapshot, darkMenuBar: Bool) -> NSImage {
        let barWidth: CGFloat = 40
        let barHeight: CGFloat = 7
        let textWidth: CGFloat = 26
        let width = barWidth + 4 + textWidth
        let percent = min(max(provider.session?.usedPercent ?? 0, 0), 100)
        let fill = NSColor(UsageLevel.tint(for: percent, base: provider.provider.color, pace: provider.session?.elapsedFraction()))
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let y = (height - barHeight) / 2
            let track = NSRect(x: 0, y: y, width: barWidth, height: barHeight)
            NSColor(white: 0, alpha: 0.25).setFill()
            NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            fill.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: max(barHeight, barWidth * percent / 100), height: barHeight), xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
            // Two-tone outline: a dark edge outside a white core, so the empty end of the track still
            // reads as bar on any background.
            let edge = NSBezierPath(roundedRect: track.insetBy(dx: -0.5, dy: -0.5), xRadius: barHeight / 2 + 0.5, yRadius: barHeight / 2 + 0.5)
            edge.lineWidth = 1
            NSColor(white: 0, alpha: 0.55).setStroke()
            edge.stroke()
            let outline = NSBezierPath(roundedRect: track.insetBy(dx: 0.5, dy: 0.5), xRadius: barHeight / 2 - 0.5, yRadius: barHeight / 2 - 0.5)
            outline.lineWidth = 1
            NSColor.white.setStroke()
            outline.stroke()
            // The pace tick is two-tone the same way.
            if let pace = provider.session?.elapsedFraction() {
                let x = barWidth * pace
                NSColor(white: 0, alpha: 0.6).setFill()
                NSBezierPath(rect: NSRect(x: x - 1.5, y: y - 2.5, width: 3, height: barHeight + 5)).fill()
                NSColor.white.setFill()
                NSBezierPath(rect: NSRect(x: x - 0.75, y: y - 2, width: 1.5, height: barHeight + 4)).fill()
            }
            // White digits over a dark outline of the same glyphs; a soft shadow washes out on a light bar.
            let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            let label = Format.percent(percent)
            let size = NSAttributedString(string: label, attributes: [.font: font]).size()
            let origin = NSPoint(x: barWidth + 4 + textWidth - size.width, y: (height - size.height) / 2)
            NSAttributedString(string: label, attributes: [.font: font, .strokeColor: NSColor(white: 0, alpha: 0.6), .strokeWidth: 22.0]).draw(at: origin)
            NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.white]).draw(at: origin)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Gauge

    public static func gauge(_ providers: [ProviderSnapshot], darkMenuBar: Bool) -> NSImage {
        let width: CGFloat = 24
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let rim = NSColor(white: darkMenuBar ? 1 : 0, alpha: 0.85)
            let center = NSPoint(x: width / 2, y: 3.5)
            let radius: CGFloat = 9.5

            // Rim: provider-neutral up to 75%, amber to 90%, red to 100%. Angles run 180° (0%) to 0° (100%).
            func arc(from startPercent: Double, to endPercent: Double, color: NSColor) {
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: radius, startAngle: 180 - 180 * startPercent / 100, endAngle: 180 - 180 * endPercent / 100, clockwise: true)
                path.lineWidth = 2
                path.lineCapStyle = .round
                color.setStroke()
                path.stroke()
            }
            arc(from: 0, to: UsageLevel.warning, color: rim)
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
            rim.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.75, y: center.y - 1.75, width: 3.5, height: 3.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Bars

    static let barWidth: CGFloat = 5
    static let gap: CGFloat = 3

    public static func bars(_ providers: [ProviderSnapshot]) -> NSImage {
        let width = CGFloat(providers.count) * barWidth + CGFloat(max(0, providers.count - 1)) * gap
        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for provider in providers {
                let percent = min(max(provider.session?.usedPercent ?? 0, 0), 100)
                let base = NSColor(provider.provider.color)
                let fill = NSColor(UsageLevel.tint(for: percent, base: provider.provider.color, pace: provider.session?.elapsedFraction()))
                base.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: barWidth, height: height - 2), xRadius: 1.5, yRadius: 1.5).fill()
                fill.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: 1, width: barWidth, height: max(2, (height - 2) * percent / 100)), xRadius: 1.5, yRadius: 1.5).fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
