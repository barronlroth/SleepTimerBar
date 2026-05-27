import Foundation

struct FadeChannel {
    private static let externalChangeThreshold = 0.015

    let floor: Double
    let curve: FadeCurve

    private var anchorValue: Double
    private var anchorDate: Date
    private var lastAppliedValue: Double

    init(currentValue: Double, floor: Double, curve: FadeCurve, date: Date) {
        let clampedCurrentValue = FadeMath.clamp01(currentValue)

        self.floor = FadeMath.clamp01(floor)
        self.curve = curve
        self.anchorValue = clampedCurrentValue
        self.anchorDate = date
        self.lastAppliedValue = clampedCurrentValue
    }

    mutating func rebaseIfExternalChange(currentValue: Double, at date: Date) {
        let clampedCurrentValue = FadeMath.clamp01(currentValue)
        guard abs(clampedCurrentValue - lastAppliedValue) > Self.externalChangeThreshold else {
            return
        }

        anchorValue = clampedCurrentValue
        anchorDate = date
        lastAppliedValue = clampedCurrentValue
    }

    func value(at date: Date, endsAt: Date) -> Double {
        FadeMath.interpolatedValue(
            start: anchorValue,
            floor: floor,
            elapsed: date.timeIntervalSince(anchorDate),
            duration: endsAt.timeIntervalSince(anchorDate),
            curve: curve
        )
    }

    mutating func markApplied(_ value: Double) {
        lastAppliedValue = FadeMath.clamp01(value)
    }
}
