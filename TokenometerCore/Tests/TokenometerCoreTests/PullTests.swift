import Foundation
import Testing
@testable import TokenometerCore

@Suite struct UsageReporterLocatorTests {
    /// A fake `~/.claude` with an optional registry entry, settings, and plugin folders.
    private func claudeHome(registry: String? = nil, settings: String? = nil, plugins: [String: String] = [:]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("plugins"), withIntermediateDirectories: true)
        if let registry {
            try registry.replacingOccurrences(of: "$HOME", with: home.path)
                .write(to: claude.appendingPathComponent("plugins/installed_plugins.json"), atomically: true, encoding: .utf8)
        }
        if let settings { try settings.write(to: claude.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8) }
        for (path, name) in plugins {
            let dir = home.appendingPathComponent(path, isDirectory: true).appendingPathComponent(".claude-plugin", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try #"{"name":"\#(name)","version":"0.6.2"}"#.write(to: dir.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        }
        return claude
    }

    private let registry = #"{"version":2,"plugins":{"usage-reporter@tksunw":[{"scope":"user","installPath":"$HOME/.claude/plugins/cache/tksunw/usage-reporter/0.6.2","version":"0.6.2"}],"other@tksunw":[{"scope":"user","installPath":"$HOME/.claude/plugins/cache/tksunw/other/1"}]}}"#

    @Test func marketplaceInstallIsFoundThroughTheRegistry() throws {
        let home = try claudeHome(registry: registry, plugins: [".claude/plugins/cache/tksunw/usage-reporter/0.6.2": "usage-reporter"])
        #expect(UsageReporterLocator(claudeHome: home).locate()?.path.hasSuffix("usage-reporter/0.6.2") == true)
    }

    @Test func developmentCopyIsFoundThroughThePluginDirs() throws {
        let home = try claudeHome(settings: #"{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"~/.claude/mods"}}"#,
                                  plugins: [".claude/mods/usage-reporter": "usage-reporter", ".claude/mods/status-enhanced": "status-enhanced"])
        #expect(UsageReporterLocator(claudeHome: home).locate()?.lastPathComponent == "usage-reporter")
    }

    @Test func theEnabledCopyWinsWhenBothExist() throws {
        let settings = #"{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"~/.claude/mods"},"enabledPlugins":{"usage-reporter@tksunw":false,"usage-reporter@inline":true}}"#
        let home = try claudeHome(registry: registry, settings: settings,
                                  plugins: [".claude/plugins/cache/tksunw/usage-reporter/0.6.2": "usage-reporter", ".claude/mods/usage-reporter": "usage-reporter"])
        #expect(UsageReporterLocator(claudeHome: home).locate()?.path.hasSuffix("mods/usage-reporter") == true)
    }

    @Test func aRegistryPathThatIsNotTheModIsSkipped() throws {
        // The registry names a folder, but the folder holds another plugin (or nothing): no match.
        let home = try claudeHome(registry: registry, plugins: [".claude/plugins/cache/tksunw/usage-reporter/0.6.2": "something-else"])
        #expect(UsageReporterLocator(claudeHome: home).locate() == nil)
        #expect(UsageReporterLocator(claudeHome: try claudeHome()).locate() == nil)
    }
}

@Suite struct ClaudeUsagePullTests {
    @Test func lastFetchIsTheNewestFetchOnlyStamp() throws {
        let scoped = #"{"version":1,"at":"2026-10-11T23:00:00.000Z","windows":[{"kind":"session","percent":1,"at":"2026-10-11T23:00:00.000Z"},{"kind":"weekly","label":"Fable","percent":2,"at":"2026-10-11T22:52:31.749Z"}],"grants":[{"id":"x","used":0,"at":"2026-10-11T22:40:00.000Z"}]}"#
        let root = try JSONSerialization.jsonObject(with: Data(scoped.utf8)) as! [String: Any]
        #expect(ClaudeUsageFile.lastFetch(report: root) == Timestamps.parse("2026-10-11T22:52:31.749Z"))

        // No scoped window, breakdown, grant or credit: the file's own stamp is all there is.
        let plain = try JSONSerialization.jsonObject(with: Data(#"{"version":1,"at":"2026-10-11T23:00:00.000Z","windows":[]}"#.utf8)) as! [String: Any]
        #expect(ClaudeUsageFile.lastFetch(report: plain) == Timestamps.parse("2026-10-11T23:00:00.000Z"))
    }

    @Test func trustPromptIsSeenThroughCursorMoves() {
        let screen = "\u{1b}[2G\u{1b}[38;2;177;185;249m❯\u{1b}[4GNo,\u{1b}[8Gexit\u{1b}[39m\n\u{1b}[4GYes,\u{1b}[9GI\u{1b}[11Gtrust\u{1b}[17Gthis\u{1b}[22Gfolder\n"
        #expect(ClaudeUsagePull.asksForTrust(screen))
        #expect(!ClaudeUsagePull.asksForTrust("⏵⏵ auto mode on (shift+tab to cycle)"))
    }

    @Test func insideTheFloorNothingIsLaunched() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var locations = LogLocations(home: home)
        locations.claudeHome = try UsageReporterLocatorTests().claudeHomeForPull(home)
        try FileManager.default.createDirectory(at: locations.claudeUsageFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"version":1,"at":"2026-10-11T23:00:00.000Z","windows":[{"kind":"weekly","label":"Fable","percent":2,"at":"2026-10-11T23:00:00.000Z"}]}"#
            .write(to: locations.claudeUsageFile, atomically: true, encoding: .utf8)
        let now = Timestamps.parse("2026-10-11T23:03:00.000Z")!
        #expect(ClaudeUsagePull(locations: locations).run(now: now) == .insideFloor(until: Timestamps.parse("2026-10-11T23:05:10.000Z")!))
    }
}

@Suite struct PullPolicyTests {
    let t0 = Timestamps.parse("2026-10-11T12:00:00.000Z")!
    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func idlePullsOnceTheFileIsHalfAnHourOld() {
        let policy = PullPolicy()
        #expect(!policy.shouldPull(.idle, now: at(29 * 60), lastFetch: t0))
        #expect(policy.shouldPull(.idle, now: at(30 * 60), lastFetch: t0))
        #expect(policy.shouldPull(.idle, now: t0, lastFetch: nil))
    }

    @Test func promptedPullsWaitForTheModFloorAndSpaceThemselves() {
        var policy = PullPolicy()
        #expect(!policy.shouldPull(.prompted, now: at(300), lastFetch: t0))
        #expect(policy.shouldPull(.prompted, now: at(310), lastFetch: t0))
        policy.record(.fetched(after: 2), at: at(310))
        // A wake ten seconds after a reset pull: one session, not two.
        #expect(!policy.shouldPull(.prompted, now: at(320), lastFetch: nil))
        #expect(policy.shouldPull(.prompted, now: at(340), lastFetch: nil))
    }

    @Test func failuresBackOffAndAFetchClearsThem() {
        var policy = PullPolicy()
        policy.record(.timedOut, at: t0)
        #expect(!policy.shouldPull(.idle, now: at(299), lastFetch: nil))
        #expect(policy.shouldPull(.idle, now: at(300), lastFetch: nil))
        policy.record(.modMissing, at: at(300))
        #expect(!policy.shouldPull(.prompted, now: at(300 + 599), lastFetch: nil))
        #expect(policy.shouldPull(.prompted, now: at(300 + 600), lastFetch: nil))
        for _ in 0..<10 { policy.record(.launchFailed("x"), at: at(1000)) }
        #expect(!policy.shouldPull(.idle, now: at(1000 + 3599), lastFetch: nil))
        #expect(policy.shouldPull(.idle, now: at(1000 + 3600), lastFetch: nil))
        policy.record(.fetched(after: 2), at: at(5000))
        #expect(policy.failures == 0)
        policy.record(.insideFloor(until: at(5300)), at: at(5100))
        #expect(policy.failures == 0)
    }
}

private extension UsageReporterLocatorTests {
    /// A `~/.claude` under `home` with one mod installed, for tests that need the locator to succeed.
    func claudeHomeForPull(_ home: URL) throws -> URL {
        let claude = home.appendingPathComponent(".claude", isDirectory: true)
        let mod = claude.appendingPathComponent("mods/usage-reporter/.claude-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: mod, withIntermediateDirectories: true)
        try #"{"name":"usage-reporter"}"#.write(to: mod.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try #"{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"\#(claude.path)/mods"}}"#.write(to: claude.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        return claude
    }
}
