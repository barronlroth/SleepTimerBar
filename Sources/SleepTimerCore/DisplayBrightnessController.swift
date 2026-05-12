import CoreGraphics
import Darwin
import Foundation

public enum DisplayBrightnessError: LocalizedError {
    case displayServicesUnavailable(String)
    case missingDisplayServicesSymbol(String)
    case readFailed(Int32)
    case writeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .displayServicesUnavailable(let message):
            "Could not load macOS display brightness controls: \(message)"
        case .missingDisplayServicesSymbol(let name):
            "Could not find macOS display brightness control: \(name)."
        case .readFailed(let code):
            "Could not read display brightness. DisplayServices returned \(code)."
        case .writeFailed(let code):
            "Could not set display brightness. DisplayServices returned \(code)."
        }
    }
}

public protocol DisplayBrightnessControlling {
    func currentBrightness() throws -> Double
    func setBrightness(_ value: Double) throws
}

public final class DisplayBrightnessController: DisplayBrightnessControlling {
    private typealias GetBrightnessFunction = @convention(c) (
        CGDirectDisplayID,
        UnsafeMutablePointer<Float>
    ) -> Int32

    private typealias SetBrightnessFunction = @convention(c) (
        CGDirectDisplayID,
        Float
    ) -> Int32

    private let displayServicesPath = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"

    public init() {}

    public func currentBrightness() throws -> Double {
        let getBrightness = try displayServicesFunction(
            named: "DisplayServicesGetBrightness",
            as: GetBrightnessFunction.self
        )
        var brightness: Float = 0
        let result = getBrightness(builtInDisplayID(), &brightness)

        guard result == 0 else {
            throw DisplayBrightnessError.readFailed(result)
        }

        return FadeMath.clamp01(Double(brightness))
    }

    public func setBrightness(_ value: Double) throws {
        let setBrightness = try displayServicesFunction(
            named: "DisplayServicesSetBrightness",
            as: SetBrightnessFunction.self
        )
        let result = setBrightness(builtInDisplayID(), Float(FadeMath.clamp01(value)))

        guard result == 0 else {
            throw DisplayBrightnessError.writeFailed(result)
        }
    }

    private func displayServicesFunction<T>(named name: String, as type: T.Type) throws -> T {
        guard let handle = dlopen(displayServicesPath, RTLD_NOW) else {
            let message = dlerror().map { String(cString: UnsafePointer($0)) } ?? "unknown error"
            throw DisplayBrightnessError.displayServicesUnavailable(message)
        }

        guard let symbol = dlsym(handle, name) else {
            throw DisplayBrightnessError.missingDisplayServicesSymbol(name)
        }

        return unsafeBitCast(symbol, to: type)
    }

    private func builtInDisplayID() -> CGDirectDisplayID {
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        return displays
            .prefix(Int(displayCount))
            .first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
}
