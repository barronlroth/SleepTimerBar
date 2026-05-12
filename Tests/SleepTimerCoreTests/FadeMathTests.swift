import Testing
@testable import SleepTimerCore

@Suite("Fade math")
struct FadeMathTests {
    @Test("Linear fade reaches the midpoint halfway through")
    func linearFadeMidpoint() {
        let value = FadeMath.interpolatedValue(
            start: 1,
            floor: 0,
            elapsed: 30,
            duration: 60,
            curve: .linear
        )

        #expect(abs(value - 0.5) < 0.0001)
    }

    @Test("Fade clamps start and floor")
    func fadeClampsValues() {
        let value = FadeMath.interpolatedValue(
            start: 2,
            floor: -1,
            elapsed: 60,
            duration: 60,
            curve: .linear
        )

        #expect(value == 0)
    }

    @Test("Late fade stays higher than linear before the end")
    func lateFadeStaysHigherEarly() {
        let linear = FadeMath.interpolatedValue(
            start: 1,
            floor: 0,
            elapsed: 30,
            duration: 60,
            curve: .linear
        )
        let lateFade = FadeMath.interpolatedValue(
            start: 1,
            floor: 0,
            elapsed: 30,
            duration: 60,
            curve: .lateFade
        )

        #expect(lateFade > linear)
    }
}
