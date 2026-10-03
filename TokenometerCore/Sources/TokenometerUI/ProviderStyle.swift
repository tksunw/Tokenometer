import SwiftUI
import TokenometerCore

public extension Provider {
    /// Brand-adjacent and separable for the common color-vision deficiencies: clay, teal, blue.
    var color: Color {
        switch self {
        case .anthropic: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .openAI: Color(red: 0.06, green: 0.64, blue: 0.50)
        case .google: Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }
}

public enum UsageLevel {
    public static let warning = 75.0
    public static let critical = 90.0

    /// Usage that is behind the clock is never alarming. Ahead of pace, amber from 75 and red from 90.
    /// With no pace known (no reset time), the thresholds apply on their own.
    public static func tint(for percent: Double, base: Color, pace: Double? = nil) -> Color {
        if let pace, percent / 100 <= pace { return base }
        switch percent {
        case critical...: return .red
        case warning...: return .orange
        default: return base
        }
    }
}
