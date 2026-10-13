import Foundation
import TokenometerCore

/// One window with the label every surface uses for it. "Session" and "Weekly" are always spelled out;
/// a scoped window keeps its group plus the word ("Fable weekly", "Gemini session").
public struct WindowRow: Identifiable, Sendable {
    public enum Role: Sendable { case session, weekly, scoped }

    public var label: String
    public var window: UsageWindow
    public var role: Role
    public var id: String { "\(role)-\(label)" }
}

public extension ProviderSnapshot {
    var sessionLabel: String { session?.label ?? "Session" }
    var weeklyLabel: String {
        if let label = weekly?.label { return label }
        return scoped.isEmpty ? "Weekly" : "All models weekly"
    }

    /// Session first, then weekly, then scoped windows, as the menu and widgets order them.
    var windowRows: [WindowRow] {
        var rows: [WindowRow] = []
        if let session { rows.append(WindowRow(label: sessionLabel, window: session, role: .session)) }
        if let weekly { rows.append(WindowRow(label: weeklyLabel, window: weekly, role: .weekly)) }
        for window in scoped { rows.append(WindowRow(label: window.label ?? "Scoped", window: window, role: .scoped)) }
        return rows
    }

    /// The name widgets use in narrow places: Claude, Codex, Gemini.
    var shortName: String { provider.shortName }
}

public extension Format {
    /// "73%": how much of the window's time has passed. Nil when the window has no reset time or length.
    static func elapsed(_ window: UsageWindow, now: Date = .now) -> String? {
        window.elapsedFraction(now: now).map { "\(Int(($0 * 100).rounded()))%" }
    }

    /// "in 1 h 21 m" under a day, "in 2 d 8 h" beyond; nil when there is no reset time or it has passed.
    static func remaining(_ window: UsageWindow, now: Date = .now) -> String? {
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        let minutes = Int(resetsAt.timeIntervalSince(now) / 60)
        if minutes < 60 { return "in \(minutes) m" }
        if minutes < 24 * 60 { return "in \(minutes / 60) h \(minutes % 60) m" }
        return "in \(minutes / (24 * 60)) d \((minutes % (24 * 60)) / 60) h"
    }
}

public extension Snapshot {
    /// The same snapshot with every window tagged with its provider, so the widget views can draw a
    /// window in its provider's color. The tag is for drawing only and is never saved.
    func stamped() -> Snapshot {
        var copy = self
        for index in copy.providers.indices {
            let provider = copy.providers[index].provider
            copy.providers[index].session?.provider = provider
            copy.providers[index].weekly?.provider = provider
            for scopedIndex in copy.providers[index].scoped.indices { copy.providers[index].scoped[scopedIndex].provider = provider }
        }
        return copy
    }
}
