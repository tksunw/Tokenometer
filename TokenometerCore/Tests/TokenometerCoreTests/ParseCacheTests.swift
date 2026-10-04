import Foundation
import Testing
@testable import TokenometerCore

private func fixtureData(_ path: String) throws -> Data {
    try Data(contentsOf: Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(path)"))
}

/// A fresh directory with one log file in it, and locations pointing the Claude and Codex collectors there.
private struct Scratch {
    let root: URL
    let file: URL
    var locations: LogLocations {
        var locations = LogLocations(home: root)
        locations.claudeCodeProjects = root
        locations.codexSessions = root
        return locations
    }

    init(name: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tokenometer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("project"), withIntermediateDirectories: true)
        file = root.appendingPathComponent("project/\(name)")
    }

    func write(_ data: Data) throws { try data.write(to: file) }

    func append(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// Byte offsets to split a fixture at: early, mid-line, and one byte short of the end.
private func splits(_ data: Data) -> [Int] {
    [1, data.count / 3, data.count / 2 + 7, data.count - 1]
}

@Suite struct ParseCacheTests {
    @Test(arguments: ["claude-code/project-a/session-main.jsonl", "claude-code/project-a/subagents/agent-1.jsonl"])
    func claudeAppendsMatchAFullParse(fixture: String) throws {
        let full = try fixtureData(fixture)
        let expected = ClaudeCodeParser.parse(objects: JSONLines.objects(in: full), tool: .claudeCode)
        for split in splits(full) {
            let scratch = try Scratch(name: "session.jsonl")
            defer { scratch.remove() }
            let collector = ClaudeCodeCollector(locations: scratch.locations)
            try scratch.write(full.prefix(split))
            _ = collector.collect(modifiedAfter: nil)
            try scratch.append(full.dropFirst(split))
            let result = collector.collect(modifiedAfter: nil)
            #expect(result.failures.isEmpty)
            #expect(result.records == expected, "split at byte \(split)")
        }
    }

    @Test func codexAppendsMatchAFullParse() throws {
        let full = try fixtureData("codex/rollout-small.jsonl")
        for split in splits(full) {
            let scratch = try Scratch(name: "rollout-small.jsonl")
            defer { scratch.remove() }
            let expected = CodexParser.parse(objects: JSONLines.objects(in: full), fallbackSessionID: "rollout-small")
            let collector = CodexCollector(locations: scratch.locations)
            try scratch.write(full.prefix(split))
            _ = collector.collect(modifiedAfter: nil)
            try scratch.append(full.dropFirst(split))
            let result = collector.collect(modifiedAfter: nil)
            #expect(result.records == expected.records, "split at byte \(split)")
            #expect(result.codexRateLimits == expected.rateLimits, "split at byte \(split)")
        }
    }

    @Test func aShorterRewriteIsParsedFromTheStart() throws {
        let full = try fixtureData("claude-code/project-a/session-main.jsonl")
        let firstTwoLines = full.split(separator: UInt8(ascii: "\n")).prefix(2).map { Data($0) + Data("\n".utf8) }.reduce(Data(), +)
        let scratch = try Scratch(name: "session.jsonl")
        defer { scratch.remove() }
        let collector = ClaudeCodeCollector(locations: scratch.locations)
        try scratch.write(full)
        #expect(collector.collect(modifiedAfter: nil).records.count == 2)
        try scratch.write(firstTwoLines)
        #expect(collector.collect(modifiedAfter: nil).records == ClaudeCodeParser.parse(objects: JSONLines.objects(in: firstTwoLines), tool: .claudeCode))
    }

    @Test func anUnchangedFileIsNotReadAgain() throws {
        let full = try fixtureData("claude-code/project-a/session-main.jsonl")
        let scratch = try Scratch(name: "session.jsonl")
        defer { scratch.remove() }
        let collector = ClaudeCodeCollector(locations: scratch.locations)
        // A whole second, so setting it back later yields an identical stamp.
        let modified = Date(timeIntervalSince1970: 1_790_000_000)
        try scratch.write(full)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: scratch.file.path)
        let first = collector.collect(modifiedAfter: nil).records
        #expect(first.count == 2)
        // Same size and mtime with different bytes: only a cache hit still returns the original records.
        try scratch.write(Data(repeating: UInt8(ascii: " "), count: full.count))
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: scratch.file.path)
        #expect(collector.collect(modifiedAfter: nil).records == first)
    }

    @Test func aTornLastLineIsLeftForTheNextRead() throws {
        let line = Data(#"{"type":"user","cwd":"/tmp/p","sessionId":"s"}"#.utf8) + Data("\n".utf8)
        var state = ClaudeCodeParser.State(tool: .claudeCode)
        #expect(JSONLines.feed(line + Data(#"{"type":"assis"#.utf8), to: &state) == line.count)
    }

    @Test func claudeSkipsNonAssistantLinesOnceSessionIsKnown() {
        var state = ClaudeCodeParser.State(tool: .claudeCode)
        let user = Data(#"{"type":"user","cwd":"/tmp/p","sessionId":"s","message":{"role":"user"}}"#.utf8)
        #expect(state.wants(user), "the first lines are read for cwd and sessionId")
        _ = JSONLines.feed(user + Data("\n".utf8), to: &state)
        #expect(!state.wants(user))
        #expect(state.wants(Data(#"{"type":"assistant"}"#.utf8)))
    }
}
