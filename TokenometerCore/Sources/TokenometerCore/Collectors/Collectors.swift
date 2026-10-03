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

    public init(locations: LogLocations = .standard) { root = locations.claudeCodeProjects }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        for url in FileWalker.files(under: root, modifiedAfter: since, where: { $0.pathExtension == "jsonl" }) {
            do { result.records += try ClaudeCodeParser.parse(fileURL: url, tool: .claudeCode) }
            catch { result.failures.append((url, error)) }
        }
        return result
    }
}

public struct ClaudeDesktopCollector: UsageCollector {
    public let tool: Tool = .claudeDesktop
    let root: URL

    public init(locations: LogLocations = .standard) { root = locations.claudeDesktopSessions }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        let transcripts = FileWalker.files(under: root, modifiedAfter: since) { url in
            url.pathExtension == "jsonl" && url.lastPathComponent != "audit.jsonl"
                && url.pathComponents.contains("projects")
        }
        for url in transcripts {
            do { result.records += try ClaudeCodeParser.parse(fileURL: url, tool: .claudeDesktop) }
            catch { result.failures.append((url, error)) }
        }
        return result
    }
}

public struct CodexCollector: UsageCollector {
    public let tool: Tool = .codex
    let root: URL

    public init(locations: LogLocations = .standard) { root = locations.codexSessions }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        for url in FileWalker.files(under: root, modifiedAfter: since, where: { $0.pathExtension == "jsonl" }) {
            do {
                let session = try CodexParser.parse(fileURL: url)
                result.records += session.records
                if let limits = session.rateLimits,
                   result.codexRateLimits.map({ limits.observedAt > $0.observedAt }) ?? true {
                    result.codexRateLimits = limits
                }
            } catch { result.failures.append((url, error)) }
        }
        return result
    }
}

public struct GeminiCLICollector: UsageCollector {
    public let tool: Tool = .geminiCLI
    let roots: [URL]

    public init(locations: LogLocations = .standard) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots = [locations.geminiTemp, home.appendingPathComponent(".cache/.gemini/tmp", isDirectory: true)]
    }

    public func isPresent() -> Bool { roots.contains { FileManager.default.fileExists(atPath: $0.path) } }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        for root in roots {
            let chats = FileWalker.files(under: root, modifiedAfter: since) { url in
                url.deletingLastPathComponent().lastPathComponent == "chats" || url.pathComponents.contains("chats")
            }.filter { ["jsonl", "json"].contains($0.pathExtension) && $0.lastPathComponent.hasPrefix("session-") }
            for url in chats {
                do { result.records += try GeminiCLIParser.parse(fileURL: url) }
                catch { result.failures.append((url, error)) }
            }
        }
        return result
    }
}

public struct AntigravityCollector: UsageCollector {
    public let tool: Tool = .antigravity
    let root: URL

    public init(locations: LogLocations = .standard) { root = locations.antigravityConversations }

    public func isPresent() -> Bool { FileManager.default.fileExists(atPath: root.path) }

    public func collect(modifiedAfter since: Date?) -> CollectorResult {
        var result = CollectorResult()
        // The -wal file carries the newest writes, so a db whose -wal is fresh counts as modified.
        let databases = FileWalker.files(under: root, modifiedAfter: nil) { $0.pathExtension == "db" }
        for url in databases {
            if let since {
                let candidates = [url, URL(fileURLWithPath: url.path + "-wal")]
                let newest = candidates.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
                if let newest, newest < since { continue }
            }
            do { result.records += try AntigravityParser.parse(databaseURL: url) }
            catch { result.failures.append((url, error)) }
        }
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
