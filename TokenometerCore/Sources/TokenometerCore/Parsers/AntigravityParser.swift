import Foundation
import SQLite3

/// Parses an Antigravity conversation database (`~/.gemini/antigravity/conversations/<id>.db`).
///
/// Usage lives in `steps.metadata` for `step_type = 15` rows as raw protobuf: field 1 is a Timestamp
/// (seconds, nanos), field 9 the usage message (1 model enum, 2 input, 3 output, 5 cache read, 9 thinking).
/// The model name string sits in `gen_metadata.data` at path 1.19, one row per model call in the same
/// order. Field numbers were inferred from live data, not a schema, so treat this parser as experimental.
public enum AntigravityParser {
    public static func parse(databaseURL: URL) throws -> [UsageRecord] {
        // The live database is in WAL mode and the IDE holds it open. Reading a copy of all three
        // files is simpler than negotiating shared locks with a read-only handle.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenometer-antigravity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let copy = scratch.appendingPathComponent(databaseURL.lastPathComponent)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: databaseURL.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }
        return try parse(copiedDatabase: copy, sessionID: databaseURL.deletingPathExtension().lastPathComponent)
    }

    static func parse(copiedDatabase url: URL, sessionID: String) throws -> [UsageRecord] {
        // The database is in WAL journal mode, which needs a writable -shm file even for readers.
        // This is our private copy, so a read-write connection is safe; the original is never touched.
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            throw AntigravityError.cannotOpen(url)
        }
        defer { sqlite3_close(db) }
        guard let steps = try? Self.check(db, sql: "SELECT count(*) FROM steps") else {
            throw AntigravityError.cannotRead(url, String(cString: sqlite3_errmsg(db)))
        }
        _ = steps

        let modelNames = blobs(db, sql: "SELECT data FROM gen_metadata ORDER BY idx").map { data -> String? in
            guard let message = try? WireMessage(parsing: data) else { return nil }
            return message.message(1)?.string(19)
        }

        var records: [UsageRecord] = []
        for (ordinal, (idx, data)) in rows(db, sql: "SELECT idx, metadata FROM steps WHERE step_type = 15 AND metadata IS NOT NULL ORDER BY idx").enumerated() {
            guard let meta = try? WireMessage(parsing: data),
                  let usage = meta.message(9),
                  let seconds = meta.message(1)?.int(1)
            else { continue }
            // A negative count is corrupt data, not usage.
            let count = { (field: Int) in max(0, usage.int(field) ?? 0) }
            let counts = TokenCounts(
                input: count(2),
                output: count(3),
                cacheRead: count(5),
                thinking: count(9)
            )
            guard counts.total > 0 else { continue }
            let modelEnum = usage.int(1) ?? meta.int(11) ?? 0
            let name = ordinal < modelNames.count ? modelNames[ordinal] : nil
            records.append(UsageRecord(
                id: "\(sessionID)/\(idx)",
                tool: .antigravity,
                model: name ?? "antigravity-model-\(modelEnum)",
                timestamp: Date(timeIntervalSince1970: TimeInterval(seconds)),
                tokens: counts,
                sessionID: sessionID
            ))
        }
        return records
    }

    /// Runs a probe statement so a failed open surfaces as an error instead of an empty result.
    private static func check(_ db: OpaquePointer, sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else { throw AntigravityError.probeFailed }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw AntigravityError.probeFailed }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func blobs(_ db: OpaquePointer, sql: String) -> [Data] {
        rows(db, sql: sql).map(\.1)
    }

    private static func rows(_ db: OpaquePointer, sql: String) -> [(Int, Data)] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else { return [] }
        defer { sqlite3_finalize(stmt) }
        let columns = sqlite3_column_count(stmt)
        var result: [(Int, Data)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let blobColumn = columns - 1
            let idx = columns > 1 ? Int(sqlite3_column_int64(stmt, 0)) : result.count
            let length = Int(sqlite3_column_bytes(stmt, blobColumn))
            guard length > 0, let bytes = sqlite3_column_blob(stmt, blobColumn) else { continue }
            result.append((idx, Data(bytes: bytes, count: length)))
        }
        return result
    }
}

public enum AntigravityError: Error {
    case cannotOpen(URL)
    case cannotRead(URL, String)
    case probeFailed
}
