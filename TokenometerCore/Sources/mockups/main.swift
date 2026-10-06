import AppKit
import SwiftUI
import TokenometerCore
import TokenometerUI

// Renders the README screenshots from the real views with sample data:
// swift run mockups ../docs/images   (from TokenometerCore)
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let now = Date(timeIntervalSince1970: 1_790_000_000)
var sample = SampleData.snapshot(now: now)
// `--two` keeps only the first two providers, to see the roomier widget variants with reset times.
// `--idle` gives the second provider a session window that has not started (0%, no reset time, so
// no pace tick), to check that its bar is the same height as the others.
if CommandLine.arguments.contains("--idle"), sample.providers.count > 1 {
    sample.providers[1].session?.usedPercent = 0
    sample.providers[1].session?.resetsAt = nil
}
// `--stale` marks the first provider's windows stale, to check the reason line under its bars.
if CommandLine.arguments.contains("--stale"), !sample.providers.isEmpty {
    sample.providers[0].windowsStale = StaleInfo(since: now.addingTimeInterval(-20 * 60), reason: "Logs are newer than the last usage report; check the usage-reporter mod is loaded in Claude Code")
}
// `--enterprise` makes the first provider an Enterprise login: no windows, its monthly spend limit as the bar.
if CommandLine.arguments.contains("--enterprise"), !sample.providers.isEmpty {
    sample.providers[0].accountKind = .metered
    sample.providers[0].planName = "Enterprise"
    sample.providers[0].session = UsageWindow(kind: .session, usedPercent: 81, label: "Monthly budget")
    sample.providers[0].weekly = nil
    sample.providers[0].scoped = []
    sample.providers[0].surfaces = nil
    sample.providers[0].grants = [CreditGrant(id: "extra_usage", label: "Monthly budget", used: 648.20, limit: 800)]
}
if CommandLine.arguments.contains("--two") { sample = Snapshot(generatedAt: sample.generatedAt, providers: Array(sample.providers.prefix(2))) }

@MainActor
func render<V: View>(_ view: V, name: String, scheme: ColorScheme = .dark) {
    let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:])
    else { print("failed \(name)"); return }
    try! png.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name) \(Int(image.size.width))x\(Int(image.size.height))")
}

struct MenuMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(sample.providers.enumerated()), id: \.offset) { index, provider in
                ProviderSectionView(snapshot: provider, now: now, expanded: index == 0)
                if index < sample.providers.count - 1 { Divider() }
            }
            Divider()
            HStack {
                Text("Updated \(Format.age(sample.generatedAt, now: now))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath")
                Image(systemName: "gearshape")
                Image(systemName: "power")
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct MenuBarStrip: View {
    let style: MenuBarStyle
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(nsImage: MenuBarImage.render(sample.providers, style: style))
            Text("Fri 9:41 AM").font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
    }
}

struct WidgetMock: View {
    let size: WidgetContentView.Size
    var frame: CGSize {
        switch size {
        // The sizes WidgetKit reported on macOS 27 (chronod log: 164x164, 344x164, 344x344).
        case .small: CGSize(width: 164, height: 164)
        case .medium: CGSize(width: 344, height: 164)
        case .large: CGSize(width: 344, height: 344)
        }
    }
    var body: some View {
        WidgetContentView(snapshot: sample, size: size, now: now)
            .padding(16)
            .frame(width: frame.width, height: frame.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

Task { @MainActor in
    render(MenuMock(), name: "menu-dark.png")
    render(MenuMock(), name: "menu-light.png", scheme: .light)
    render(MenuBarStrip(style: .gauge), name: "menubar.png")
    render(MenuBarStrip(style: .bars), name: "menubar-bars.png")
    render(MenuBarStrip(style: .horizontal), name: "menubar-horizontal.png")
    render(Image(nsImage: MenuBarImage.gauge(sample.providers)).interpolation(.none).resizable().frame(width: 24 * 6, height: 18 * 6).background(Color.black), name: "menubar-gauge-zoom.png")
    render(WidgetMock(size: .small), name: "widget-small.png")
    render(WidgetMock(size: .medium), name: "widget-medium.png")
    render(WidgetMock(size: .large), name: "widget-large.png")
    exit(0)
}
RunLoop.main.run()
