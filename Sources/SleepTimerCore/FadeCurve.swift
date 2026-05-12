import Foundation

public enum FadeCurve: String, CaseIterable, Sendable {
    case linear
    case lateFade

    public var title: String {
        switch self {
        case .linear:
            "Linear"
        case .lateFade:
            "Late fade"
        }
    }

    public func adjustedProgress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }

        let rawProgress = min(max(elapsed / duration, 0), 1)

        switch self {
        case .linear:
            return rawProgress
        case .lateFade:
            return rawProgress * rawProgress
        }
    }
}

public enum FadeMath {
    public static func interpolatedValue(
        start: Double,
        floor: Double,
        elapsed: TimeInterval,
        duration: TimeInterval,
        curve: FadeCurve
    ) -> Double {
        let clampedStart = clamp01(start)
        let clampedFloor = min(clamp01(floor), clampedStart)
        let progress = curve.adjustedProgress(elapsed: elapsed, duration: duration)
        return clampedStart + (clampedFloor - clampedStart) * progress
    }

    public static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
