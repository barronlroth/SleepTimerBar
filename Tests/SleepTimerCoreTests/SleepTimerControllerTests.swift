import Foundation
import Testing
@testable import SleepTimerCore

@MainActor
private final class FakeClock: SleepTimerClock {
    var now: TimeInterval = 0
    var date = Date(timeIntervalSinceReferenceDate: 100_000)
}

@MainActor
private final class FakeScheduler: SleepTimerScheduling {
    var action: (@MainActor () -> Void)?
    var scheduled = false
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.action = action
        scheduled = true
    }
    func cancel() { scheduled = false }
    // Deliberately deliver even canceled callbacks to exercise already-queued ticks.
    func fire() { action?() }
}

@MainActor
private final class FakeHardware: DisplayBrightnessControlling, VolumeControlling, SystemSleepControlling {
    enum Failure: Error { case unavailable }
    var brightness = 0.8
    var volume = 0.6
    var brightnessWrites = 0
    var volumeWrites = 0
    var volumeReads = 0
    var sleepRequests = 0
    var failBrightness = false
    var failVolumeRead = false
    var failVolumeWrite = false
    var failSleep = false
    var blockVolumeRead = false
    var blockedRead: CheckedContinuation<Double, any Error>?
    var onReadBlocked: (() -> Void)?

    func currentBrightness() throws -> Double {
        if failBrightness { throw Failure.unavailable }
        return brightness
    }
    func setBrightness(_ value: Double) throws {
        if failBrightness { throw Failure.unavailable }
        brightness = value
        brightnessWrites += 1
    }
    func currentVolume() async throws -> Double {
        volumeReads += 1
        if failVolumeRead { throw Failure.unavailable }
        if blockVolumeRead {
            return try await withCheckedThrowingContinuation {
                blockedRead = $0
                onReadBlocked?()
            }
        }
        return volume
    }
    func setVolume(_ value: Double) async throws {
        if failVolumeWrite { throw Failure.unavailable }
        volume = value
        volumeWrites += 1
    }
    func sleepNow() async throws {
        sleepRequests += 1
        if failSleep { throw Failure.unavailable }
    }
    func releaseRead() {
        blockVolumeRead = false
        let continuation = blockedRead
        blockedRead = nil
        continuation?.resume(returning: volume)
    }
}

@MainActor
private struct Fixture {
    let clock = FakeClock()
    let scheduler = FakeScheduler()
    let hardware = FakeHardware()
    let controller: SleepTimerController

    init(floor: Double = 0) {
        let defaults = UserDefaults(suiteName: "SleepTimerTests.\(UUID())")!
        defaults.register(defaults: ["brightnessFloor": floor, "volumeFloor": floor])
        controller = SleepTimerController(
            settings: AppSettings(defaults: defaults), brightnessController: hardware,
            volumeController: hardware, sleepController: hardware,
            clock: clock, scheduler: scheduler
        )
    }
    func flush() async {
        while let task = controller.updateTask { await task.value }
    }
    func start() async {
        controller.start(duration: .thirty)
        await flush()
    }
    func advance(to time: TimeInterval) async {
        clock.now = time
        scheduler.fire()
        await flush()
    }
    func blockNextRead() async {
        hardware.blockVolumeRead = true
        await withCheckedContinuation { entered in
            hardware.onReadBlocked = { entered.resume() }
            scheduler.fire()
        }
        hardware.onReadBlocked = nil
    }
}

@Suite("Timer lifecycle")
@MainActor
struct SleepTimerControllerTests {
    @Test("Restart publishes only the new running state")
    func restartState() async {
        let f = Fixture()
        var states: [SleepTimerState] = []
        f.controller.onStateChanged = { states.append($0) }
        await f.start()
        f.controller.start(duration: .sixty)
        await f.flush()
        #expect(states.count == 2)
        #expect(states.allSatisfy { if case .running = $0 { true } else { false } })
        #expect(f.controller.remainingSeconds == 3600)
        f.controller.cancel()
    }

    @Test("Cancel keeps current levels and prevents queued fade/sleep work")
    func cancel() async {
        let f = Fixture()
        await f.start()
        await f.advance(to: 900)
        let brightness = f.hardware.brightness
        let volume = f.hardware.volume
        let reads = f.hardware.volumeReads
        f.controller.cancel()
        await f.advance(to: 7200)
        #expect(f.hardware.brightness == brightness)
        #expect(f.hardware.volume == volume)
        #expect(f.hardware.volumeReads == reads)
        #expect(f.hardware.sleepRequests == 0)
        #expect(!f.scheduler.scheduled)
        #expect(f.controller.state == .idle)
    }

    @Test("Completion applies floors and requests sleep exactly once")
    func completion() async {
        let f = Fixture(floor: 0.1)
        await f.start()
        await f.advance(to: 1800)
        await f.advance(to: 7200)
        #expect(abs(f.hardware.brightness - 0.1) < 0.00001)
        #expect(f.hardware.volume == 0.1)
        #expect(f.hardware.sleepRequests == 1)
        #expect(f.controller.state == .idle)
        #expect(!f.scheduler.scheduled)
    }

    @Test("System sleep cancels; an overdue wake never requests sleep again")
    func systemSleep() async {
        let f = Fixture()
        await f.start()
        f.controller.systemWillSleep()
        await f.advance(to: 7200)
        #expect(f.controller.state == .idle)
        #expect(f.hardware.sleepRequests == 0)
    }

    @Test("Wall clock changes do not alter remaining duration")
    func wallClockChanges() async {
        let f = Fixture()
        await f.start()
        f.clock.date.addTimeInterval(7200)
        await f.advance(to: 900)
        #expect(f.controller.remainingSeconds == 900)
        #expect(f.controller.estimatedSleepDate == f.clock.date.addingTimeInterval(900))
        #expect(f.hardware.sleepRequests == 0)
        f.clock.date.addTimeInterval(-14400)
        await f.advance(to: 1800)
        #expect(f.hardware.sleepRequests == 1)
    }

    @Test("Initial hardware failures still allow the sleep timer to complete")
    func initialFailures() async {
        let f = Fixture()
        f.hardware.failBrightness = true
        f.hardware.failVolumeRead = true
        await f.start()
        #expect(f.controller.issues.count == 2)
        await f.advance(to: 1800)
        #expect(f.hardware.sleepRequests == 1)
        #expect(f.controller.issues.count == 2)
    }

    @Test("Final fade failures report status and still request sleep")
    func finalFadeFailures() async {
        let f = Fixture()
        await f.start()
        var updates = 0
        f.controller.onStatusChanged = { updates += 1 }
        f.hardware.failBrightness = true
        f.hardware.failVolumeWrite = true
        await f.advance(to: 1800)
        #expect(f.hardware.sleepRequests == 1)
        #expect(f.controller.issues.map(\.source) == [.brightness, .volume])
        #expect(updates >= 2)
    }

    @Test("A failed sleep command is visible and is not retried on later ticks")
    func failedSleep() async {
        let f = Fixture()
        f.hardware.failSleep = true
        await f.start()
        await f.advance(to: 1800)
        await f.advance(to: 1805)
        #expect(f.hardware.sleepRequests == 1)
        #expect(f.controller.issues.first?.source == .sleep)
        #expect(f.controller.state == .idle)
    }

    @Test("Manual increases fade from new levels over the original remaining time")
    func manualIncreases() async {
        let f = Fixture()
        await f.start()
        await f.advance(to: 900)
        f.hardware.brightness = 0.9
        f.hardware.volume = 0.8
        await f.advance(to: 900)
        #expect(f.hardware.brightness == 0.9)
        #expect(f.hardware.volume == 0.8)
        await f.advance(to: 1350)
        #expect(abs(f.hardware.brightness - 0.45) < 0.00001)
        #expect(f.hardware.volume == 0.4)
        #expect(f.controller.remainingSeconds == 450)
        await f.advance(to: 1800)
        #expect(f.hardware.sleepRequests == 1)
    }

    @Test("Manual decreases below floors remain below floors")
    func manualBelowFloor() async {
        let f = Fixture(floor: 0.2)
        await f.start()
        f.hardware.brightness = 0.1
        f.hardware.volume = 0.1
        await f.advance(to: 900)
        await f.advance(to: 1800)
        #expect(abs(f.hardware.brightness - 0.1) < 0.00001)
        #expect(f.hardware.volume == 0.1)
    }

    @Test("Unchanged rounded volume does not launch a write")
    func skipsUnchangedVolume() async {
        let f = Fixture()
        await f.start()
        await f.advance(to: 5)
        await f.advance(to: 10)
        #expect(f.hardware.volumeWrites == 0)
        await f.advance(to: 20)
        #expect(f.hardware.volumeWrites == 1)
        #expect(f.hardware.volume == 0.59)
        f.controller.cancel()
    }

    @Test("Cancel while a read is pending discards its result")
    func cancelDuringRead() async {
        let f = Fixture()
        await f.start()
        f.clock.now = 1800
        await f.blockNextRead()
        let writes = f.hardware.volumeWrites
        f.controller.cancel()
        f.hardware.releaseRead()
        await f.flush()
        #expect(f.hardware.volumeWrites == writes)
        #expect(f.hardware.sleepRequests == 0)
        #expect(f.controller.issues.isEmpty)
    }

    @Test("Restart serializes helpers and discards an old completion")
    func restartDuringRead() async {
        let f = Fixture()
        await f.start()
        f.clock.now = 1800
        await f.blockNextRead()
        let reads = f.hardware.volumeReads
        f.controller.start(duration: .sixty)
        f.scheduler.fire()
        await Task.yield()
        #expect(f.hardware.volumeReads == reads)
        f.hardware.releaseRead()
        await f.flush()
        #expect(f.hardware.sleepRequests == 0)
        #expect(f.controller.remainingSeconds == 3600)
        #expect(f.controller.issues.isEmpty)
        await f.advance(to: 5400)
        #expect(f.hardware.sleepRequests == 1)
    }

    @Test("Ticks coalesce while a hardware operation is pending")
    func overlappingTicks() async {
        let f = Fixture()
        await f.start()
        await f.blockNextRead()
        let reads = f.hardware.volumeReads
        for _ in 0..<10 { f.scheduler.fire() }
        await Task.yield()
        #expect(f.hardware.volumeReads == reads)
        f.hardware.releaseRead()
        await f.flush()
        #expect(f.hardware.volumeReads == reads + 1)
        f.controller.cancel()
    }
}
