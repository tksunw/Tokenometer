#!/usr/bin/env swift
// Renders the app icon: three provider-colored bars on a dark rounded square, at every size the
// AppIcon asset catalog needs. Run from the repo root: swift Scripts/make-icon.swift
import AppKit

let colors: [NSColor] = [
    NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1),
    NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1),
    NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1),
]
let heights: [CGFloat] = [0.55, 0.8, 0.35]

func render(size: Int) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    let inset = s * 0.08
    let square = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset), xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor(white: 0.12, alpha: 1).setFill()
    square.fill()
    let barWidth = s * 0.14
    let gap = s * 0.08
    let totalWidth = 3 * barWidth + 2 * gap
    var x = (s - totalWidth) / 2
    let baseY = s * 0.26
    let maxH = s * 0.5
    for (color, h) in zip(colors, heights) {
        let track = NSBezierPath(roundedRect: NSRect(x: x, y: baseY, width: barWidth, height: maxH), xRadius: barWidth / 2, yRadius: barWidth / 2)
        color.withAlphaComponent(0.25).setFill()
        track.fill()
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: baseY, width: barWidth, height: maxH * h), xRadius: barWidth / 2, yRadius: barWidth / 2)
        color.setFill()
        bar.fill()
        x += barWidth + gap
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = "Tokenometer/Assets.xcassets/AppIcon.appiconset"
var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)@\(scale)x.png"
    try! render(size: points * scale).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
print("wrote \(images.count) icons")
