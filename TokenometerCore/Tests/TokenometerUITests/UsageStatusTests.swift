import Foundation
import Testing
import TokenometerCore
@testable import TokenometerUI

@Suite struct UsageStatusTests {
    @Test func behindOrOnThePaceLineIsOk() {
        #expect(UsageStatus.of(percent: 42, pace: 0.73) == .ok)
        #expect(UsageStatus.of(percent: 61, pace: 0.61) == .ok)
    }

    @Test func aSmallLeadStaysGreen() {
        // The floor: under 10 points ahead of the clock is not worth a color change.
        #expect(UsageStatus.of(percent: 4, pace: 0.03) == .ok)
        #expect(UsageStatus.of(percent: 40, pace: 0.31) == .ok)
    }

    @Test func tenPointsAheadIsCaution() {
        #expect(UsageStatus.of(percent: 61, pace: 0.51) == .caution)
        #expect(UsageStatus.of(percent: 73, pace: 0.38) == .caution)
    }

    @Test func pastTheLineAtNinetyIsCriticalWhateverTheLead() {
        #expect(UsageStatus.of(percent: 94, pace: 0.66) == .critical)
        // Only 3 points ahead, but at 90% or more it is time to wrap up.
        #expect(UsageStatus.of(percent: 91, pace: 0.88) == .critical)
    }

    @Test func ninetyPercentBehindThePaceLineIsNotCritical() {
        // Late in a window, 92% used with 95% of the time gone is on schedule.
        #expect(UsageStatus.of(percent: 92, pace: 0.95) == .ok)
    }

    @Test func withoutAPaceTheAbsoluteThresholdsApply() {
        #expect(UsageStatus.of(percent: 50, pace: nil) == .ok)
        #expect(UsageStatus.of(percent: 80, pace: nil) == .caution)
        #expect(UsageStatus.of(percent: 95, pace: nil) == .critical)
    }

    @Test func elapsedShareFollowsTheClock() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        // 1 h 21 m left of a 5 h session: 3 h 39 m gone, 73%.
        let window = UsageWindow(kind: .session, usedPercent: 42, resetsAt: now.addingTimeInterval(81 * 60), length: 5 * 3600)
        #expect(Format.elapsed(window, now: now) == "73%")
        #expect(Format.remaining(window, now: now) == "in 1 h 21 m")
        #expect(Format.elapsed(UsageWindow(kind: .session, usedPercent: 10), now: now) == nil)
    }

    @Test func remainingSwitchesToDaysBeyondOneDay() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let window = UsageWindow(kind: .weekly, usedPercent: 61, resetsAt: now.addingTimeInterval(56 * 3600 + 32 * 60), length: 7 * 86400)
        #expect(Format.remaining(window, now: now) == "in 2 d 8 h")
    }

    @Test func aPaletteChangeCountsAsNewContent() {
        let now = Date.now
        let standard = Snapshot(generatedAt: now, providers: [], palette: "trafficLight")
        let colorBlind = Snapshot(generatedAt: now, providers: [], palette: "colorBlind")
        #expect(!colorBlind.hasSameContent(as: standard))
        #expect(standard.hasSameContent(as: Snapshot(generatedAt: now.addingTimeInterval(60), providers: [], palette: "trafficLight")))
    }

    @Test func anOldSnapshotFileWithoutAPaletteStillDecodes() throws {
        let json = #"{"version":1,"generatedAt":0,"providers":[]}"#
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        #expect(snapshot.palette == nil)
    }

    @Test func windowRowsOrderSessionWeeklyScoped() {
        let session = UsageWindow(kind: .session, usedPercent: 1)
        let weekly = UsageWindow(kind: .weekly, usedPercent: 2)
        let fable = UsageWindow(kind: .weekly, usedPercent: 3, label: "Fable weekly")
        let provider = ProviderSnapshot(provider: .anthropic, accountKind: .plan, session: session, weekly: weekly, scoped: [fable])
        #expect(provider.windowRows.map(\.label) == ["Session", "All models weekly", "Fable weekly"])
        let alone = ProviderSnapshot(provider: .openAI, accountKind: .plan, session: session, weekly: weekly)
        #expect(alone.windowRows.map(\.label) == ["Session", "Weekly"])
    }

    @Test func providerPaletteIgnoresStatus() {
        for status in [UsageStatus.ok, .caution, .critical] {
            #expect(StatusPalette.provider.color(status, .dark, provider: .openAI) == Provider.openAI.color)
        }
        // The other palettes ignore the provider.
        #expect(StatusPalette.trafficLight.color(.ok, .dark, provider: .openAI) == StatusPalette.trafficLight.color(.ok, .dark))
    }

    @Test func paletteNamesDecodeIncludingTheOldDevelopmentName() {
        #expect(PaletteChoice(stored: "standard") == .trafficLight)
        #expect(PaletteChoice(stored: "colorBlind") == .colorBlind)
        #expect(PaletteChoice(stored: "provider") == .provider)
        #expect(PaletteChoice(stored: nil) == .trafficLight)
    }

    @Test func stampingTagsEveryWindowWithItsProvider() {
        let provider = ProviderSnapshot(provider: .google, accountKind: .plan,
                                        session: UsageWindow(kind: .session, usedPercent: 1), weekly: UsageWindow(kind: .weekly, usedPercent: 2),
                                        scoped: [UsageWindow(kind: .weekly, usedPercent: 3, label: "x")])
        let stamped = Snapshot(generatedAt: .now, providers: [provider]).stamped().providers[0]
        #expect(stamped.windowRows.allSatisfy { $0.window.provider == .google })
    }
}
