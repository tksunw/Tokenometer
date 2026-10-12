import AppIntents
import SwiftUI
import WidgetKit
import TokenometerCore
import TokenometerUI

@main
struct TokenometerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenometerWidget()
        RingsWidget()
    }
}

/// The snapshot at an instant, with the providers one placed widget was set to show.
struct ProvidersEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let providers: Set<Provider>
}

/// Entries every 5 minutes keep the pace ticks and elapsed numbers moving in between reloads: the app
/// reloads timelines only when the snapshot changes. 15 min is the backstop.
func providersTimeline(providers: Set<Provider>) -> Timeline<ProvidersEntry> {
    let snapshot = SnapshotStore().load()
    let now = Date.now
    let entries = stride(from: 0.0, to: 15 * 60, by: 5 * 60).map { ProvidersEntry(date: now.addingTimeInterval($0), snapshot: snapshot, providers: providers) }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
}

/// The edit sheet of a placed widget (right-click, Edit Widget): which providers to show. Each placed
/// widget keeps its own, so several can sit side by side showing different providers. All three
/// switched off means all three, so the widget never goes blank.
struct BarsConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tokenometer Bars"
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

struct BarsProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProvidersEntry {
        ProvidersEntry(date: .now, snapshot: nil, providers: [])
    }

    func snapshot(for configuration: BarsConfigurationIntent, in context: Context) async -> ProvidersEntry {
        ProvidersEntry(date: .now, snapshot: SnapshotStore().load(), providers: configuration.providers)
    }

    func timeline(for configuration: BarsConfigurationIntent, in context: Context) async -> Timeline<ProvidersEntry> {
        providersTimeline(providers: configuration.providers)
    }
}

struct TokenometerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TokenometerWidget", intent: BarsConfigurationIntent.self, provider: BarsProvider()) { entry in
            BarsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tokenometer Bars")
        .description("Session and weekly usage as bars in a card per provider. Choose one, two, or all three providers.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct BarsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProvidersEntry

    var body: some View {
        BarsWidgetView(snapshot: entry.snapshot, size: family == .systemSmall ? .small : (family == .systemLarge ? .large : .medium),
                       providers: entry.providers, now: entry.date)
    }
}
