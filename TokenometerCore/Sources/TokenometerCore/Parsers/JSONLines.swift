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
