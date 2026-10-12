import Darwin
import Foundation

/// Finds the installed `usage-reporter` mod. Marketplace installs are listed in Claude Code's plugin
/// registry; a development copy sits in a folder named by `CLAUDE_CODE_PLUGIN_DIRS` in settings.
/// Either may be the one Claude Code loads, so the copy that `enabledPlugins` marks on wins.
public struct UsageReporterLocator: Sendable {
    public var claudeHome: URL

    public init(claudeHome: URL) {
        self.claudeHome = claudeHome
    }

    public func locate() -> URL? {
        let settings = (try? JSONLines.object(in: claudeHome.appendingPathComponent("settings.json"))) ?? [:]
        let enabled = settings.dict("enabledPlugins") ?? [:]
        var candidates: [(enabled: Bool, path: URL)] = []

        let registry = claudeHome.appendingPathComponent("plugins/installed_plugins.json")
        for (key, entries) in (try? JSONLines.object(in: registry))?.dict("plugins") ?? [:] where key.hasPrefix("usage-reporter@") {
            for entry in entries as? [[String: Any]] ?? [] {
                guard entry.string("scope") ?? "user" == "user", let path = entry.string("installPath") else { continue }
                candidates.append((enabled[key] as? Bool == true, URL(fileURLWithPath: path, isDirectory: true)))
            }
        }

        let home = claudeHome.deletingLastPathComponent().path
        for dir in (settings.dict("env")?.string("CLAUDE_CODE_PLUGIN_DIRS") ?? "").split(separator: ":") {
            let expanded = dir.hasPrefix("~") ? home + dir.dropFirst() : String(dir)
            let children = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: expanded, isDirectory: true), includingPropertiesForKeys: nil)) ?? []
            for child in children { candidates.append((enabled["usage-reporter@inline"] as? Bool == true, child)) }
        }

        return candidates.first { $0.enabled && Self.isUsageReporter($0.path) }?.path
            ?? candidates.first { Self.isUsageReporter($0.path) }?.path
    }

    static func isUsageReporter(_ dir: URL) -> Bool {
        let manifest = dir.appendingPathComponent(".claude-plugin/plugin.json")
        return (try? JSONLines.object(in: manifest))?.string("name") == "usage-reporter"
    }
}

/// Asks the mod to report without a live session: starts Claude Code in a PTY with only the mod loaded,
/// waits for the mod's `session.start` report to land in the usage file, and ends the session. No prompt
/// is sent and no token is spent; Claude Code makes its usual usage call on its own login (ADR-0006).
public struct ClaudeUsagePull: Sendable {
    public enum Outcome: Equatable, Sendable {
        case fetched(after: TimeInterval)
        case timedOut
        /// The mod calls the endpoint at most once per five minutes across sessions; inside that a new
        /// session writes nothing, so the pull is not started.
        case insideFloor(until: Date)
        case modMissing
        case claudeMissing
        case launchFailed(String)
    }

    /// The mod's floor plus a margin for clock skew between its `at` and ours.
    public static let floor: TimeInterval = 5 * 60 + 10

    public var locations: LogLocations
    public var timeout: TimeInterval

    public init(locations: LogLocations = .standard, timeout: TimeInterval = 20) {
        self.locations = locations
        self.timeout = timeout
    }

    public func lastFetch() -> Date? { ClaudeUsageFile(file: locations.claudeUsageFile).lastFetch() }

    public func run(now: Date = .now, ignoringFloor: Bool = false) -> Outcome {
        guard let plugin = UsageReporterLocator(claudeHome: locations.claudeHome).locate() else { return .modMissing }
        guard let claude = Self.claudeExecutable() else { return .claudeMissing }
        let before = lastFetch()
        if !ignoringFloor, let before, before.addingTimeInterval(Self.floor) > now {
            return .insideFloor(until: before.addingTimeInterval(Self.floor))
        }
        try? FileManager.default.createDirectory(at: locations.claudePullDirectory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])

        var master: Int32 = -1, slave: Int32 = -1
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { return .launchFailed("openpty failed") }
        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        defer { close(master); try? terminal.close() }
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

        let process = Process()
        process.executableURL = claude
        process.arguments = Self.arguments(plugin: plugin)
        process.currentDirectoryURL = locations.claudePullDirectory
        process.environment = Self.environment()
        process.standardInput = terminal
        process.standardOutput = terminal
        process.standardError = terminal
        do { try process.run() } catch { return .launchFailed(error.localizedDescription) }
        defer { Self.stop(process) }

        let started = Date()
        var screen = Data(), buffer = [UInt8](repeating: 0, count: 16384), answered = false
        while Date().timeIntervalSince(started) < timeout {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            if poll(&descriptor, 1, 250) > 0 {
                let count = read(master, &buffer, buffer.count)
                if count > 0 {
                    screen.append(contentsOf: buffer.prefix(count))
                    if screen.count > 32768 { screen.removeFirst(screen.count - 16384) }
                }
            }
            // First run in the pull directory: Claude Code asks whether to trust it. Second choice is "Yes".
            if !answered, Self.asksForTrust(String(decoding: screen, as: UTF8.self)) {
                answered = true
                usleep(300_000); Self.type("\u{1b}[B", to: master)
                usleep(200_000); Self.type("\r", to: master)
            }
            if let after = lastFetch(), after != before { return .fetched(after: Date().timeIntervalSince(started)) }
            if !process.isRunning { break }
        }
        return .timedOut
    }

    /// Only the mod loads: no user settings, hooks, other plugins, tools, MCP servers or browser.
    static func arguments(plugin: URL) -> [String] {
        ["--setting-sources", "", "--plugin-dir", plugin.path, "--tools", "", "--strict-mcp-config",
         "--mcp-config", #"{"mcpServers":{}}"#, "--no-chrome"]
    }

    static func environment() -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env = ["HOME": home, "TERM": "xterm-256color", "LANG": "en_US.UTF-8", "CLAUDE_CODE_SKIP_PROMPT_HISTORY": "1",
                   "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        for key in ["USER", "SHELL", "TMPDIR"] { env[key] = current[key] }
        return env
    }

    public static func claudeExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let known = ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        let onPath = (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/claude" }
        return (known + onPath).first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// The trust dialog, read through the cursor moves the TUI puts between its words.
    static func asksForTrust(_ screen: String) -> Bool {
        let plain = screen
            .replacing(/\x1B\[[0-9;?]*[ -\/]*[@-~]/, with: "")
            .replacing(/\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)/, with: "")
        return plain.contains(/trust\s*this\s*folder/.ignoresCase())
    }

    private static func type(_ text: String, to fd: Int32) {
        Array(text.utf8).withUnsafeBufferPointer { _ = write(fd, $0.baseAddress, $0.count) }
    }

    private static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}
