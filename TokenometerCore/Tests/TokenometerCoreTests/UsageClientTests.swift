import Foundation
import Testing
@testable import TokenometerCore

private struct StubTransport: HTTPTransport {
    let responses: [String: (Int, String)]  // keyed by URL suffix

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!.absoluteString
        guard let match = responses.first(where: { url.hasSuffix($0.key) }) else { throw UsageClientError.badResponse }
        let response = HTTPURLResponse(url: request.url!, statusCode: match.value.0, httpVersion: nil, headerFields: nil)!
        return (Data(match.value.1.utf8), response)
    }
}

@Suite struct ClaudeUsageFileTests {
    private func report(_ json: String) throws -> ClaudeUsageFile {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try json.write(to: file, atomically: true, encoding: .utf8)
        return ClaudeUsageFile(file: file)
    }

    @Test func readsFormatOne() async throws {
        let json = #"{"version":1,"at":"2026-10-03T05:00:00.000Z","windows":[{"kind":"session","percent":24,"resetsAt":"2026-10-03T06:00:00.000Z","at":"2026-10-03T05:00:00.000Z"},{"kind":"weekly","percent":5,"resetsAt":"2026-10-04T23:00:00.000Z","at":"2026-10-03T04:58:00.000Z"},{"kind":"weekly","label":"Fable","percent":41,"at":"2026-10-03T04:58:00.000Z"},{"kind":"monthly","percent":9}],"raw":{"limits":[]}}"#
        let windows = try await report(json).fetchWindows()
        #expect(windows.session?.usedPercent == 24)
        #expect(windows.session?.length == 18000)
        #expect(windows.session?.resetsAt == Date(timeIntervalSince1970: 1_791_007_200))
        #expect(windows.weekly?.usedPercent == 5)
        #expect(windows.scoped.map(\.label) == ["Fable weekly"])
        #expect(windows.scoped.first?.usedPercent == 41)
        #expect(windows.scoped.first?.resetsAt == nil)
        #expect(windows.fetchedAt == Date(timeIntervalSince1970: 1_791_003_600))
    }

    @Test func newerFormatSaysSoInsteadOfGuessing() async throws {
        let client = try report(#"{"version":2,"at":"2026-10-03T05:00:00.000Z","windows":[]}"#)
        await #expect(throws: UsageClientError.noReport("usage-reporter wrote format 2; this Tokenometer reads format 1")) { try await client.fetchWindows() }
    }

    @Test func missingFileSaysTheModHasNotReported() async {
        let client = ClaudeUsageFile(file: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        await #expect(throws: UsageClientError.noReport("The usage-reporter mod for Claude Code has not reported yet")) { try await client.fetchWindows() }
    }
}

@Suite struct AntigravityLocalClientTests {
    let summary = #"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"gemini-weekly","window":"weekly","remainingFraction":0.9742,"resetTime":"2026-10-09T22:24:20Z"},{"bucketId":"gemini-5h","window":"5h","remainingFraction":0.9949,"resetTime":"2026-10-03T03:24:20Z"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"3p-weekly","window":"weekly","remainingFraction":1,"resetTime":"2026-10-09T22:24:20Z"},{"bucketId":"3p-5h","window":"5h","remainingFraction":1,"resetTime":"2026-10-03T03:24:20Z"}]}]}}"#

    @Test func firstGroupIsSessionAndWeeklyOthersAreScoped() throws {
        let root = try JSONSerialization.jsonObject(with: Data(summary.utf8)) as! [String: Any]
        let windows = try AntigravityLocalClient.parse(summary: root, now: .now)
        #expect(abs((windows.session?.usedPercent ?? 0) - 0.51) < 1e-6)
        #expect(abs((windows.weekly?.usedPercent ?? 0) - 2.58) < 1e-6)
        #expect(windows.session?.label == "Gemini session")
        #expect(windows.weekly?.length == 604800.0)
        #expect(windows.scoped.map(\.label) == ["Claude & GPT weekly", "Claude & GPT session"])
        #expect(windows.scoped.first?.usedPercent == 0)
    }

    @Test func fetchUsesFirstAnsweringPortAndReadsPlan() async throws {
        let transport = StubTransport(responses: [
            ":61010/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary": (200, summary),
            ":61010/exa.language_server_pb.LanguageServerService/GetUserStatus": (200, #"{"userStatus":{"planStatus":{"planInfo":{"planName":"Pro"}}}}"#),
            ":61009/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary": (400, "Client sent an HTTP request to an HTTPS server."),
        ])
        let client = AntigravityLocalClient(transport: transport) {
            [LanguageServer(pid: 1, csrfToken: "t", ports: [61009, 61010], isHub: true)]
        }
        let windows = try await client.fetchWindows()
        #expect(windows.planName == "Pro")
        #expect(windows.scoped.count == 2)
    }

    @Test func notRunningIsAPlainReason() async {
        let client = AntigravityLocalClient(transport: StubTransport(responses: [:])) { [] }
        await #expect(throws: UsageClientError.noCredentials("Antigravity is not running")) { try await client.fetchWindows() }
    }

    @Test func flagParsingHandlesBothForms() {
        #expect(LanguageServer.flagValue("--csrf_token", in: ["x", "--csrf_token", "abc"]) == "abc")
        #expect(LanguageServer.flagValue("--csrf_token", in: ["x", "--csrf_token=abc"]) == "abc")
        #expect(LanguageServer.flagValue("--csrf_token", in: ["x"]) == nil)
    }
}
