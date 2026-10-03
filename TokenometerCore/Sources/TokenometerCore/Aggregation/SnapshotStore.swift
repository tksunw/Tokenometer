import Foundation

/// JSON file in the App Group container. The app writes it after every refresh; the widget reads it.
public struct SnapshotStore: Sendable {
    /// Team-prefixed so Developer ID builds need no provisioning profile for the App Group entitlement.
    public static let appGroup = "F5ED28X889.net.timkennedy.tokenometer"

    public let fileURL: URL

    public init(appGroup: String = SnapshotStore.appGroup) {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.temporaryDirectory
        fileURL = container.appendingPathComponent("snapshot.json")
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Snapshot.self, from: data)
    }

    public func save(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
