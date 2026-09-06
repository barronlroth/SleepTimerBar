import Foundation

public struct SleepTimerSnapshot: Equatable, Sendable {
    public let duration: TimerDuration
    public let startedAt: Date
    public let endsAt: Date

    public var totalSeconds: TimeInterval { duration.seconds }
}

public enum SleepTimerState: Equatable, Sendable {
    case idle
    case running(SleepTimerSnapshot)
}

public struct SleepTimerIssue: Equatable, Sendable {
    public enum Source: String, Sendable {
        case brightness = "Brightness"
        case volume = "Volume"
        case sleep = "Sleep"
    }
    public let source: Source
    public let message: String
}

private struct SleepTimerSession {
    let id: UUID
    let snapshot: SleepTimerSnapshot
    let startedAt: TimeInterval
    let brightnessFloor: Double
    let volumeFloor: Double
    var initialized = false
    var brightness: FadeChannel?
    var volume: FadeChannel?

    var endsAt: Date {
        Date(timeIntervalSinceReferenceDate: startedAt + snapshot.totalSeconds)
    }
}

@MainActor
public final class SleepTimerController {
    public private(set) var state: SleepTimerState = .idle {
        didSet { if state != oldValue { onStateChanged?(state) } }
    }
    public private(set) var issues: [SleepTimerIssue] = []
    public var onStateChanged: ((SleepTimerState) -> Void)?
    public var onStatusChanged: (() -> Void)?

    private let settings: AppSettings
    private let brightnessController: DisplayBrightnessControlling
    private let volumeController: VolumeControlling
    private let sleepController: SystemSleepControlling
    private let clock: SleepTimerClock
    private let scheduler: SleepTimerScheduling
    private let updateInterval: TimeInterval
    private var session: SleepTimerSession?
    private var generation = UUID()
    private var updateRequested = false
    // Internal visibility lets lifecycle tests await real asynchronous work.
    private(set) var updateTask: Task<Void, Never>?

    public var remainingSeconds: TimeInterval {
        guard let session else { return 0 }
        return max(0, session.snapshot.totalSeconds - (clock.now - session.startedAt))
    }

    public var estimatedSleepDate: Date? {
        session.map { _ in clock.date.addingTimeInterval(remainingSeconds) }
    }

    public init(
        settings: AppSettings,
        brightnessController: DisplayBrightnessControlling = DisplayBrightnessController(),
        volumeController: VolumeControlling = VolumeController(),
        sleepController: SystemSleepControlling = SystemSleepController(),
        updateInterval: TimeInterval = 5,
        clock: SleepTimerClock = MonotonicTimerClock(),
        scheduler: SleepTimerScheduling = RunLoopTimerScheduler()
    ) {
        precondition(updateInterval.isFinite && updateInterval > 0)
        self.settings = settings
        self.brightnessController = brightnessController
        self.volumeController = volumeController
        self.sleepController = sleepController
        self.updateInterval = updateInterval
        self.clock = clock
        self.scheduler = scheduler
    }

    public func toggleDefaultTimer() {
        switch state {
        case .idle: start(duration: settings.defaultDuration)
        case .running: cancel()
        }
    }

    public func start(duration: TimerDuration) {
        stopUpdates()
        issues = []
        let snapshot = SleepTimerSnapshot(
            duration: duration, startedAt: clock.date,
            endsAt: clock.date.addingTimeInterval(duration.seconds)
        )
        session = SleepTimerSession(
            id: generation, snapshot: snapshot, startedAt: clock.now,
            brightnessFloor: settings.brightnessFloor, volumeFloor: settings.volumeFloor
        )
        state = .running(snapshot)
        onStatusChanged?()
        scheduler.schedule(every: updateInterval) { [weak self] in self?.requestUpdate() }
        requestUpdate()
    }

    public func cancel() {
        stopUpdates()
        state = .idle
        onStatusChanged?()
    }

    /// Called for actual system sleep, including lid closure and manual sleep.
    /// A later wake never resumes the canceled session.
    public func systemWillSleep() {
        cancel()
    }

    private func stopUpdates() {
        generation = UUID()
        scheduler.cancel()
        session = nil
        updateRequested = false
        updateTask?.cancel()
        // Keep the task until its helper exits. A new session must not overlap it.
    }

    private func requestUpdate() {
        guard session != nil else { return }
        updateRequested = true
        guard updateTask == nil else { return }
        updateTask = Task { [weak self] in
            guard let self else { return }
            while self.updateRequested && !Task.isCancelled {
                self.updateRequested = false
                await self.update()
            }
            self.updateTask = nil
            if self.updateRequested { self.requestUpdate() }
        }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        generation == id && !Task.isCancelled
    }

    private var fadeDate: Date { Date(timeIntervalSinceReferenceDate: clock.now) }

    private func update() async {
        guard var current = session, isCurrent(current.id) else { return }
        if !current.initialized {
            do {
                let value = try brightnessController.currentBrightness()
                current.brightness = FadeChannel(
                    currentValue: value, floor: current.brightnessFloor, curve: .linear, date: fadeDate
                )
            } catch { record(error, source: .brightness) }
            guard isCurrent(current.id) else { return }
            do {
                let value = try await volumeController.currentVolume()
                guard isCurrent(current.id) else { return }
                current.volume = FadeChannel(
                    currentValue: value, floor: current.volumeFloor, curve: .linear, date: fadeDate
                )
            } catch {
                guard isCurrent(current.id) else { return }
                record(error, source: .volume)
            }
            current.initialized = true
        }
        guard isCurrent(current.id) else { return }
        let completing = clock.now >= current.startedAt + current.snapshot.totalSeconds
        if completing { scheduler.cancel() }

        if var brightness = current.brightness {
            do {
                let value = try brightnessController.currentBrightness()
                let date = min(fadeDate, current.endsAt)
                brightness.rebaseIfExternalChange(currentValue: value, at: date)
                let next = brightness.value(at: date, endsAt: current.endsAt)
                if abs(next - value) > 0.00001 { try brightnessController.setBrightness(next) }
                brightness.markApplied(next)
                current.brightness = brightness
            } catch {
                current.brightness = nil
                record(error, source: .brightness)
            }
        }
        guard isCurrent(current.id) else { return }
        if var volume = current.volume {
            do {
                let value = try await volumeController.currentVolume()
                guard isCurrent(current.id) else { return }
                let date = min(fadeDate, current.endsAt)
                volume.rebaseIfExternalChange(currentValue: value, at: date)
                let next = volume.value(at: date, endsAt: current.endsAt)
                let percent = (next * 100).rounded()
                if percent != (value * 100).rounded() {
                    try await volumeController.setVolume(percent / 100)
                    guard isCurrent(current.id) else { return }
                }
                volume.markApplied(percent / 100)
                current.volume = volume
            } catch {
                guard isCurrent(current.id) else { return }
                current.volume = nil
                record(error, source: .volume)
            }
        }
        guard isCurrent(current.id) else { return }
        session = current
        if completing {
            // Clear the session before invoking sleep: even a queued tick cannot
            // complete twice. Channel issues never interrupt this path.
            session = nil
            updateRequested = false
            state = .idle
            onStatusChanged?()
            guard isCurrent(current.id) else { return }
            do {
                try await sleepController.sleepNow()
            } catch {
                guard isCurrent(current.id) else { return }
                record(error, source: .sleep)
            }
        }
    }

    private func record(_ error: any Error, source: SleepTimerIssue.Source) {
        issues.removeAll { $0.source == source }
        issues.append(SleepTimerIssue(source: source, message: error.localizedDescription))
        onStatusChanged?()
    }
}
