import Darwin
import Foundation

public enum CommandError: LocalizedError {
    case launchFailed(String)
    case timedOut
    case failed(Int32, String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message): "Could not run the system command: \(message)"
        case .timedOut: "The system command took too long and was stopped."
        case .failed(let status, let message):
            "System command failed (\(status)): \(message)"
        }
    }
}

/// Used only for the app's short-lived system helpers. No shell interpolation.
@MainActor
final class CommandRunner {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval = 3) async throws -> String {
        precondition(timeout.isFinite && timeout > 0)
        try Task.checkCancellation()
        let execution = CommandExecution(executable: executable, arguments: arguments)
        return try await withTaskCancellationHandler {
            try await execution.run(timeout: timeout)
        } onCancel: {
            Task { @MainActor in execution.cancel() }
        }
    }
}

@MainActor
private final class CommandExecution {
    private let process = Process()
    private let output = CommandOutput()
    private let errors = CommandOutput()
    private var continuation: CheckedContinuation<String, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var stopError: (any Error)?

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output.pipe
        process.standardError = errors.pipe
    }

    func run(timeout: TimeInterval) async throws -> String {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in self?.finished() }
            }
            do {
                try process.run()
            } catch {
                self.continuation = nil
                output.close()
                errors.close()
                continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                return
            }
            timeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                    self?.stop(with: CommandError.timedOut)
                } catch { /* Finished or canceled before the deadline. */ }
            }
        }
    }

    func cancel() {
        stop(with: CancellationError())
    }

    private func stop(with error: any Error) {
        guard continuation != nil, stopError == nil else { return }
        stopError = error
        if process.isRunning {
            // These helpers must not outlive a canceled/replaced session. SIGKILL
            // also bounds commands that ignore SIGTERM; completion waits for exit.
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func finished() {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        let stdout = output.finish()
        let stderr = errors.finish()
        if let stopError {
            continuation.resume(throwing: stopError)
        } else if process.terminationStatus != 0 {
            continuation.resume(throwing: CommandError.failed(
                process.terminationStatus, stderr.isEmpty ? stdout : stderr
            ))
        } else {
            continuation.resume(returning: stdout)
        }
    }
}

/// FileHandle callbacks run off the main actor. The lock protects both reads and
/// captured bytes; draining continuously prevents a full pipe blocking a helper.
private final class CommandOutput: @unchecked Sendable {
    let pipe = Pipe()
    private let lock = NSLock()
    private var data = Data()
    private var closed = false
    private let limit = 65_536

    init() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard !self.closed else { return }
            let chunk = handle.availableData
            self.append(chunk)
            if chunk.isEmpty { handle.readabilityHandler = nil }
        }
    }

    private func append(_ chunk: Data) {
        data.append(chunk.prefix(max(0, limit - data.count)))
    }

    func finish() -> String {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil
        lock.lock()
        if !closed { append(handle.readDataToEndOfFile()) }
        let result = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        close()
        return result
    }

    func close() {
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
    }
}
