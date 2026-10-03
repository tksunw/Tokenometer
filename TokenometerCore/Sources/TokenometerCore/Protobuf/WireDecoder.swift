import Foundation

/// Schema-less protobuf wire format reader. Antigravity stores its usage as raw protobuf
/// with no published schema, so field numbers are addressed by path (see CLAUDE.md).
public enum WireValue: Sendable, Equatable {
    case varint(UInt64)
    case fixed64(UInt64)
    case fixed32(UInt32)
    case bytes(Data)
}

public struct WireField: Sendable, Equatable {
    public var number: Int
    public var value: WireValue
}

public struct WireMessage: Sendable, Equatable {
    public var fields: [WireField]

    public init(fields: [WireField]) {
        self.fields = fields
    }

    /// Parses `data` as a sequence of fields. Throws on a truncated or unknown wire type.
    public init(parsing data: Data) throws {
        var fields: [WireField] = []
        var index = data.startIndex
        let end = data.endIndex

        func readVarint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard index < end, shift < 64 else { throw WireError.truncated }
                let byte = data[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
        }

        while index < end {
            let key = try readVarint()
            let number = Int(key >> 3)
            let wireType = key & 0x7
            guard number > 0 else { throw WireError.badField }
            switch wireType {
            case 0:
                fields.append(WireField(number: number, value: .varint(try readVarint())))
            case 1:
                guard index + 8 <= end else { throw WireError.truncated }
                let raw = data[index..<index + 8].withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
                index += 8
                fields.append(WireField(number: number, value: .fixed64(UInt64(littleEndian: raw))))
            case 5:
                guard index + 4 <= end else { throw WireError.truncated }
                let raw = data[index..<index + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                index += 4
                fields.append(WireField(number: number, value: .fixed32(UInt32(littleEndian: raw))))
            case 2:
                let length = Int(try readVarint())
                guard length >= 0, index + length <= end else { throw WireError.truncated }
                fields.append(WireField(number: number, value: .bytes(Data(data[index..<index + length]))))
                index += length
            default:
                throw WireError.unsupportedWireType(Int(wireType))
            }
        }
        self.fields = fields
    }

    public func all(_ number: Int) -> [WireValue] {
        fields.filter { $0.number == number }.map(\.value)
    }

    public func first(_ number: Int) -> WireValue? {
        fields.first { $0.number == number }?.value
    }

    public func varint(_ number: Int) -> UInt64? {
        if case .varint(let v)? = first(number) { return v }
        return nil
    }

    public func int(_ number: Int) -> Int? {
        varint(number).map(Int.init)
    }

    public func string(_ number: Int) -> String? {
        if case .bytes(let d)? = first(number) { return String(data: d, encoding: .utf8) }
        return nil
    }

    public func message(_ number: Int) -> WireMessage? {
        if case .bytes(let d)? = first(number) { return try? WireMessage(parsing: d) }
        return nil
    }

    public func messages(_ number: Int) -> [WireMessage] {
        all(number).compactMap {
            if case .bytes(let d) = $0 { return try? WireMessage(parsing: d) }
            return nil
        }
    }

    /// Follows a dotted field path such as "1.4.2" through nested messages.
    public func message(path: [Int]) -> WireMessage? {
        var current = self
        for number in path {
            guard let next = current.message(number) else { return nil }
            current = next
        }
        return current
    }
}

public enum WireError: Error, Equatable {
    case truncated
    case badField
    case unsupportedWireType(Int)
}
