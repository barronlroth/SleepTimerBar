import Foundation
import Testing
@testable import SleepTimerCore

@Suite("Fade channel")
struct FadeChannelTests {
    @Test("External changes rebase the fade over remaining time")
    func externalChangeRebasesFade() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let endsAt = Date(timeIntervalSinceReferenceDate: 100)
        let halfway = Date(timeIntervalSinceReferenceDate: 50)
        let threeQuarters = Date(timeIntervalSinceReferenceDate: 75)

        var channel = FadeChannel(currentValue: 1, floor: 0, curve: .linear, date: startedAt)
        channel.markApplied(0.5)
        channel.rebaseIfExternalChange(currentValue: 0.8, at: halfway)

        let value = channel.value(at: threeQuarters, endsAt: endsAt)

        #expect(abs(value - 0.4) < 0.0001)
    }

    @Test("Small differences from the last app-applied value do not rebase")
    func smallDifferencesDoNotRebase() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let endsAt = Date(timeIntervalSinceReferenceDate: 100)
        let halfway = Date(timeIntervalSinceReferenceDate: 50)
        let threeQuarters = Date(timeIntervalSinceReferenceDate: 75)

        var channel = FadeChannel(currentValue: 1, floor: 0, curve: .linear, date: startedAt)
        channel.markApplied(0.5)
        channel.rebaseIfExternalChange(currentValue: 0.505, at: halfway)

        let value = channel.value(at: threeQuarters, endsAt: endsAt)

        #expect(abs(value - 0.25) < 0.0001)
    }

    @Test("Manual values below the floor are preserved")
    func valuesBelowFloorArePreserved() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 0)
        let endsAt = Date(timeIntervalSinceReferenceDate: 100)
        let halfway = Date(timeIntervalSinceReferenceDate: 50)
        let threeQuarters = Date(timeIntervalSinceReferenceDate: 75)

        var channel = FadeChannel(currentValue: 1, floor: 0.2, curve: .linear, date: startedAt)
        channel.markApplied(0.6)
        channel.rebaseIfExternalChange(currentValue: 0.1, at: halfway)

        let value = channel.value(at: threeQuarters, endsAt: endsAt)

        #expect(abs(value - 0.1) < 0.0001)
    }
}
