import Foundation

public enum VolumeError: LocalizedError {
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOutput(let output): "Could not read the current volume from: \(output)"
        }
    }
}

@MainActor
public protocol VolumeControlling {
    func currentVolume() async throws -> Double
    func setVolume(_ value: Double) async throws
}

@MainActor
public final class VolumeController: VolumeControlling {
    private let runner = CommandRunner()

    public init() {}

    public func currentVolume() async throws -> Double {
        let output = try await runner.run("/usr/bin/osascript", arguments: [
            "-e", "output volume of (get volume settings)"
        ])
        guard let integerValue = Int(output) else { throw VolumeError.invalidOutput(output) }
        return FadeMath.clamp01(Double(integerValue) / 100)
    }

    public func setVolume(_ value: Double) async throws {
        let percent = Int((FadeMath.clamp01(value) * 100).rounded())
        _ = try await runner.run("/usr/bin/osascript", arguments: [
            "-e", "set volume output volume \(percent)"
        ])
    }
}
