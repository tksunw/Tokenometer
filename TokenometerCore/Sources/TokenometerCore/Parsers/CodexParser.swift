import Foundation

/// What one Codex rollout file yields: per-turn usage plus the newest rate-limit report it contains.
public struct CodexSession: Sendable, Equatable {
    public var records: [UsageRecord]
    public var rateLimits: CodexRateLimits?
}

/// Codex is the one provider that writes usage percent to disk. `observedAt` is the event's timestamp,
/// so the newest report across all rollout files is the current state.
public struct CodexRateLimits: Sendable, Equatable {
    public var session: UsageWindow?
    public var weekly: UsageWindow?
    public var planType: String?
    public var limitID: String?
    public var observedAt: Date
}

/// Parses Codex rollouts (`~/.codex/sessions/**/*.jsonl`). `token_count` events carry cumulative
/// `total_token_usage`; usage per turn is the delta between consecutive events.
public enum CodexParser {
    public static func parse(fileURL: URL) throws -> CodexSession {
        parse(objects: try JSONLines.objects(in: fileURL), fallbackSessionID: fileURL.deletingPathExtension().lastPathComponent)
    }

    public static func parse(objects: [[String: Any]], fallbackSessionID: String) -> CodexSession {
        var records: [UsageRecord] = []
        var rateLimits: CodexRateLimits?
        var sessionID = fallbackSessionID
        var project: String?
        var model = "unknown"
        var previousTotal: [String: Any] = [:]
        var turn = 0

        for entry in objects {
            guard let payload = entry.dict("payload") else { continue }
            switch entry.string("type") {
            case "session_meta":
                if let id = payload.string("id") { sessionID = id }
                if let cwd = payload.string("cwd") { project = URL(fileURLWithPath: cwd).lastPathComponent }
            case "turn_context":
                if let m = payload.string("model") { model = m }
                if project == nil, let cwd = payload.string("cwd") { project = URL(fileURLWithPath: cwd).lastPathComponent }
            case "event_msg":
                guard payload.string("type") == "token_count",
                      let timestamp = Timestamps.parse(entry["timestamp"])
                else { continue }
                if let info = payload.dict("info"), let total = info.dict("total_token_usage") {
                    let delta = tokenDelta(from: previousTotal, to: total)
                    previousTotal = total
                    if delta.total > 0 {
                        turn += 1
                        records.append(UsageRecord(
                            id: "\(sessionID)#\(turn)",
                            tool: .codex,
                            model: model,
                            timestamp: timestamp,
                            tokens: delta,
                            sessionID: sessionID,
                            project: project
                        ))
                    }
                }
                if let limits = payload.dict("rate_limits") {
                    rateLimits = CodexRateLimits(
                        session: window(.session, from: limits.dict("primary")),
                        weekly: window(.weekly, from: limits.dict("secondary")),
                        planType: limits.string("plan_type"),
                        limitID: limits.string("limit_id"),
                        observedAt: timestamp
                    )
                }
            default:
                continue
            }
        }
        return CodexSession(records: records, rateLimits: rateLimits)
    }

    /// Codex `input_tokens` includes `cached_input_tokens`; split them so input means uncached.
    private static func tokenDelta(from previous: [String: Any], to current: [String: Any]) -> TokenCounts {
        func delta(_ key: String) -> Int { max(0, current.int(key) - previous.int(key)) }
        let cached = delta("cached_input_tokens")
        return TokenCounts(
            input: max(0, delta("input_tokens") - cached),
            output: delta("output_tokens"),
            cacheRead: cached,
            cacheWrite: delta("cache_write_input_tokens"),
            thinking: delta("reasoning_output_tokens")
        )
    }

    private static func window(_ kind: WindowKind, from dict: [String: Any]?) -> UsageWindow? {
        guard let dict, let used = dict["used_percent"] as? NSNumber else { return nil }
        let minutes = dict["window_minutes"] as? NSNumber
        return UsageWindow(
            kind: kind,
            usedPercent: used.doubleValue,
            resetsAt: Timestamps.parse(dict["resets_at"]),
            length: minutes.map { $0.doubleValue * 60 }
        )
    }
}
