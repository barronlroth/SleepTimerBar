import Foundation

public final class AppSettings {
    private enum Key {
        static let defaultDurationMinutes = "defaultDurationMinutes"
        static let brightnessFloor = "brightnessFloor"
        static let volumeFloor = "volumeFloor"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var defaultDuration: TimerDuration {
        get {
            let storedValue = defaults.integer(forKey: Key.defaultDurationMinutes)
            return TimerDuration(minutes: storedValue) ?? .thirty
        }
        set {
            defaults.set(newValue.minutes, forKey: Key.defaultDurationMinutes)
        }
    }

    public var brightnessFloor: Double {
        get {
            storedFloor(forKey: Key.brightnessFloor)
        }
        set {
            defaults.set(FadeMath.clamp01(newValue), forKey: Key.brightnessFloor)
        }
    }

    public var volumeFloor: Double {
        get {
            storedFloor(forKey: Key.volumeFloor)
        }
        set {
            defaults.set(FadeMath.clamp01(newValue), forKey: Key.volumeFloor)
        }
    }

    private func storedFloor(forKey key: String) -> Double {
        guard defaults.object(forKey: key) != nil else { return 0 }
        return FadeMath.clamp01(defaults.double(forKey: key))
    }
}
