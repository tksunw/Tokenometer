import Foundation
import TokenometerCore

// Diagnostic CLI: runs the same collectors and usage clients as the app and prints what it found.
// `swift run tokenometerctl` for a summary, `swift run tokenometerctl --json` for the full snapshot.
let json = CommandLine.arguments.contains("--json")
let skipNetwork = CommandLine.arguments.contains("--no-network")

if CommandLine.arguments.contains("--collectors") {
    for collector in Collectors.all() {
        let present = collector.isPresent()
        let result = present ? collector.collect(modifiedAfter: nil) : CollectorResult()
        print("\(collector.tool.displayName): present=\(present) records=\(result.records.count) failures=\(result.failures.count)")
        for (url, error) in result.failures.prefix(3) { print("  \(url.lastPathComponent): \(error)") }
    }
    exit(0)
}

if CommandLine.arguments.contains("--claude-raw") {
    // Prints what the usage-reporter mod last wrote (no secrets in it), `raw` included, for parser work.
    print(try String(contentsOf: LogLocations.standard.claudeUsageFile, encoding: .utf8))
    exit(0)
}

if CommandLine.arguments.contains("--google") {
    // Asks only the running Antigravity language server on localhost.
    do {
        let windows = try await AntigravityLocalClient().fetchWindows()
        print("plan: \(windows.planName ?? "-")")
        for w in [windows.session, windows.weekly].compactMap({ $0 }) + windows.scoped {
            print("\(w.label ?? w.kind.rawValue): \(String(format: "%.2f", w.usedPercent))% resets \(w.resetsAt?.description ?? "-")")
        }
    } catch {
        print("error: \(error)")
    }
    exit(0)
}

let refresher = UsageRefresher(collectors: Collectors.all(), windowSources: [ClaudeUsageFile(), AntigravityLocalClient()])
let snapshot = await refresher.refresh(settings: EngineSettings(), fetchWindows: !skipNetwork)

if json {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
} else {
    print("generated \(snapshot.generatedAt)")
    for p in snapshot.providers {
        func pct(_ w: UsageWindow?) -> String { w.map { "\(Int($0.usedPercent.rounded()))%" } ?? "-" }
        print("\(p.provider.displayName) [\(p.accountKind)\(p.planName.map { " \($0)" } ?? "")] session \(pct(p.session)) weekly \(pct(p.weekly))")
        print("  spend session \(p.sessionSpend.tokens.total) tok $\(String(format: "%.2f", p.sessionSpend.costUSD)) | week \(p.weeklySpend.tokens.total) tok $\(String(format: "%.2f", p.weeklySpend.costUSD))\(p.weeklySpend.hasUnknownCost ? " (+unpriced)" : "")")
        for t in p.tools { print("  \(t.tool.displayName): week \(t.weekly.tokens.total) tok, \(t.weekly.calls) calls") }
        for m in p.models.prefix(6) { print("    \(m.model): \(m.weekly.tokens.total) tok") }
        if let surfaces = p.surfaces { print("  by surface, whole account: " + surfaces.map { "\($0.label) \(Int($0.percent.rounded()))%" }.joined(separator: ", ")) }
        if let s = p.windowsStale { print("  windows stale: \(s.reason)") }
        if let s = p.spendStale { print("  spend stale: \(s.reason)") }
    }
}
