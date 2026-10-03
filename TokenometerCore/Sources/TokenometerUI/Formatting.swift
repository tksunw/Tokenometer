import Foundation
import TokenometerCore

public enum Format {
    /// 950 -> "950", 12_300 -> "12.3K", 4_560_000 -> "4.6M".
    public static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return String(format: "%.1fK", value / 1_000).replacingOccurrences(of: ".0K", with: "K")
        default: return String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }

    /// API-equivalent dollars; a trailing "+" when some model had no rate, "?" when nothing was priceable.
    public static func usd(_ spend: Spend) -> String {
        if spend.hasUnknownCost && spend.costUSD == 0 { return "$?" }
        let text = spend.costUSD < 0.01 && spend.costUSD > 0 ? String(format: "$%.3f", spend.costUSD) : String(format: "$%.2f", spend.costUSD)
        return spend.hasUnknownCost ? text + "+" : text
    }

    public static func percent(_ value: Double) -> String {
        "\(Int(min(max(value, 0), 100).rounded()))%"
    }

    /// Menu: "⟳ today 11:49 PM", "⟳ tomorrow 6:59 AM", "⟳ Oct 6, 6:59 AM".
    public static func resets(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "⟳ now" }
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return "⟳ today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "⟳ tomorrow \(time)"
        }
        return "⟳ \(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    /// Small and medium widgets: "⟳ 3:49 PM" today, else "⟳ Oct 4, 3:49 PM".
    public static func resetsShort(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "⟳ now" }
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "⟳ \(time)" }
        return "⟳ \(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    /// Large widget's narrow column: the time today, else the date, no symbol.
    public static func resetsCompact(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "now" }
        if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    public static func age(_ date: Date, now: Date = .now) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(seconds / 60)m ago"
        case ..<86_400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86_400)d ago"
        }
    }
}
