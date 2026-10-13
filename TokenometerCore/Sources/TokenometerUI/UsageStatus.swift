import SwiftUI
import TokenometerCore

/// How a window's fill is colored: by whether usage is running ahead of the clock, not by provider.
/// Green while at or behind the pace line (and for a small lead), yellow once usage leads the line
/// by `leadToCaution`, red when it is past the line at `criticalPercent` or more ("time to wrap it up").
public enum UsageStatus: Sendable, Equatable {
    case ok, caution, critical

    /// A lead over the pace line smaller than this stays green, so the first minutes of a window
    /// (when a point or two of use is already "ahead") do not flip the bar.
    public static let leadToCaution = 0.10
    public static let criticalPercent = 90.0

    /// `pace` is the elapsed fraction of the window, 0 to 1, or nil when the window has no reset time.
    /// With no pace the old absolute rule applies: caution from 75%, critical from 90%.
    public static func of(percent: Double, pace: Double?) -> UsageStatus {
        let used = min(max(percent, 0), 100)
        if let pace {
            if used >= criticalPercent, used / 100 > pace { return .critical }
            // Compared in points with a hair of tolerance: 61 against a 51 pace is exactly 10 ahead, not 9.999999.
            return used - pace * 100 >= leadToCaution * 100 - 1e-9 ? .caution : .ok
        }
        if used >= criticalPercent { return .critical }
        return used >= UsageLevel.warning ? .caution : .ok
    }
}

/// How fills are colored. `trafficLight` is green, yellow, red (RAG status); `colorBlind` is the
/// Okabe-Ito set (sky blue, orange, vermilion), the same in light and dark; `provider` is each
/// provider's own color whatever the status, with no warning or critical change.
public struct StatusPalette: Sendable, Equatable {
    /// Draws every fill in its provider's color. The status colors below are then only a fallback
    /// for a fill with no provider.
    let usesProviderColor: Bool
    struct Pair: Sendable, Equatable {
        var light: UInt32
        var dark: UInt32
    }
    let ok: Pair
    let caution: Pair
    let critical: Pair

    public static let trafficLight = StatusPalette(
        usesProviderColor: false,
        ok: Pair(light: 0x1F9D63, dark: 0x3FC58B),
        caution: Pair(light: 0xD9A400, dark: 0xF5CF4A),
        critical: Pair(light: 0xD93036, dark: 0xE5484D))
    public static let colorBlind = StatusPalette(
        usesProviderColor: false,
        ok: Pair(light: 0x56B4E9, dark: 0x56B4E9),
        caution: Pair(light: 0xE69F00, dark: 0xE69F00),
        critical: Pair(light: 0xD55E00, dark: 0xD55E00))

    public static let provider = StatusPalette(
        usesProviderColor: true,
        ok: trafficLight.ok, caution: trafficLight.caution, critical: trafficLight.critical)

    public func color(_ status: UsageStatus, _ scheme: ColorScheme, provider: Provider? = nil) -> Color {
        if usesProviderColor, let provider { return provider.color }
        let pair = switch status {
        case .ok: ok
        case .caution: caution
        case .critical: critical
        }
        let hex = scheme == .dark ? pair.dark : pair.light
        return Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The user's palette choice, carried in the snapshot so the widget (a separate, sandboxed process
/// that cannot read the app's preferences) draws the same colors as the menu.
public enum PaletteChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case trafficLight, colorBlind, provider

    public var id: String { rawValue }

    public var palette: StatusPalette {
        switch self {
        case .trafficLight: .trafficLight
        case .colorBlind: .colorBlind
        case .provider: .provider
        }
    }

    public var displayName: String {
        switch self {
        case .trafficLight: "Traffic light"
        case .colorBlind: "Color-blind friendly"
        case .provider: "Provider"
        }
    }

    /// Reads the stored name. A snapshot written by a development build called traffic light "standard".
    public init(stored: String?) {
        self = stored == "standard" ? .trafficLight : (stored.flatMap(PaletteChoice.init(rawValue:)) ?? .trafficLight)
    }
}

extension EnvironmentValues {
    @Entry public var statusPalette: StatusPalette = .trafficLight
}
