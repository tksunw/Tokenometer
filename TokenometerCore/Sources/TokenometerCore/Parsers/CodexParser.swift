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
        var state = State(fallbackSessionID: sessionID(for: fileURL))
        _ = JSONLines.feed(try Data(contentsOf: fileURL), to: &state)
        return state.session
    }

    public static func parse(objects: [[String: Any]], fallbackSessionID: String) -> CodexSession {
        var state = State(fallbackSessionID: fallbackSessionID)
        for object in objects { state.consume(object) }
        return state.session
    }

    static func sessionID(for fileURL: URL) -> String {
        fileURL.deletingPathExtension().lastPathComponent
    }

    /// One rollout's parse so far: the running totals carry across reads, so appended lines are parsed
    /// on their own and still produce per-turn deltas.
    struct State: JSONLineConsumer, Sendable {
        /// The only entry types the parser reads. Everything else (messages, tool calls and their
        /// output) is skipped without being deserialized.
        private static let needles = ["\"token_count\"", "\"session_meta\"", "\"turn_context\""].map { Data($0.utf8) }
        private static let totalKeys = ["input_tokens", "cached_input_tokens", "output_tokens", "cache_write_input_tokens", "reasoning_output_tokens"]

        private var sessionID: String
        private var project: String?
        private var model = "unknown"
        private var previousTotal: [String: Int] = [:]
        private var turn = 0
        private var records: [UsageRecord] = []
        private var rateLimits: CodexRateLimits?

        init(fallbackSessionID: String) {
            sessionID = fallbackSessionID
        }

        var session: CodexSession { CodexSession(records: records, rateLimits: rateLimits) }

        func wants(_ line: Data) -> Bool {
            Self.needles.contains { line.range(of: $0) != nil }
        }

        mutating func consume(_ entry: [String: Any]) {
            guard let payload = entry.dict("payload") else { return }
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
                else { return }
                if let info = payload.dict("info"), let total = info.dict("total_token_usage") {
                    let current = Dictionary(uniqueKeysWithValues: Self.totalKeys.map { ($0, total.int($0)) })
                    let delta = CodexParser.tokenDelta(from: previousTotal, to: current)
                    previousTotal = current
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
                        session: CodexParser.window(.session, from: limits.dict("primary")),
                        weekly: CodexParser.window(.weekly, from: limits.dict("secondary")),
                        planType: limits.string("plan_type"),
                        limitID: limits.string("limit_id"),
                        observedAt: timestamp
                    )
                }
            default:
                return
            }
        }
    }

    /// Codex `input_tokens` includes `cached_input_tokens`; split them so input means uncached.
    private static func tokenDelta(from previous: [String: Int], to current: [String: Int]) -> TokenCounts {
        func delta(_ key: String) -> Int { max(0, (current[key] ?? 0) - (previous[key] ?? 0)) }
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
