import AppKit
import Foundation
import Observation
import WidgetKit
import TokenometerCore

/// Owns the latest snapshot and drives refreshes: FSEvents on log change, a 60 s timer as backstop,
/// usage endpoint calls at a 2 min floor while logs are active and every 5 min when idle.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot: Snapshot?
    private(set) var isRefreshing = false
    let settings = AppSettings()
    let updater = Updater()
    /// Set by the menu view from its environment, so AppKit callers (right-click menu) can open Settings.
    var openSettingsAction: (() -> Void)?
    private var statusItemMenu: StatusItemMenu?
    /// Which provider the horizontal menu bar style shows right now; advances every 10 s when cycling.
    private(set) var cycleIndex = 0
    private var cycleTimer: Timer?

    private let store = SnapshotStore()
    private let locations = LogLocations.standard
    private var refresher: UsageRefresher
    private var watcher: LogWatcher?
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private var lastWindowFetch: Date = .distantPast
    private var lastLogChange: Date = .distantPast
    private var windowSources: [any UsageWindowSource] = []

    init() {
        let previous = SnapshotStore().load()
        snapshot = previous
        refresher = UsageRefresher(collectors: Collectors.all(), windowSources: [], previous: previous)
    }

    func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettingsAction?()
    }

    func start(windowSources: [any UsageWindowSource]) {
        self.windowSources = windowSources
        statusItemMenu = StatusItemMenu(model: self)
        statusItemMenu?.install()
        refresher = UsageRefresher(collectors: Collectors.all(), windowSources: windowSources, locations: locations, previous: snapshot)
        restartWatcher()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestRefresh(logChanged: false) }
        }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.cycleIndex += 1 }
        }
        requestRefresh(logChanged: true)
    }

    /// The provider for the horizontal menu bar style: the pinned one, or the cycling one.
    var menuBarFocus: ProviderSnapshot? {
        guard let providers = snapshot?.providers, !providers.isEmpty else { return nil }
        if let pinned = settings.menuBarProvider.provider {
            return providers.first { $0.provider == pinned } ?? providers[0]
        }
        return providers[cycleIndex % providers.count]
    }

    func requestRefresh(logChanged: Bool, force: Bool = false) {
        if logChanged { lastLogChange = .now }
        if force { lastWindowFetch = .distantPast }
        guard refreshTask == nil else { refreshPending = true; return }
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
            guard let self else { return }
            refreshTask = nil
            if refreshPending {
                refreshPending = false
                requestRefresh(logChanged: false)
            }
        }
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let now = Date.now
        let active = now.timeIntervalSince(lastLogChange) < 600
        let fetchWindows = now.timeIntervalSince(lastWindowFetch) >= (active ? 120 : 300)
        let previous = snapshot
        let result = await refresher.refresh(settings: settings.engineSettings, fetchWindows: fetchWindows, now: now)
        if fetchWindows { lastWindowFetch = now }
        snapshot = result
        try? store.save(result)
        WidgetCenter.shared.reloadAllTimelines()
        if settings.notifyAtCritical { Notifier.notifyCrossings(from: previous, to: result) }
        restartWatcher()
    }

    private func restartWatcher() {
        let roots = [locations.claudeCodeProjects, locations.claudeDesktopSessions, locations.codexSessions,
                     locations.geminiTemp, locations.antigravityConversations, locations.claudeUsageFile.deletingLastPathComponent()]
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard roots != watcher?.paths else { return }
        watcher?.stop()
        watcher = LogWatcher(paths: roots) { [weak self] in
            Task { @MainActor in self?.requestRefresh(logChanged: true) }
        }
        watcher?.start()
    }
}
