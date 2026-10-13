import SwiftUI
import TokenometerCore

public extension Provider {
    /// Identity color, used on the logo tile: clay, light purple, blue. The window fills take the status
    /// color (`UsageStatus`) unless the Provider palette is chosen, which uses this.
    var color: Color {
        switch self {
        case .anthropic: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .openAI: Color(red: 0.66, green: 0.55, blue: 1.0)
        case .google: Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }
}

public enum UsageLevel {
    public static let warning = 75.0
    public static let critical = 90.0
}
