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

    /// Menu: "⟳ today 11:49 PM", "⟳ Sun 6:59 AM" within the week, "⟳ Oct 16, 6:59 AM" beyond.
    public static func resets(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "⟳ now" }
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "⟳ today \(time)" }
        return "⟳ \(day(date, now: now)) \(time)"
    }

    /// Widgets: "⟳ 3:49 PM" today, "⟳ Sun 3:49 PM" within the week, "⟳ Oct 16, 3:49 PM" beyond.
    public static func resetsShort(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "⟳ now" }
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "⟳ \(time)" }
        return "⟳ \(day(date, now: now)) \(time)"
    }

    /// A weekly window resets within seven days, so its weekday names the day without ambiguity;
    /// anything further out gets the date. "Sun" or "Oct 16,".
    private static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 7
        return days < 7 ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.month(.abbreviated).day()) + ","
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
