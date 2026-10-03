import AppKit
import Foundation
import Observation
import Sparkle

/// Sparkle wrapper. The feed is an appcast.xml attached to each GitHub release; updates are EdDSA
/// signed by `Scripts/release.sh`. System profiling is off (see PRIVACY.md).
///
/// A menu bar app has no window to host Sparkle's scheduled-update alert, so this implements
/// Sparkle's gentle reminders: a background check that finds an update only marks `pendingVersion`,
/// the menu shows it, and Sparkle's own UI appears when the user asks.
@MainActor
@Observable
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    /// Version a scheduled check found, until the user acts on it.
    private(set) var pendingVersion: String?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Let Sparkle show its window only when it would be seen; otherwise we surface it in the menu.
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.pendingVersion = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pendingVersion = nil }
    }
}
