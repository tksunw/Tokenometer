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

    /// Menu: "⟳ today 11:49 PM", "⟳ Sun 6:59 AM" otherwise.
    public static func resets(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "⟳ now" }
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "⟳ today \(time)" }
        return "⟳ \(day(date, now: now)) \(time)"
    }

    /// Widgets: "⟳ 3:49 PM" today, "⟳ Sun 3:49 PM" otherwise.
    public static func resetsShort(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "⟳ now" }
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return "⟳ \(time)" }
        return "⟳ \(day(date, now: now)) \(time)"
    }

    /// Bare reset time for the cards: "12:38 PM" today, "Wed 7:49 PM" otherwise.
    public static func resetTime(_ date: Date?, now: Date = .now) -> String? {
        guard let date else { return nil }
        if date <= now { return "now" }
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return time }
        return "\(day(date, now: now)) \(time)"
    }

    /// The weekday names the day. A window resets within seven days, and a reset exactly a week out
    /// reads as today's weekday, which the pace tick and the time of day tell apart from today.
    private static func day(_ date: Date, now: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// Menu footer: "3:49 PM" today, "Wed 7:49 PM" within a week, the date beyond that.
    public static func updated(_ date: Date, now: Date = .now) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDate(date, inSameDayAs: now) { return time }
        if now.timeIntervalSince(date) < 6 * 86_400 { return "\(day(date, now: now)) \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + " \(time)"
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
