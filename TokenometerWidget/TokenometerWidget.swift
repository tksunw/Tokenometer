import SwiftUI
import WidgetKit
import TokenometerCore
import TokenometerUI

@main
struct TokenometerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenometerWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: SnapshotStore().load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: SnapshotStore().load())
        // The app reloads timelines after every refresh; this is only the backstop.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct TokenometerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenometerWidget", provider: SnapshotProvider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Tokenometer")
        .description("Session and weekly AI usage per provider.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        WidgetContentView(snapshot: entry.snapshot, size: family == .systemSmall ? .small : (family == .systemLarge ? .large : .medium), now: entry.date)
    }
}
