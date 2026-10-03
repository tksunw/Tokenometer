import Foundation
import UserNotifications
import TokenometerCore
import TokenometerUI

/// One notification when a window crosses the critical threshold, one when it resets. Off by default.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyCrossings(from previous: Snapshot?, to current: Snapshot) {
        for provider in current.providers {
            let old = previous?.provider(provider.provider)
            for (label, window, before) in [("Session", provider.session, old?.session), ("Weekly", provider.weekly, old?.weekly)] {
                guard let window else { continue }
                let was = before?.usedPercent ?? 0
                let aheadOfPace = window.elapsedFraction().map { window.usedPercent / 100 > $0 } ?? true
                if was < UsageLevel.critical, window.usedPercent >= UsageLevel.critical, aheadOfPace {
                    post(id: "\(provider.provider.rawValue)-\(label)-critical",
                         title: "\(provider.provider.displayName) \(label.lowercased()) window at \(Format.percent(window.usedPercent))",
                         body: Format.resets(window.resetsAt)?.replacingOccurrences(of: "⟳", with: "Resets") ?? "")
                } else if was >= UsageLevel.critical, window.usedPercent < UsageLevel.warning {
                    post(id: "\(provider.provider.rawValue)-\(label)-reset",
                         title: "\(provider.provider.displayName) \(label.lowercased()) window reset",
                         body: "Back to \(Format.percent(window.usedPercent))")
                }
            }
        }
    }

    private static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
