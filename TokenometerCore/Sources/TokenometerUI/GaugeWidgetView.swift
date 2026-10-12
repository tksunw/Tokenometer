import SwiftUI
import TokenometerCore

/// The Gauge widget: half-circle gauges in provider cards. Small, medium, large; one, two, or three
/// providers (`providers` empty means all). STUB: replaced by the real layouts.
public struct GaugeWidgetView: View {
    public enum Size { case small, medium, large }

    let snapshot: Snapshot?
    let size: Size
    let providers: Set<Provider>
    let now: Date

    public init(snapshot: Snapshot?, size: Size, providers: Set<Provider> = [], now: Date = .now) {
        self.snapshot = snapshot
        self.size = size
        self.providers = providers
        self.now = now
    }

    public var body: some View { Text("Gauge widget") }
}
