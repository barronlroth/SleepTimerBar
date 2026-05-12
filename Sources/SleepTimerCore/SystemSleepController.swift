import Foundation

public enum SystemSleepError: LocalizedError {
    case launchFailed(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            "Could not run the sleep command: \(message)"
        case .commandFailed(let message):
            "Sleep command failed: \(message)"
        }
    }
}

public protocol SystemSleepControlling {
    func sleepNow() throws
}

public final class SystemSleepController: SystemSleepControlling {
    public init() {}

    public func sleepNow() throws {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw SystemSleepError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "exit code \(process.terminationStatus)"
            throw SystemSleepError.commandFailed(output)
        }
    }
}
