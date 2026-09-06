import CoreGraphics
import Darwin
import Foundation

public enum DisplayBrightnessError: LocalizedError {
    case displayServicesUnavailable(String)
    case missingDisplayServicesSymbol(String)
    case noBuiltInDisplay
    case displayListFailed(Int32)
    case readFailed(Int32)
    case writeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .displayServicesUnavailable(let message):
            "Could not load macOS display brightness controls: \(message)"
        case .missingDisplayServicesSymbol(let name):
            "Could not find macOS display brightness control: \(name)."
        case .noBuiltInDisplay:
            "No active built-in display is available."
        case .displayListFailed(let code):
            "Could not find the built-in display (\(code))."
        case .readFailed(let code):
            "Could not read display brightness. DisplayServices returned \(code)."
        case .writeFailed(let code):
            "Could not set display brightness. DisplayServices returned \(code)."
        }
    }
}

@MainActor
public protocol DisplayBrightnessControlling {
    func currentBrightness() throws -> Double
    func setBrightness(_ value: Double) throws
}

@MainActor
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

    // One retained loader owns both function pointers for their entire lifetime.
    private lazy var functions: Result<DisplayServicesFunctions, Error> = Result {
        try DisplayServicesFunctions(path: displayServicesPath)
    }

    public init() {}

    public func currentBrightness() throws -> Double {
        let getBrightness = try functions.get().getBrightness
        var brightness: Float = 0
        let result = getBrightness(try builtInDisplayID(), &brightness)

        guard result == 0 else {
            throw DisplayBrightnessError.readFailed(result)
        }

        return FadeMath.clamp01(Double(brightness))
    }

    public func setBrightness(_ value: Double) throws {
        let setBrightness = try functions.get().setBrightness
        let result = setBrightness(try builtInDisplayID(), Float(FadeMath.clamp01(value)))

        guard result == 0 else {
            throw DisplayBrightnessError.writeFailed(result)
        }
    }

    private final class DisplayServicesFunctions {
        let handle: UnsafeMutableRawPointer
        let getBrightness: GetBrightnessFunction
        let setBrightness: SetBrightnessFunction

        init(path: String) throws {
            guard let handle = dlopen(path, RTLD_NOW) else {
                let message = dlerror().map { String(cString: $0) } ?? "unknown error"
                throw DisplayBrightnessError.displayServicesUnavailable(message)
            }
            do {
                guard let get = dlsym(handle, "DisplayServicesGetBrightness") else {
                    throw DisplayBrightnessError.missingDisplayServicesSymbol("DisplayServicesGetBrightness")
                }
                guard let set = dlsym(handle, "DisplayServicesSetBrightness") else {
                    throw DisplayBrightnessError.missingDisplayServicesSymbol("DisplayServicesSetBrightness")
                }
                self.handle = handle
                getBrightness = unsafeBitCast(get, to: GetBrightnessFunction.self)
                setBrightness = unsafeBitCast(set, to: SetBrightnessFunction.self)
            } catch {
                dlclose(handle)
                throw error
            }
        }

        deinit { dlclose(handle) }
    }

    private func builtInDisplayID() throws -> CGDirectDisplayID {
        var displayCount: UInt32 = 0
        var result = CGGetActiveDisplayList(0, nil, &displayCount)
        guard result == .success else {
            throw DisplayBrightnessError.displayListFailed(result.rawValue)
        }
        guard displayCount > 0 else { throw DisplayBrightnessError.noBuiltInDisplay }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        result = CGGetActiveDisplayList(displayCount, &displays, &displayCount)
        guard result == .success else {
            throw DisplayBrightnessError.displayListFailed(result.rawValue)
        }
        guard let display = displays.prefix(Int(displayCount)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
            throw DisplayBrightnessError.noBuiltInDisplay
        }
        return display
    }
}
