import Foundation
import Testing
@testable import TokenometerCore

private func fixture(_ path: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(path)")
}

@Suite struct ClaudeCodeParserTests {
    @Test func dedupesStreamedEntriesByMessageID() throws {
        let records = try ClaudeCodeParser.parse(fileURL: fixture("claude-code/project-a/session-main.jsonl"))
        #expect(records.count == 2)
        let first = try #require(records.first)
        #expect(first.id == "msg_a1")
        #expect(first.model == "claude-fable-5-1")
        #expect(first.tokens == TokenCounts(input: 4, output: 120, cacheRead: 30000, cacheWrite: 12000))
        #expect(first.project == "project-a")
        #expect(first.sessionID == "sess-main")
        #expect(records[1].model == "claude-haiku-4-5-20251001")
    }

    @Test func readsSubagentTranscripts() throws {
        let records = try ClaudeCodeParser.parse(fileURL: fixture("claude-code/project-a/subagents/agent-1.jsonl"))
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.tool == .claudeCode && $0.tokens.total > 0 })
    }
}

@Suite struct CodexParserTests {
    @Test func turnsAreDeltasOfCumulativeTotals() throws {
        let session = try CodexParser.parse(fileURL: fixture("codex/rollout-small.jsonl"))
        #expect(!session.records.isEmpty)
        let first = try #require(session.records.first)
        #expect(first.tokens.input == 16908 - 12416)
        #expect(first.tokens.cacheRead == 12416)
        #expect(first.tokens.output == 218)
        #expect(first.tokens.thinking == 37)
        #expect(first.tool == .codex)
        // Repeated token_count events with unchanged totals must not produce empty turns.
        #expect(session.records.allSatisfy { $0.tokens.total > 0 })
    }

    @Test func readsRateLimits() throws {
        let session = try CodexParser.parse(fileURL: fixture("codex/rollout-small.jsonl"))
        let limits = try #require(session.rateLimits)
        #expect(limits.planType == "team")
        let s = try #require(limits.session)
        #expect(s.length == 18000.0)
        #expect(s.resetsAt != nil)
        let w = try #require(limits.weekly)
        #expect(w.length == 604800.0)
        #expect(w.usedPercent >= 0)
    }
}

@Suite struct GeminiCLIParserTests {
    private let chats = "gemini-cli/tmp/0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/chats"

    @Test func appliesPatchesAndSplitsCachedInput() throws {
        let records = try GeminiCLIParser.parse(fileURL: fixture("\(chats)/session-2026-10-01T09-15-abcd1234.jsonl"))
        #expect(records.count == 2)
        #expect(records[0].tokens == TokenCounts(input: 1200, output: 150, cacheRead: 2000, thinking: 40))
        #expect(records[0].model == "gemini-3.8-flash")
        // The $patch line replaces m4 with its final counts.
        #expect(records[1].tokens.output == 400)
        #expect(records[1].tokens.thinking == 120)
        #expect(records[1].sessionID == "abcd1234-0000-4000-8000-000000000001")
    }

    @Test func readsLegacyJSON() throws {
        let records = try GeminiCLIParser.parse(fileURL: fixture("\(chats)/session-2026-09-20T10-00-legacy01.json"))
        #expect(records.count == 1)
        #expect(records[0].tokens == TokenCounts(input: 1000, output: 100))
        #expect(records[0].model == "gemini-3.5-flash")
    }
}

@Suite struct AntigravityParserTests {
    @Test func readsStepsAndModelNames() throws {
        let records = try AntigravityParser.parse(databaseURL: fixture("antigravity/conversation-small.db"))
        #expect(records.count == 6)
        let first = try #require(records.first)
        #expect(first.tool == .antigravity)
        #expect(first.tokens.input == 16561)
        #expect(first.tokens.output == 899)
        #expect(first.tokens.thinking == 814)
        #expect(first.model == "gemini-3.8-flash")
        #expect(Calendar.current.component(.year, from: first.timestamp) == 2026)
        // Only four gen_metadata rows in the fixture, so later steps fall back to the enum name.
        #expect(records[5].model.hasPrefix("antigravity-model-"))
    }
}

@Suite struct WireDecoderTests {
    @Test func decodesNestedVarintsAndStrings() throws {
        // field 1: message { field 2: varint 300, field 3: "hi" }
        let inner = Data([0x10, 0xAC, 0x02, 0x1A, 0x02, 0x68, 0x69])
        let outer = Data([0x0A, UInt8(inner.count)]) + inner
        let message = try WireMessage(parsing: outer)
        let nested = try #require(message.message(1))
        #expect(nested.int(2) == 300)
        #expect(nested.string(3) == "hi")
        #expect(message.message(path: [1])?.int(2) == 300)
    }

    @Test func rejectsTruncatedInput() {
        #expect(throws: WireError.truncated) { try WireMessage(parsing: Data([0x0A, 0x05, 0x01])) }
    }

    @Test func readsNegativeInt64InsteadOfTrapping() throws {
        // field 2: varint -1, encoded as ten bytes (0xFF x9, 0x01), above Int.max as a UInt64
        let message = try WireMessage(parsing: Data([0x10] + [UInt8](repeating: 0xFF, count: 9) + [0x01]))
        #expect(message.int(2) == -1)
    }

    @Test func rejectsALengthAboveIntMax() {
        // field 1, length-delimited, length 2^64 - 1
        let data = Data([0x0A] + [UInt8](repeating: 0xFF, count: 9) + [0x01])
        #expect(throws: WireError.truncated) { try WireMessage(parsing: data) }
    }
}
