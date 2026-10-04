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
        let snapshot = SnapshotStore().load()
        let now = Date.now
        // The app reloads timelines only when the snapshot changes, so entries every 5 minutes keep
        // the pace markers moving in between without spending the reload budget. 15 min is the backstop.
        let entries = stride(from: 0.0, to: 15 * 60, by: 5 * 60).map { SnapshotEntry(date: now.addingTimeInterval($0), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
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
