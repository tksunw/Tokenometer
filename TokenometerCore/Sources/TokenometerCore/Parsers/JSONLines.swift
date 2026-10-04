import Foundation

/// Line-oriented JSON helpers shared by the JSONL parsers. Malformed lines are skipped, never fatal:
/// agents append to these files while we read them, so a torn last line is normal.
enum JSONLines {
    static func objects(in url: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: url)
        return objects(in: data)
    }

    static func objects(in data: Data) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            result.append(object)
        }
        return result
    }

    static func object(in url: URL) throws -> [String: Any]? {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Feeds each complete line to `consumer`, deserializing only the lines it `wants`, and returns the
    /// number of bytes consumed: through the last newline, plus an unterminated last line that is wanted
    /// and already parses. Anything after that is a line still being written; the next read starts there.
    static func feed<Consumer: JSONLineConsumer>(_ data: Data, to consumer: inout Consumer) -> Int {
        let newline = UInt8(ascii: "\n")
        var start = data.startIndex
        while let end = data[start...].firstIndex(of: newline) {
            let line = data[start..<end]
            if !line.isEmpty, consumer.wants(line),
               let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                consumer.consume(object)
            }
            start = end + 1
        }
        let tail = data[start...]
        if !tail.isEmpty, consumer.wants(tail),
           let object = try? JSONSerialization.jsonObject(with: Data(tail)) as? [String: Any] {
            consumer.consume(object)
            start = data.endIndex
        }
        return start - data.startIndex
    }
}

/// A JSONL parser that takes one object at a time, so it can resume where the last read stopped.
protocol JSONLineConsumer {
    /// A cheap byte test run before deserializing; a line it rejects is skipped unparsed. It may pass
    /// lines the parser then ignores, never the reverse.
    func wants(_ line: Data) -> Bool
    mutating func consume(_ object: [String: Any])
}

enum Timestamps {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    static func parse(_ value: Any?) -> Date? {
        switch value {
        case let s as String:
            return (try? fractional.parse(s)) ?? (try? whole.parse(s))
        case let n as NSNumber:
            let d = n.doubleValue
            return Date(timeIntervalSince1970: d > 1e12 ? d / 1000 : d)
        default:
            return nil
        }
    }
}

extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int {
        (self[key] as? NSNumber)?.intValue ?? 0
    }

    func dict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }
}
