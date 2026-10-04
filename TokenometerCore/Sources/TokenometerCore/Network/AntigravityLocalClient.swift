import Foundation

/// Google usage windows from the Antigravity hub's local language server (ADR-0003).
///
/// Antigravity (the hub app, the IDE, and the `agy` CLI) runs a `language_server` process on
/// localhost that serves Connect-JSON RPCs. `RetrieveUserQuotaSummary` returns the same grouped
/// quota the IDE and `agy` display: a "Gemini Models" group and a "Claude and GPT models" group,
/// each with a weekly and a 5-hour bucket. The process is found by its command line, which also
/// carries the CSRF token the server requires. Nothing here leaves the machine.
public struct AntigravityLocalClient: UsageWindowSource {
    public let provider: Provider = .google
    static let service = "exa.language_server_pb.LanguageServerService"

    let transport: any HTTPTransport
    let processes: @Sendable () throws -> [LanguageServer]

    public init(transport: any HTTPTransport = URLSessionTransport.loopback, processes: @escaping @Sendable () throws -> [LanguageServer] = LanguageServer.running) {
        self.transport = transport
        self.processes = processes
    }

    public func fetchWindows() async throws -> ProviderWindows {
        let servers = try processes()
        guard !servers.isEmpty else { throw UsageClientError.noCredentials("Antigravity is not running") }
        var lastError: any Error = UsageClientError.noCredentials("Antigravity language server did not answer")
        for server in servers {
            for port in server.ports {
                do {
                    let summary = try await call("RetrieveUserQuotaSummary", port: port, token: server.csrfToken)
                    var windows = try Self.parse(summary: summary, now: .now)
                    if let status = try? await call("GetUserStatus", port: port, token: server.csrfToken) {
                        windows.planName = status.dict("userStatus")?.dict("planStatus")?.dict("planInfo")?.string("planName")
                    }
                    return windows
                } catch {
                    lastError = error
                }
            }
        }
        throw lastError
    }

    /// Gemini group becomes session and weekly; every other group's buckets are scoped windows.
    public static func parse(summary root: [String: Any], now: Date) throws -> ProviderWindows {
        guard let groups = root.dict("response")?["groups"] as? [[String: Any]], !groups.isEmpty else {
            throw UsageClientError.malformed("Antigravity quota summary")
        }
        var windows = ProviderWindows(fetchedAt: now)
        for (index, group) in groups.enumerated() {
            let groupName = Self.shortName(group.string("displayName") ?? "Group \(index + 1)")
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard let remaining = bucket["remainingFraction"] as? NSNumber else { continue }
                let isWeekly = bucket.string("window") == "weekly"
                let window = UsageWindow(
                    kind: isWeekly ? .weekly : .session,
                    usedPercent: (1 - remaining.doubleValue) * 100,
                    resetsAt: Timestamps.parse(bucket["resetTime"]),
                    length: isWeekly ? 7 * 86400 : 5 * 3600,
                    label: "\(groupName) \(isWeekly ? "weekly" : "session")"
                )
                if index == 0 {
                    if isWeekly { windows.weekly = window } else { windows.session = window }
                } else {
                    windows.scoped.append(window)
                }
            }
        }
        return windows
    }

    /// "Gemini Models" -> "Gemini", "Claude and GPT models" -> "Claude & GPT". Short enough for a widget row.
    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: " models", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " and ", with: " & ")
            .trimmingCharacters(in: .whitespaces)
    }

    private func call(_ method: String, port: Int, token: String) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/\(Self.service)/\(method)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        request.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await transport.send(request)
        guard response.statusCode == 200 else { throw UsageClientError.http(response.statusCode) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.malformed("Antigravity \(method) response")
        }
        return root
    }
}

/// A running Antigravity `language_server` process: its CSRF token and listening localhost ports.
public struct LanguageServer: Sendable, Equatable {
    public var pid: Int32
    public var csrfToken: String
    public var ports: [Int]
    public var isHub: Bool

    public init(pid: Int32, csrfToken: String, ports: [Int], isHub: Bool) {
        self.pid = pid
        self.csrfToken = csrfToken
        self.ports = ports
        self.isHub = isHub
    }

    /// Finds language servers via `ps` and their listening ports via `lsof`. The hub app's server
    /// is preferred because it stays up while the IDE and CLI come and go.
    @Sendable public static func running() throws -> [LanguageServer] {
        let listing = try run("/bin/ps", ["-axo", "pid=,uid=,command="])
        return parse(listing: listing, uid: getuid()) { (try? listeningPorts(pid: $0)) ?? [] }
    }

    /// Language servers in a `ps -o pid=,uid=,command=` listing. `ps -ax` lists every account's
    /// processes, so only those running as `uid` count: another user on this Mac could otherwise
    /// start a look-alike and have its numbers shown here.
    static func parse(listing: String, uid: uid_t, ports: (Int32) -> [Int]) -> [LanguageServer] {
        var servers: [LanguageServer] = []
        for line in listing.split(separator: "\n") {
            guard line.contains("language_server"), line.contains("--csrf_token") else { continue }
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count > 2, let pid = Int32(parts[0]), uid_t(parts[1]) == uid else { continue }
            guard let token = flagValue("--csrf_token", in: parts) else { continue }
            let isHub = flagValue("--subclient_type", in: parts) == "hub"
            servers.append(LanguageServer(pid: pid, csrfToken: token, ports: ports(pid), isHub: isHub))
        }
        return servers.sorted { $0.isHub && !$1.isHub }
    }

    static func flagValue(_ flag: String, in parts: [String]) -> String? {
        for (index, part) in parts.enumerated() {
            if part == flag, index + 1 < parts.count { return parts[index + 1] }
            if part.hasPrefix(flag + "=") { return String(part.dropFirst(flag.count + 1)) }
        }
        return nil
    }

    static func listeningPorts(pid: Int32) throws -> [Int] {
        let output = try run("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-Fn"])
        return output.split(separator: "\n").compactMap { line -> Int? in
            guard line.hasPrefix("n"), let colon = line.lastIndex(of: ":") else { return nil }
            return Int(line[line.index(after: colon)...])
        }
    }

    /// Runs a tool and returns its stdout. Stderr is discarded rather than piped, since a full pipe
    /// nobody reads would block the child, and the child is terminated after `timeout` so a stuck
    /// `lsof` cannot hold up the refresh.
    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let pid = process.processIdentifier
        let deadline = DispatchWorkItem { kill(pid, SIGTERM) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}
