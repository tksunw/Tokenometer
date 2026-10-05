import Foundation

/// Claude usage percent, read from the file the `usage-reporter` Claude Code mod writes (ADR-0004).
/// Claude Code makes the usage call itself with its own login; Tokenometer reads no credential and
/// contacts no Anthropic host.
///
/// Format version 1: `{version: 1, at, windows: [{kind: session | weekly, label?, percent, resetsAt?, at}],
/// weeklyBreakdown?: {rows: [{key, label?, percent}]}, grants?: [{id, label, used, limit?, currency, endsAt?,
/// ends?}], raw?}`. A weekly window with a `label` is scoped to that model family; `weeklyBreakdown` is the
/// weekly usage split by surface, account-wide; `grants` is every dollar credit, unknown kinds included.
/// The single-credit fields the mod also writes (`credits`, `cloudSessionCredits`, `projectSetupCredit`)
/// are not read; `grants` covers them. Knowledge of Anthropic's response
/// shape lives in the mod, not here.
public struct ClaudeUsageFile: UsageWindowSource {
    public let provider: Provider = .anthropic
    public let readsLocalFile = true
    let file: URL

    public init(file: URL = LogLocations.standard.claudeUsageFile) {
        self.file = file
    }

    public func fetchWindows() async throws -> ProviderWindows {
        guard let data = try? Data(contentsOf: file) else {
            throw UsageClientError.noReport("The usage-reporter mod for Claude Code has not reported yet")
        }
        return try Self.parse(report: data)
    }

    static func parse(report data: Data) throws -> ProviderWindows {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (root["version"] as? NSNumber)?.intValue
        else { throw UsageClientError.malformed("usage-reporter's file") }
        guard version == 1 else {
            throw UsageClientError.noReport("usage-reporter wrote format \(version); this Tokenometer reads format 1")
        }
        guard let at = Timestamps.parse(root["at"]), let list = root["windows"] as? [[String: Any]] else {
            throw UsageClientError.malformed("usage-reporter's file")
        }

        var windows = ProviderWindows(fetchedAt: at)
        for window in list {
            guard let percent = (window["percent"] as? NSNumber)?.doubleValue else { continue }
            let resets = Timestamps.parse(window["resetsAt"])
            switch (window.string("kind"), window.string("label")) {
            case ("session", nil):
                windows.session = UsageWindow(kind: .session, usedPercent: percent, resetsAt: resets, length: 5 * 3600)
            case ("weekly", nil):
                windows.weekly = UsageWindow(kind: .weekly, usedPercent: percent, resetsAt: resets, length: 7 * 86400)
            case ("weekly", let label?):
                windows.scoped.append(UsageWindow(kind: .weekly, usedPercent: percent, resetsAt: resets, length: 7 * 86400, label: "\(label) weekly"))
            default:
                continue
            }
        }
        // Every row is kept, unknown surfaces included: Anthropic can add one without a new release here.
        for row in root.dict("weeklyBreakdown")?["rows"] as? [[String: Any]] ?? [] {
            guard let key = row.string("key"), let percent = (row["percent"] as? NSNumber)?.doubleValue else { continue }
            windows.surfaces.append(SurfaceShare(key: key, label: row.string("label") ?? key, percent: percent))
        }
        // Every grant is kept, unknown kinds included, for the same reason.
        for grant in root["grants"] as? [[String: Any]] ?? [] {
            guard let id = grant.string("id"), let used = (grant["used"] as? NSNumber)?.doubleValue else { continue }
            windows.grants.append(CreditGrant(id: id, label: grant.string("label") ?? id, used: used,
                                              limit: (grant["limit"] as? NSNumber)?.doubleValue, currency: grant.string("currency") ?? "USD",
                                              endsAt: Timestamps.parse(grant["endsAt"]), ends: grant.string("ends").flatMap(CreditGrant.Ends.init)))
        }
        return windows
    }
}
