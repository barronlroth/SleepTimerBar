import Foundation

public enum TimerDuration: Int, CaseIterable, Identifiable, Sendable {
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90
    case oneTwenty = 120

    public var id: Int { rawValue }
    public var minutes: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    public var title: String {
        "\(rawValue) min"
    }

    public var accessibilityTitle: String {
        "\(rawValue) minutes"
    }

    public init?(minutes: Int) {
        self.init(rawValue: minutes)
    }
}
