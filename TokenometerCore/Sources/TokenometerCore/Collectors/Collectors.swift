import Foundation

/// A tool's on-disk presence and the records it has logged since a cutoff. Collectors never write.
public protocol UsageCollector: Sendable {
    var tool: Tool { get }
    /// True when the tool's data directory exists. Absent tools vanish from the UI.
    func isPresent() -> Bool
    func collect(modifiedAfter since: Date?) -> CollectorResult
}

public struct CollectorResult: Sendable {
    public var records: [UsageRecord] = []
    /// Files that could not be read, with the error. Reported as a stale reason, never fatal.
    public var failures: [(URL, any Error)] = []
    public var codexRateLimits: CodexRateLimits?

    public init() {}
}

public struct ClaudeCodeCollector: UsageCollector {
    public let tool: Tool = .claudeCode
    let root: URL
    private let cache = AppendOnlyCache<ClaudeCodeParser.State>()

    public init(locations: LogLocations = .standard) { root = locations.claudeCodeProjects }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        let files = FileWalker.files(under: root, modifiedAfter: since, where: { $0.pathExtension == "jsonl" })
        return ClaudeCodeCollector.collect(files, tool: tool, cache: cache)
    }

    static func collect(_ files: [LogFile], tool: Tool, cache: AppendOnlyCache<ClaudeCodeParser.State>) -> CollectorResult {
        var result = CollectorResult()
        for file in files {
            do { result.records += try cache.state(for: file) { ClaudeCodeParser.State(tool: tool) }.records }
            catch { result.failures.append((file.url, error)) }
        }
        cache.retain(only: Set(files.map(\.url)))
        return result
    }
}

public struct ClaudeDesktopCollector: UsageCollector {
    public let tool: Tool = .claudeDesktop
    let root: URL
    private let cache = AppendOnlyCache<ClaudeCodeParser.State>()

    public init(locations: LogLocations = .standard) { root = locations.claudeDesktopSessions }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        let transcripts = FileWalker.files(under: root, modifiedAfter: since) { url in
            url.pathExtension == "jsonl" && url.lastPathComponent != "audit.jsonl"
                && url.pathComponents.contains("projects")
        }
        return ClaudeCodeCollector.collect(transcripts, tool: tool, cache: cache)
    }
}

public struct CodexCollector: UsageCollector {
    public let tool: Tool = .codex
    let root: URL
    private let cache = AppendOnlyCache<CodexParser.State>()

    public init(locations: LogLocations = .standard) { root = locations.codexSessions }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        let files = FileWalker.files(under: root, modifiedAfter: since, where: { $0.pathExtension == "jsonl" })
        for file in files {
            do {
                let session = try cache.state(for: file) { CodexParser.State(fallbackSessionID: CodexParser.sessionID(for: file.url)) }.session
                result.records += session.records
                if let limits = session.rateLimits,
                   result.codexRateLimits.map({ limits.observedAt > $0.observedAt }) ?? true {
                    result.codexRateLimits = limits
                }
            } catch { result.failures.append((file.url, error)) }
        }
        cache.retain(only: Set(files.map(\.url)))
        return result
    }
}

public struct GeminiCLICollector: UsageCollector {
    public let tool: Tool = .geminiCLI
    let roots: [URL]
    /// Gemini CLI rewrites history with `$patch` and `$rewindTo` lines, so a changed file is parsed whole.
    private let cache = ParseCache<[UsageRecord]>()

    public init(locations: LogLocations = .standard) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots = [locations.geminiTemp, home.appendingPathComponent(".cache/.gemini/tmp", isDirectory: true)]
    }

    public func isPresent() -> Bool { roots.contains { FileManager.default.fileExists(atPath: $0.path) } }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        var seen: Set<URL> = []
        for root in roots {
            let chats = FileWalker.files(under: root, modifiedAfter: since) { url in
                url.deletingLastPathComponent().lastPathComponent == "chats" || url.pathComponents.contains("chats")
            }.filter { ["jsonl", "json"].contains($0.url.pathExtension) && $0.url.lastPathComponent.hasPrefix("session-") }
            for file in chats {
                seen.insert(file.url)
                do { result.records += try cache.value(for: file.url, stamps: [file.stamp]) { try GeminiCLIParser.parse(fileURL: file.url) } }
                catch { result.failures.append((file.url, error)) }
            }
        }
        cache.retain(only: seen)
        return result
    }
}

public struct AntigravityCollector: UsageCollector {
    public let tool: Tool = .antigravity
    let root: URL
    /// Keyed on the db and its -wal together: the -wal carries the newest writes until a checkpoint.
    private let cache = ParseCache<[UsageRecord]>()

    public init(locations: LogLocations = .standard) { root = locations.antigravityConversations }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        var seen: Set<URL> = []
        // The -wal file carries the newest writes, so a db whose -wal is fresh counts as modified.
        let databases = FileWalker.files(under: root, modifiedAfter: nil) { $0.pathExtension == "db" }
        for database in databases {
            let wal = FileStamp(of: URL(fileURLWithPath: database.url.path + "-wal"))
            if let since, max(database.stamp.modified, wal?.modified ?? .distantPast) < since { continue }
            seen.insert(database.url)
            do { result.records += try cache.value(for: database.url, stamps: [database.stamp, wal]) { try AntigravityParser.parse(databaseURL: database.url) } }
            catch { result.failures.append((database.url, error)) }
        }
        cache.retain(only: seen)
        return result
    }
}

public enum Collectors {
    public static func all(locations: LogLocations = .standard) -> [any UsageCollector] {
        [
            ClaudeCodeCollector(locations: locations),
            ClaudeDesktopCollector(locations: locations),
            CodexCollector(locations: locations),
            GeminiCLICollector(locations: locations),
            AntigravityCollector(locations: locations),
        ]
    }
}
