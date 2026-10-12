import AppKit
import SwiftUI
import TokenometerCore
import TokenometerUI

// Renders the README screenshots from the real views with sample data:
// swift run mockups ../docs/images   (from TokenometerCore)
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/images")
try FileManager.default.createDirectory(at: outDir.appendingPathComponent("widgets"), withIntermediateDirectories: true)
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
// `--near` pushes Claude toward its limits (session 88%, weekly 82%, Fable 94%) to see yellow and red.
if CommandLine.arguments.contains("--near"), !sample.providers.isEmpty {
    sample.providers[0].session?.usedPercent = 88
    sample.providers[0].weekly?.usedPercent = 82
    if !sample.providers[0].scoped.isEmpty { sample.providers[0].scoped[0].usedPercent = 94 }
}
// `--colorblind` stamps the color-blind palette, as the app does when the setting is on.
if CommandLine.arguments.contains("--colorblind") { sample.palette = "colorBlind" }
let onlyWidgets = CommandLine.arguments.contains("--only-widgets")
let lightScheme = CommandLine.arguments.contains("--light")
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
                ProviderCardView(snapshot: provider, now: now, expanded: index == 0)
            }
            HStack {
                Text("Updated \(Format.age(sample.generatedAt, now: now))").font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath")
                Image(systemName: "gearshape")
                Image(systemName: "power")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(width: 340)
        .environment(\.statusPalette, PaletteChoice(rawValue: sample.palette ?? "")?.palette ?? .standard)
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

/// A widget at its WidgetKit size on a card-colored ground, like the container background.
struct WidgetFrame<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: Content
    init(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.content = content()
    }
    var body: some View {
        content
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Every size of both new widgets for each provider choice: all three, two, and one.
@MainActor
func renderWidgetSets() {
    let sets: [(String, Set<Provider>)] = [
        ("3", []), ("2-claude-codex", [.anthropic, .openAI]), ("2-claude-gemini", [.anthropic, .google]), ("2-codex-gemini", [.openAI, .google]),
        ("1-claude", [.anthropic]), ("1-codex", [.openAI]), ("1-gemini", [.google]),
    ]
    let scheme: ColorScheme = lightScheme ? .light : .dark
    // The README uses three of the seven sets; `--only-widgets` renders all of them to review every layout.
    let curated: Set<String> = ["3", "1-claude", "2-claude-codex"]
    for (tag, providers) in sets where onlyWidgets || curated.contains(tag) {
        for (sizeName, width, height, bars, gauge) in [
            ("small", 164.0, 164.0, BarsWidgetView.Size.small, GaugeWidgetView.Size.small),
            ("medium", 344.0, 164.0, .medium, .medium),
            ("large", 344.0, 344.0, .large, .large),
        ] as [(String, CGFloat, CGFloat, BarsWidgetView.Size, GaugeWidgetView.Size)] {
            render(WidgetFrame(width: width, height: height) { BarsWidgetView(snapshot: sample, size: bars, providers: providers, now: now) }, name: "widgets/bars-\(sizeName)-\(tag).png", scheme: scheme)
            render(WidgetFrame(width: width, height: height) { GaugeWidgetView(snapshot: sample, size: gauge, providers: providers, now: now) }, name: "widgets/gauge-\(sizeName)-\(tag).png", scheme: scheme)
        }
    }
}

/// The shared pieces on their own: tiles, gauges at three statuses, bars.
struct PrimitivesMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) { ForEach(Provider.allCases) { ProviderTile($0, size: 28) } }
            HStack(spacing: 16) {
                ArcGauge(percent: 42, pace: 0.73, width: 104, numberSize: 24, caption: "Session")
                ArcGauge(percent: 61, pace: 0.38, width: 104, numberSize: 24, caption: "Weekly")
                ArcGauge(percent: 94, pace: 0.66, width: 104, numberSize: 24, caption: "Fable")
                ArcGauge(percent: 0, pace: 0.2, width: 60, numberSize: 14)
            }
            VStack(spacing: 4) {
                StatusBar(percent: 42, pace: 0.73, height: 8)
                StatusBar(percent: 61, pace: 0.38, height: 8)
                StatusBar(percent: 94, pace: 0.66, height: 8)
                StatusBar(percent: 0, pace: nil, height: 8)
            }
        }
        .padding(16)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

Task { @MainActor in
    if onlyWidgets { render(PrimitivesMock(), name: "primitives.png") }
    if onlyWidgets { renderWidgetSets(); exit(0) }
    renderWidgetSets()
    render(MenuMock(), name: "menu-dark.png")
    render(MenuMock(), name: "menu-light.png", scheme: .light)
    render(MenuBarStrip(style: .gauge), name: "menubar.png")
    render(MenuBarStrip(style: .bars), name: "menubar-bars.png")
    render(MenuBarStrip(style: .horizontal), name: "menubar-horizontal.png")
    render(Image(nsImage: MenuBarImage.gauge(sample.providers)).interpolation(.none).resizable().frame(width: 24 * 6, height: 18 * 6).background(Color.black), name: "menubar-gauge-zoom.png")
    exit(0)
}
RunLoop.main.run()
