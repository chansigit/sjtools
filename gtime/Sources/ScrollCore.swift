import Foundation

// MARK: - Pure scroll-direction logic (testable, no CoreGraphics side effects)

/// Absolute scroll direction the user wants for a device.
enum ScrollDir: String, Codable {
    case natural   // content follows fingers / scroll-down moves content up (macOS default)
    case reverse   // traditional wheel: scroll-down moves content down
}

/// Desired absolute direction per device. Persisted to UserDefaults.
struct ScrollSettings: Codable, Equatable {
    var mouse: ScrollDir
    var trackpad: ScrollDir

    static let `default` = ScrollSettings(mouse: .natural, trackpad: .natural)
}

/// Whether each device's scroll deltas must be negated, given the desired settings
/// and the live system baseline.
struct ScrollFlips: Equatable {
    var mouse: Bool
    var trackpad: Bool
}

/// macOS applies its global "natural scrolling" switch before our tap sees the event,
/// so a device's real direction is `baseline XOR ourFlip`. To land on the user's chosen
/// absolute direction we flip exactly when the desired direction differs from the baseline.
func computeFlips(settings: ScrollSettings, baselineNatural: Bool) -> ScrollFlips {
    func flip(_ dir: ScrollDir) -> Bool {
        let desiredNatural = (dir == .natural)
        return desiredNatural != baselineNatural
    }
    return ScrollFlips(mouse: flip(settings.mouse), trackpad: flip(settings.trackpad))
}

/// The event tap only needs to run when at least one device is being flipped.
func shouldRunTap(_ flips: ScrollFlips) -> Bool {
    return flips.mouse || flips.trackpad
}

/// Reverse a vertical scroll delta for the device that produced it.
/// `isContinuous` true means trackpad (continuous), false means mouse wheel (discrete).
func reversedVerticalDelta(_ delta: Int64, isContinuous: Bool, flips: ScrollFlips) -> Int64 {
    let shouldFlip = isContinuous ? flips.trackpad : flips.mouse
    return shouldFlip ? -delta : delta
}

func reversedVerticalDelta(_ delta: Double, isContinuous: Bool, flips: ScrollFlips) -> Double {
    let shouldFlip = isContinuous ? flips.trackpad : flips.mouse
    return shouldFlip ? -delta : delta
}

// MARK: - Persistence

func encodeScrollSettings(_ settings: ScrollSettings) -> Data {
    return (try? JSONEncoder().encode(settings)) ?? Data()
}

func decodeScrollSettings(_ data: Data) -> ScrollSettings {
    return (try? JSONDecoder().decode(ScrollSettings.self, from: data)) ?? .default
}
