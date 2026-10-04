import Foundation
import Synchronization

/// What a collector parsed on earlier refreshes, so a refresh reads only files that changed. In memory
/// only: it is lost when the app quits and is not a history store (ADR: real-time view only).
final class ParseCache<Value: Sendable>: Sendable {
    private struct Entry: Sendable {
        var stamps: [FileStamp?]
        var value: Value
    }

    private let entries = Mutex<[URL: Entry]>([:])

    /// The cached value while `stamps` match the last parse, else `parse()`'s result, cached.
    func value(for url: URL, stamps: [FileStamp?], parse: () throws -> Value) rethrows -> Value {
        if let entry = entries.withLock({ $0[url] }), entry.stamps == stamps { return entry.value }
        let value = try parse()
        entries.withLock { $0[url] = Entry(stamps: stamps, value: value) }
        return value
    }

    /// Drops files the last walk no longer returned (deleted, or older than the window).
    func retain(only urls: Set<URL>) {
        entries.withLock { $0 = $0.filter { urls.contains($0.key) } }
    }
}

/// Append-only JSONL logs (Claude Code, Claude Desktop, Codex): remembers how far each file was read and
/// the parser state at that point, so a refresh parses only the bytes written since. A file that shrank,
/// was replaced, or changed without growing is parsed again from the start.
final class AppendOnlyCache<State: JSONLineConsumer & Sendable>: Sendable {
    private struct Entry: Sendable {
        var stamp: FileStamp
        var fileNumber: Int?
        var offset: UInt64
        var state: State
    }

    private let entries = Mutex<[URL: Entry]>([:])

    func state(for file: LogFile, fresh: () -> State) throws -> State {
        let previous = entries.withLock { $0[file.url] }
        if let previous, previous.stamp == file.stamp { return previous.state }

        let fileNumber = (try? FileManager.default.attributesOfItem(atPath: file.url.path))?[.systemFileNumber] as? Int
        var entry: Entry
        if let previous, previous.fileNumber == fileNumber, file.stamp.size > previous.stamp.size,
           UInt64(file.stamp.size) >= previous.offset {
            entry = previous
        } else {
            entry = Entry(stamp: file.stamp, fileNumber: fileNumber, offset: 0, state: fresh())
        }

        let handle = try FileHandle(forReadingFrom: file.url)
        defer { try? handle.close() }
        try handle.seek(toOffset: entry.offset)
        let data = try handle.readToEnd() ?? Data()
        entry.offset += UInt64(JSONLines.feed(data, to: &entry.state))
        entry.stamp = file.stamp
        entry.fileNumber = fileNumber
        entries.withLock { $0[file.url] = entry }
        return entry.state
    }

    func retain(only urls: Set<URL>) {
        entries.withLock { $0 = $0.filter { urls.contains($0.key) } }
    }
}
