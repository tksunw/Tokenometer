import Foundation

/// Parses Claude Code transcripts (`~/.claude/projects/**/*.jsonl`). Claude Desktop's local agent
/// sessions write the same format, so the caller names the tool.
public enum ClaudeCodeParser {
    public static func parse(fileURL: URL, tool: Tool = .claudeCode) throws -> [UsageRecord] {
        var state = State(tool: tool)
        _ = JSONLines.feed(try Data(contentsOf: fileURL), to: &state)
        return state.records
    }

    public static func parse(objects: [[String: Any]], tool: Tool) -> [UsageRecord] {
        var state = State(tool: tool)
        for object in objects { state.consume(object) }
        return state.records
    }

    /// One transcript's parse so far. Kept between reads so appended lines are parsed on their own and
    /// still dedupe against the entries already seen.
    struct State: JSONLineConsumer, Sendable {
        /// Only assistant entries carry usage. Most of a transcript's bytes are tool results in user
        /// entries, so those lines are never deserialized once the session's cwd and id are known.
        private static let assistant = Data("\"assistant\"".utf8)

        let tool: Tool
        private var order: [String] = []
        private var byID: [String: UsageRecord] = [:]
        private var project: String?
        private var sessionID: String?

        init(tool: Tool) {
            self.tool = tool
        }

        var records: [UsageRecord] { order.compactMap { byID[$0] } }

        func wants(_ line: Data) -> Bool {
            project == nil || sessionID == nil || line.range(of: Self.assistant) != nil
        }

        mutating func consume(_ entry: [String: Any]) {
            if project == nil, let cwd = entry.string("cwd") {
                project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            if sessionID == nil { sessionID = entry.string("sessionId") }
            guard entry.string("type") == "assistant",
                  let message = entry.dict("message"),
                  let usage = message.dict("usage"),
                  let timestamp = Timestamps.parse(entry["timestamp"])
            else { return }

            let tokens = TokenCounts(
                input: usage.int("input_tokens"),
                output: usage.int("output_tokens"),
                cacheRead: usage.int("cache_read_input_tokens"),
                cacheWrite: usage.int("cache_creation_input_tokens")
            )
            if tokens.total == 0 { return }

            // Streaming writes one entry per content block, all sharing message.id.
            // The last one carries the final counts, so it replaces earlier ones.
            let messageID = message.string("id") ?? entry.string("uuid") ?? UUID().uuidString
            let record = UsageRecord(
                id: messageID,
                tool: tool,
                model: message.string("model") ?? "unknown",
                timestamp: timestamp,
                tokens: tokens,
                sessionID: sessionID ?? entry.string("sessionId") ?? "",
                project: project
            )
            if byID[messageID] == nil { order.append(messageID) }
            byID[messageID] = record
        }
    }
}
