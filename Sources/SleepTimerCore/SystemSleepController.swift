import Foundation

@MainActor
public protocol SystemSleepControlling {
    func sleepNow() async throws
}

@MainActor
public final class SystemSleepController: SystemSleepControlling {
    private let runner = CommandRunner()

    public init() {}

    public func sleepNow() async throws {
        _ = try await runner.run("/usr/bin/pmset", arguments: ["sleepnow"])
    }
}
