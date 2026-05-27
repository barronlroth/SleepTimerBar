import Foundation

public struct SleepTimerSnapshot: Equatable, Sendable {
    public let duration: TimerDuration
    public let startedAt: Date
    public let endsAt: Date

    public var totalSeconds: TimeInterval {
        endsAt.timeIntervalSince(startedAt)
    }

    public func remainingSeconds(at date: Date = Date()) -> TimeInterval {
        max(endsAt.timeIntervalSince(date), 0)
    }
}

public enum SleepTimerState: Equatable, Sendable {
    case idle
    case running(SleepTimerSnapshot)
}

private struct SleepTimerSession {
    let snapshot: SleepTimerSnapshot
    var brightness: FadeChannel?
    var volume: FadeChannel?
}

@MainActor
public final class SleepTimerController {
    public private(set) var state: SleepTimerState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }

    public var onStateChanged: ((SleepTimerState) -> Void)?
    public var onError: ((String) -> Void)?

    private let settings: AppSettings
    private let brightnessController: DisplayBrightnessControlling
    private let volumeController: VolumeControlling
    private let sleepController: SystemSleepControlling
    private let updateInterval: TimeInterval

    private var session: SleepTimerSession?
    private var updateTimer: Timer?
    private var brightnessFailed = false
    private var volumeFailed = false

    public init(
        settings: AppSettings,
        brightnessController: DisplayBrightnessControlling = DisplayBrightnessController(),
        volumeController: VolumeControlling = VolumeController(),
        sleepController: SystemSleepControlling = SystemSleepController(),
        updateInterval: TimeInterval = 5
    ) {
        self.settings = settings
        self.brightnessController = brightnessController
        self.volumeController = volumeController
        self.sleepController = sleepController
        self.updateInterval = updateInterval
    }

    public func toggleDefaultTimer() {
        switch state {
        case .idle:
            start(duration: settings.defaultDuration)
        case .running:
            cancel()
        }
    }

    public func start(duration: TimerDuration) {
        cancel(sendStateUpdate: false)

        let startedAt = Date()
        let endsAt = startedAt.addingTimeInterval(duration.seconds)
        let snapshot = SleepTimerSnapshot(duration: duration, startedAt: startedAt, endsAt: endsAt)

        brightnessFailed = false
        volumeFailed = false

        let initialBrightness = readInitialBrightness().map {
            FadeChannel(
                currentValue: $0,
                floor: settings.brightnessFloor,
                curve: .linear,
                date: startedAt
            )
        }
        let initialVolume = readInitialVolume().map {
            FadeChannel(
                currentValue: $0,
                floor: settings.volumeFloor,
                curve: .linear,
                date: startedAt
            )
        }

        session = SleepTimerSession(
            snapshot: snapshot,
            brightness: initialBrightness,
            volume: initialVolume
        )

        state = .running(snapshot)
        scheduleTimer()
        tick()
    }

    public func cancel() {
        cancel(sendStateUpdate: true)
    }

    private func cancel(sendStateUpdate: Bool) {
        updateTimer?.invalidate()
        updateTimer = nil
        session = nil
        brightnessFailed = false
        volumeFailed = false

        if sendStateUpdate {
            state = .idle
        } else {
            state = .idle
        }
    }

    private func scheduleTimer() {
        updateTimer?.invalidate()
        let timer = Timer(timeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        updateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick(date: Date = Date()) {
        guard let session else { return }

        let elapsed = date.timeIntervalSince(session.snapshot.startedAt)
        let duration = session.snapshot.totalSeconds

        guard elapsed < duration else {
            complete()
            return
        }

        applyFade(date: date)
    }

    private func complete() {
        if let session {
            applyFade(date: session.snapshot.endsAt)
        }

        updateTimer?.invalidate()
        updateTimer = nil
        self.session = nil
        state = .idle

        do {
            try sleepController.sleepNow()
        } catch {
            onError?((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func applyFade(date: Date) {
        guard var session else { return }

        if !brightnessFailed, var brightness = session.brightness {
            do {
                let currentBrightness = try brightnessController.currentBrightness()
                brightness.rebaseIfExternalChange(currentValue: currentBrightness, at: date)

                let nextBrightness = brightness.value(at: date, endsAt: session.snapshot.endsAt)
                try brightnessController.setBrightness(nextBrightness)
                brightness.markApplied(nextBrightness)
                session.brightness = brightness
            } catch {
                brightnessFailed = true
                onError?((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }

        if !volumeFailed, var volume = session.volume {
            do {
                let currentVolume = try volumeController.currentVolume()
                volume.rebaseIfExternalChange(currentValue: currentVolume, at: date)

                let nextVolume = volume.value(at: date, endsAt: session.snapshot.endsAt)
                try volumeController.setVolume(nextVolume)
                volume.markApplied(nextVolume)
                session.volume = volume
            } catch {
                volumeFailed = true
                onError?((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }

        self.session = session
    }

    private func readInitialBrightness() -> Double? {
        do {
            return try brightnessController.currentBrightness()
        } catch {
            onError?((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return nil
        }
    }

    private func readInitialVolume() -> Double? {
        do {
            return try volumeController.currentVolume()
        } catch {
            onError?((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return nil
        }
    }
}
