import Foundation

/// Parses Gemini CLI chat recordings (`~/.gemini/tmp/<hash>/chats/session-*.jsonl`, legacy `*.json`).
/// Only `type: "gemini"` messages carry `tokens`; `$patch`, `$rewindTo` and `$set` control lines are honored.
public enum GeminiCLIParser {
    public static func parse(fileURL: URL) throws -> [UsageRecord] {
        if fileURL.pathExtension == "json" {
            guard let doc = try JSONLines.object(in: fileURL) else { return [] }
            let messages = doc["messages"] as? [[String: Any]] ?? []
            return build(sessionID: doc.string("sessionId") ?? fileURL.lastPathComponent, messages: messages)
        }
        return parse(lines: try JSONLines.objects(in: fileURL), fallbackSessionID: fileURL.lastPathComponent)
    }

    public static func parse(lines: [[String: Any]], fallbackSessionID: String) -> [UsageRecord] {
        var sessionID = fallbackSessionID
        var order: [String] = []
        var byID: [String: [String: Any]] = [:]

        func upsert(_ message: [String: Any]) {
            guard let id = message.string("id") else { return }
            if byID[id] == nil { order.append(id) }
            byID[id] = message
        }

        for (index, line) in lines.enumerated() {
            if index == 0, let id = line.string("sessionId") {
                sessionID = id
                continue
            }
            if let patch = line.dict("$patch") {
                for update in patch["updates"] as? [[String: Any]] ?? [] { upsert(update) }
                for removed in patch["removeIds"] as? [String] ?? [] {
                    byID[removed] = nil
                    order.removeAll { $0 == removed }
                }
                if let ordered = patch["orderIds"] as? [String], !ordered.isEmpty {
                    order = ordered.filter { byID[$0] != nil } + order.filter { !ordered.contains($0) }
                }
                continue
            }
            if let target = line["$rewindTo"] as? String {
                if let cut = order.firstIndex(of: target) {
                    for id in order[(cut + 1)...] { byID[id] = nil }
                    order = Array(order[...cut])
                }
                continue
            }
            if line["$set"] != nil { continue }
            upsert(line)
        }
        return build(sessionID: sessionID, messages: order.compactMap { byID[$0] })
    }

    private static func build(sessionID: String, messages: [[String: Any]]) -> [UsageRecord] {
        messages.compactMap { message in
            guard message.string("type") == "gemini",
                  let tokens = message.dict("tokens"),
                  let id = message.string("id"),
                  let timestamp = Timestamps.parse(message["timestamp"])
            else { return nil }
            // Gemini API semantics: input (promptTokenCount) already includes cached.
            let cached = tokens.int("cached")
            let counts = TokenCounts(
                input: max(0, tokens.int("input") - cached),
                output: tokens.int("output"),
                cacheRead: cached,
                thinking: tokens.int("thoughts")
            )
            guard counts.total > 0 else { return nil }
            return UsageRecord(
                id: "\(sessionID)/\(id)",
                tool: .geminiCLI,
                model: message.string("model") ?? "unknown",
                timestamp: timestamp,
                tokens: counts,
                sessionID: sessionID
            )
        }
    }
}
