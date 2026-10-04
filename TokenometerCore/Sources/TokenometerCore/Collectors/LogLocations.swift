import Foundation

/// Where each tool writes on this Mac. Overridable so tests and the "force show" setting can point elsewhere.
public struct LogLocations: Sendable, Equatable {
    public var claudeCodeProjects: URL
    public var claudeDesktopSessions: URL
    public var claudeConfig: URL
    /// Written by the `usage-reporter` Claude Code mod (ADR-0004).
    public var claudeUsageFile: URL
    public var codexSessions: URL
    public var geminiHome: URL
    public var geminiTemp: URL
    public var antigravityConversations: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        claudeCodeProjects = home.appendingPathComponent(".claude/projects", isDirectory: true)
        claudeDesktopSessions = home.appendingPathComponent("Library/Application Support/Claude/local-agent-mode-sessions", isDirectory: true)
        claudeConfig = home.appendingPathComponent(".claude.json")
        claudeUsageFile = home.appendingPathComponent(".claude/usage-reporter/usage.json")
        codexSessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        geminiHome = home.appendingPathComponent(".gemini", isDirectory: true)
        // Under the seatbelt sandbox Gemini CLI relocates its runtime dir; the collector checks both.
        geminiTemp = home.appendingPathComponent(".gemini/tmp", isDirectory: true)
        antigravityConversations = home.appendingPathComponent(".gemini/antigravity/conversations", isDirectory: true)
    }

    public static let standard = LogLocations()
}

/// A log file as the walk saw it. `stamp` is what the parse caches compare to decide whether to read it again.
struct LogFile: Sendable {
    var url: URL
    var stamp: FileStamp
}

/// Size and modification time of a file at one moment.
struct FileStamp: Sendable, Equatable {
    var size: Int
    var modified: Date

    init(size: Int, modified: Date) {
        self.size = size
        self.modified = modified
    }

    /// Nil when the file is missing or unreadable.
    init?(of url: URL) {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        self.init(size: size, modified: modified)
    }
}

enum FileWalker {
    /// Regular files under `root` matching `predicate`, modified after `since` when given. Hidden
    /// directories are descended because Claude Desktop nests `.claude/projects` inside each session.
    static func files(under root: URL, modifiedAfter since: Date?, where predicate: (URL) -> Bool) -> [LogFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: []) else { return [] }
        var result: [LogFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            if let since, modified < since { continue }
            if predicate(url) { result.append(LogFile(url: url, stamp: FileStamp(size: values.fileSize ?? 0, modified: modified))) }
        }
        return result
    }
}
