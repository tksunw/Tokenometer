import AppKit
import Foundation
import Observation
import WidgetKit
import TokenometerCore

/// Owns the latest snapshot and drives refreshes: FSEvents on log change, a 60 s timer as backstop,
/// the Antigravity localhost call at a 2 min floor while logs are active and every 5 min when idle,
/// and a pull through a throwaway Claude Code session when the usage-reporter file ages (ADR-0006).
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
    private let pull = ClaudeUsagePull()
    private var pullPolicy = PullPolicy()
    private var pullTask: Task<Void, Never>?
    private var resetTimer: Timer?

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
        WidgetRepair.runIfBuildChanged()
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
        // Windows may have reset and the file aged while the Mac slept; give the network a moment first.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                self?.requestRefresh(logChanged: false, force: true)
            }
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

    /// `force` is a prompt (Refresh now, wake, a window's reset): network sources are asked again
    /// regardless of pace, and the mod is asked to report if its floor allows.
    func requestRefresh(logChanged: Bool, force: Bool = false) {
        if logChanged { lastLogChange = .now }
        if force { lastWindowFetch = .distantPast; requestPull(.prompted) }
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
        // Saved every time so the widget's "as of" stays current when its timeline next ends (15 min).
        // Most refreshes change nothing visible; a reload for each one wakes the widget extension
        // and spends WidgetKit's reload budget, so only a real change reloads.
        try? store.save(result)
        if !result.hasSameContent(as: previous) { WidgetCenter.shared.reloadAllTimelines() }
        if settings.notifyAtCritical { Notifier.notifyCrossings(from: previous, to: result) }
        restartWatcher()
        scheduleResetWakeup(for: result)
        requestPull(.idle)
    }

    /// Starts a pull if the policy allows and there is a Claude plan account to pull for. The session
    /// blocks for up to twenty seconds, so it runs off the main actor; the file watcher and an explicit
    /// refresh pick up the report.
    private func requestPull(_ trigger: PullPolicy.Trigger) {
        guard pullTask == nil, snapshot?.provider(.anthropic)?.accountKind == .plan else { return }
        let now = Date.now
        guard pullPolicy.shouldPull(trigger, now: now, lastFetch: pull.lastFetch()) else { return }
        let pull = pull
        pullTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .utility) { pull.run(now: now) }.value
            guard let self else { return }
            pullPolicy.record(outcome, at: .now)
            pullTask = nil
            if case .fetched = outcome { requestRefresh(logChanged: false) }
        }
    }

    /// Wakes at the next window reset across every provider, so the bar empties on time and the
    /// provider is asked for the new window instead of waiting for the next log change.
    private func scheduleResetWakeup(for snapshot: Snapshot) {
        resetTimer?.invalidate()
        let windows = snapshot.providers.flatMap { [$0.session, $0.weekly].compactMap { $0 } + $0.scoped }
        guard let next = windows.compactMap(\.resetsAt).filter({ $0 > .now }).min() else { return }
        resetTimer = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSinceNow + PullPolicy.resetGrace, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.requestRefresh(logChanged: false, force: true) }
        }
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
