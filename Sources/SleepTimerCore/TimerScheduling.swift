import Foundation

@MainActor
public protocol SleepTimerClock {
    var now: TimeInterval { get }
    var date: Date { get }
}

@MainActor
public final class MonotonicTimerClock: SleepTimerClock {
    private let origin = ContinuousClock.now

    public init() {}

    public var now: TimeInterval {
        let components = origin.duration(to: .now).components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    public var date: Date { Date() }
}

@MainActor
public protocol SleepTimerScheduling {
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void)
    func cancel()
}

@MainActor
public final class RunLoopTimerScheduler: SleepTimerScheduling {
    private var timer: Timer?

    public init() {}

    public func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        cancel()
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
