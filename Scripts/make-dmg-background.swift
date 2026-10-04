// Renders the DMG installer-window background: the icon's charcoal, a title, an arrow pointing
// from the app icon (left) toward the Applications folder (right), a hint line, and the three
// provider colors as a thin rule. Icon positions in dmg-settings.py must match the gaps left
// here: app ~(170,200), Applications ~(490,200) in a 660x400-point window.
// Usage: swift Scripts/make-dmg-background.swift <out-dir>, then
//   tiffutil -cathidpicheck <out-dir>/dmg-bg-1x.png <out-dir>/dmg-bg@2x.png -out Scripts/dmg-background.tiff
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let providerColors: [NSColor] = [
    NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1),
    NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1),
    NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1),
]

func render(scale: CGFloat) -> Data {
    let w = 660 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(colors: [NSColor(white: 0.10, alpha: 1), NSColor(white: 0.18, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)

    func draw(_ text: String, size: CGFloat, y: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size * scale, weight: weight),
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: style,
        ])
        let height = string.size().height
        string.draw(in: NSRect(x: 0, y: (h - y * scale) - height / 2, width: w, height: height))
    }
    draw("Install Tokenometer", size: 26, y: 64, weight: .semibold, alpha: 0.95)
    draw("Drag the app onto the Applications folder", size: 13, y: 330, weight: .regular, alpha: 0.7)

    // The provider colors as a short rule under the title.
    let segment = 34 * scale, gap = 6 * scale
    var x = (w - (segment * 3 + gap * 2)) / 2
    for color in providerColors {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: h - 96 * scale, width: segment, height: 4 * scale), xRadius: 2 * scale, yRadius: 2 * scale).fill()
        x += segment + gap
    }

    // Arrow across the middle, between the two icon slots (~x 250 to 410).
    let arrow = NSBezierPath()
    let midY = h / 2, x0 = 258 * scale, x1 = 402 * scale, head = 16 * scale
    arrow.lineWidth = 6 * scale
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: x0, y: midY))
    arrow.line(to: NSPoint(x: x1, y: midY))
    arrow.move(to: NSPoint(x: x1 - head, y: midY + head))
    arrow.line(to: NSPoint(x: x1, y: midY))
    arrow.line(to: NSPoint(x: x1 - head, y: midY - head))
    NSColor.white.withAlphaComponent(0.85).setStroke()
    arrow.stroke()

    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 2).write(to: URL(fileURLWithPath: outDir).appendingPathComponent("dmg-bg@2x.png"))
try! render(scale: 1).write(to: URL(fileURLWithPath: outDir).appendingPathComponent("dmg-bg-1x.png"))
print("wrote dmg-bg-1x.png and dmg-bg@2x.png")
