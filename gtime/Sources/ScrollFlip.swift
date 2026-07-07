import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - System baseline & Accessibility

/// Reads the global "natural scrolling" switch (com.apple.swipescrolldirection).
/// true = natural scrolling ON (macOS default when unset).
func systemNaturalScrolling() -> Bool {
    let key = "com.apple.swipescrolldirection" as CFString
    CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    for host in [kCFPreferencesAnyHost, kCFPreferencesCurrentHost] {
        if let v = CFPreferencesCopyValue(key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, host) as? Bool {
            return v
        }
    }
    return true
}

/// Whether this process is trusted for Accessibility (required for event taps).
/// Pass prompt=true to surface the system permission dialog when it isn't.
func hasAccessibilityPermission(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// MARK: - Scroll event tap controller

final class ScrollFlipController {
    private(set) var settings: ScrollSettings
    fileprivate var flips: ScrollFlips = ScrollFlips(mouse: false, trackpad: false)
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(settings: ScrollSettings) {
        self.settings = settings
    }

    /// Recompute the required flips from the live system baseline and start or stop
    /// the tap so it runs only while at least one device needs flipping.
    /// Returns false if flipping is needed but Accessibility permission is missing.
    @discardableResult
    func apply(_ newSettings: ScrollSettings? = nil, promptForPermission: Bool = false) -> Bool {
        if let s = newSettings { settings = s }
        flips = computeFlips(settings: settings, baselineNatural: systemNaturalScrolling())

        if !shouldRunTap(flips) {
            stopTap()
            return true
        }
        if !hasAccessibilityPermission(prompt: promptForPermission) {
            stopTap()
            return false
        }
        return startTap()
    }

    var isActive: Bool { eventTap != nil }

    @discardableResult
    private func startTap() -> Bool {
        if let tap = eventTap {                 // already running: just refresh enable state
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        let mask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: scrollFlipCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func stopTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}

private func scrollFlipCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<ScrollFlipController>.fromOpaque(userInfo).takeUnretainedValue()

    // Re-enable if macOS disabled the tap (timeout or user input burst).
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = controller.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }

    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
    let flips = controller.flips
    let shouldFlip = isContinuous ? flips.trackpad : flips.mouse
    if !shouldFlip { return Unmanaged.passUnretained(event) }

    guard let newEvent = event.copy() else { return Unmanaged.passUnretained(event) }
    let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    newEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1,
                                  value: reversedVerticalDelta(d1, isContinuous: isContinuous, flips: flips))
    let pd1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    newEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1,
                                  value: reversedVerticalDelta(pd1, isContinuous: isContinuous, flips: flips))
    let fd1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    newEvent.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1,
                                 value: reversedVerticalDelta(fd1, isContinuous: isContinuous, flips: flips))
    return Unmanaged.passRetained(newEvent)
}
