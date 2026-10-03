import Foundation

/// Parses Claude Code transcripts (`~/.claude/projects/**/*.jsonl`). Claude Desktop's local agent
/// sessions write the same format, so the caller names the tool.
public enum ClaudeCodeParser {
    public static func parse(fileURL: URL, tool: Tool = .claudeCode) throws -> [UsageRecord] {
        parse(objects: try JSONLines.objects(in: fileURL), tool: tool)
    }

    public static func parse(objects: [[String: Any]], tool: Tool) -> [UsageRecord] {
        var order: [String] = []
        var byID: [String: UsageRecord] = [:]
        var project: String?
        var sessionID: String?

        for entry in objects {
            if project == nil, let cwd = entry.string("cwd") {
                project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            if sessionID == nil { sessionID = entry.string("sessionId") }
            guard entry.string("type") == "assistant",
                  let message = entry.dict("message"),
                  let usage = message.dict("usage"),
                  let timestamp = Timestamps.parse(entry["timestamp"])
            else { continue }

            let tokens = TokenCounts(
                input: usage.int("input_tokens"),
                output: usage.int("output_tokens"),
                cacheRead: usage.int("cache_read_input_tokens"),
                cacheWrite: usage.int("cache_creation_input_tokens")
            )
            if tokens.total == 0 { continue }

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
        return order.compactMap { byID[$0] }
    }
}
