import Foundation

public enum VolumeError: LocalizedError {
    case launchFailed(String)
    case commandFailed(String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            "Could not run the volume command: \(message)"
        case .commandFailed(let message):
            "Volume command failed: \(message)"
        case .invalidOutput(let output):
            "Could not read the current volume from: \(output)"
        }
    }
}

public protocol VolumeControlling {
    func currentVolume() throws -> Double
    func setVolume(_ value: Double) throws
}

public final class VolumeController: VolumeControlling {
    public init() {}

    public func currentVolume() throws -> Double {
        let output = try runAppleScript("output volume of (get volume settings)")
        guard let integerValue = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw VolumeError.invalidOutput(output)
        }
        return FadeMath.clamp01(Double(integerValue) / 100)
    }

    public func setVolume(_ value: Double) throws {
        let percent = Int((FadeMath.clamp01(value) * 100).rounded())
        _ = try runAppleScript("set volume output volume \(percent)")
    }

    private func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw VolumeError.launchFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw VolumeError.commandFailed(errorOutput.isEmpty ? output : errorOutput)
        }

        return output
    }
}
