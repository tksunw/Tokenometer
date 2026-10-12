import AppIntents
import SwiftUI
import WidgetKit
import TokenometerCore
import TokenometerUI

/// The Gauge widget's edit sheet: which providers to show. Kept under its old name so a placed
/// widget keeps its provider choice across the redesign; the ring-shape parameter is gone, since the
/// half-circle gauge replaces both shapes. All three off means all three.
struct RingsConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Session Gauges"
    static let description = IntentDescription("Choose the providers to show.")

    @Parameter(title: "Anthropic", default: true)
    var anthropic: Bool

    @Parameter(title: "OpenAI", default: true)
    var openAI: Bool

    @Parameter(title: "Google", default: true)
    var google: Bool

    var providers: Set<Provider> {
        var chosen = Set<Provider>()
        if anthropic { chosen.insert(.anthropic) }
        if openAI { chosen.insert(.openAI) }
        if google { chosen.insert(.google) }
        return chosen
    }
}

struct RingsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProvidersEntry {
        ProvidersEntry(date: .now, snapshot: nil, providers: [])
    }

    func snapshot(for configuration: RingsConfigurationIntent, in context: Context) async -> ProvidersEntry {
        ProvidersEntry(date: .now, snapshot: SnapshotStore().load(), providers: configuration.providers)
    }

    func timeline(for configuration: RingsConfigurationIntent, in context: Context) async -> Timeline<ProvidersEntry> {
        providersTimeline(providers: configuration.providers)
    }
}

struct RingsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TokenometerRings", intent: RingsConfigurationIntent.self, provider: RingsProvider()) { entry in
            GaugeView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Session Gauges")
        .description("Usage as half-circle gauges in a card per provider. Choose one, two, or all three providers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct GaugeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProvidersEntry

    var body: some View {
        GaugeWidgetView(snapshot: entry.snapshot, size: family == .systemSmall ? .small : (family == .systemLarge ? .large : .medium),
                        providers: entry.providers, now: entry.date)
    }
}
