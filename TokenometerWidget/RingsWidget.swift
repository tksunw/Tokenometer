import AppIntents
import SwiftUI
import WidgetKit
import TokenometerCore
import TokenometerUI

/// The widget's edit sheet (right-click, Edit Widget): which providers to show and the ring's
/// shape. Each placed widget keeps its own, so several can sit side by side showing different
/// providers. All three switched off means all three, so the widget never goes blank.
struct RingsConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Session Rings"
    static let description = IntentDescription("Choose the providers and the ring's shape.")

    @Parameter(title: "Anthropic", default: true)
    var anthropic: Bool

    @Parameter(title: "OpenAI", default: true)
    var openAI: Bool

    @Parameter(title: "Google", default: true)
    var google: Bool

    @Parameter(title: "Shape", default: .ring)
    var shape: RingShape

    var providers: Set<Provider> {
        var chosen = Set<Provider>()
        if anthropic { chosen.insert(.anthropic) }
        if openAI { chosen.insert(.openAI) }
        if google { chosen.insert(.google) }
        return chosen
    }
}

enum RingShape: String, AppEnum {
    case ring, gauge

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Shape")
    static let caseDisplayRepresentations: [RingShape: DisplayRepresentation] = [.ring: "Ring", .gauge: "Gauge"]

    var style: SessionRingStyle { self == .ring ? .ring : .gauge }
}

struct RingsEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let configuration: RingsConfigurationIntent
}

/// Same timeline shape as `SnapshotProvider`: entries every 5 min for the pace ticks, 15 min backstop.
struct RingsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> RingsEntry {
        RingsEntry(date: .now, snapshot: nil, configuration: RingsConfigurationIntent())
    }

    func snapshot(for configuration: RingsConfigurationIntent, in context: Context) async -> RingsEntry {
        RingsEntry(date: .now, snapshot: SnapshotStore().load(), configuration: configuration)
    }

    func timeline(for configuration: RingsConfigurationIntent, in context: Context) async -> Timeline<RingsEntry> {
        let snapshot = SnapshotStore().load()
        let now = Date.now
        let entries = stride(from: 0.0, to: 15 * 60, by: 5 * 60).map { RingsEntry(date: now.addingTimeInterval($0), snapshot: snapshot, configuration: configuration) }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
    }
}

struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TokenometerRings", intent: RingsConfigurationIntent.self, provider: RingsProvider()) { entry in
            RingsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Session Rings")
        .description("Session usage as a ring per provider, weekly too on the large, or one provider large.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RingsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RingsEntry

    var body: some View {
        RingWidgetView(snapshot: entry.snapshot, size: family == .systemSmall ? .small : (family == .systemLarge ? .large : .medium),
                       providers: entry.configuration.providers, style: entry.configuration.shape.style, now: entry.date)
    }
}
