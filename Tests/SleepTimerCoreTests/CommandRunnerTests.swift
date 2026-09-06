import Foundation
import Testing
@testable import SleepTimerCore

@Suite("Asynchronous command runner")
@MainActor
struct CommandRunnerTests {
    @Test("Captures output")
    func output() async throws {
        let result = try await CommandRunner().run("/usr/bin/printf", arguments: ["hello"])
        #expect(result == "hello")
    }

    @Test("Reports launch failures")
    func missingExecutable() async {
        do {
            _ = try await CommandRunner().run("/missing-sleep-timer-command", arguments: [])
            Issue.record("Expected launch failure")
        } catch CommandError.launchFailed { }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("Reports command exit failures and stderr")
    func exitFailure() async {
        do {
            _ = try await CommandRunner().run("/bin/sh", arguments: ["-c", "printf problem >&2; exit 7"])
            Issue.record("Expected exit failure")
        } catch CommandError.failed(let code, let output) {
            #expect(code == 7)
            #expect(output == "problem")
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("Stops a helper at its timeout")
    func timeout() async {
        let start = ContinuousClock.now
        do {
            _ = try await CommandRunner().run("/bin/sleep", arguments: ["30"], timeout: 0.1)
            Issue.record("Expected timeout")
        } catch CommandError.timedOut { }
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test("Cancellation stops a running helper")
    func cancellation() async throws {
        let task = Task { try await CommandRunner().run("/bin/sleep", arguments: ["30"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
    }

    @Test("A canceled task does not launch a command")
    func canceledBeforeLaunch() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await CommandRunner().run("/missing-sleep-timer-command", arguments: [])
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError { }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("Large output drains without deadlocking and capture is bounded")
    func largeOutput() async throws {
        let payload = String(repeating: "a", count: 100_000)
        let output = try await CommandRunner().run("/usr/bin/printf", arguments: [payload])
        #expect(output.count == 65_536)
    }
}
