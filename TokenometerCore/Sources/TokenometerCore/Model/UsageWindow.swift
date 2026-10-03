import Foundation

public enum WindowKind: String, Codable, Sendable, CaseIterable {
    case session
    case weekly
}

/// A provider's rolling allowance window as the provider reports it.
public struct UsageWindow: Codable, Sendable, Equatable {
    public var kind: WindowKind
    /// 0 to 100.
    public var usedPercent: Double
    public var resetsAt: Date?
    public var length: TimeInterval?
    /// Set on model-scoped windows, e.g. "Fable" for Claude's per-model weekly cap.
    public var label: String?

    public init(kind: WindowKind, usedPercent: Double, resetsAt: Date? = nil, length: TimeInterval? = nil, label: String? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.length = length
        self.label = label
    }

    /// Start of the window when both reset time and length are known, else nil.
    public var startsAt: Date? {
        guard let resetsAt, let length else { return nil }
        return resetsAt.addingTimeInterval(-length)
    }

    /// Fraction of the window already elapsed, 0 to 1, when the reset time and length are known.
    /// Drives the pace marker: usage at or behind this fraction is never alarming.
    public func elapsedFraction(now: Date = .now) -> Double? {
        guard let resetsAt, let length, length > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(1, max(0, 1 - remaining / length))
    }
}

/// Plan accounts have usage windows; metered accounts are billed per token and have none.
public enum AccountKind: String, Codable, Sendable {
    case plan
    case metered
}
