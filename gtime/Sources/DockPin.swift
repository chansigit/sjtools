import AppKit
import CoreGraphics
import Foundation

// MARK: - Display enumeration

struct DockDisplay {
    let id: CGDirectDisplayID
    let name: String
    let bounds: CGRect
    let isMain: Bool
}

func listDockDisplays() -> [DockDisplay] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)

    var names: [CGDirectDisplayID: String] = [:]
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    for screen in NSScreen.screens {
        if let num = (screen.deviceDescription[key] as? NSNumber)?.uint32Value {
            names[num] = screen.localizedName
        }
    }

    return ids.prefix(Int(count)).map { id in
        DockDisplay(id: id, name: names[id] ?? "显示器 \(id)",
                    bounds: CGDisplayBounds(id), isMain: CGDisplayIsMain(id) != 0)
    }
}

/// The Dock's current edge, read from its preferences.
func dockOrientationString() -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    task.arguments = ["read", "com.apple.dock", "orientation"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    try? task.run()
    task.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return out.isEmpty ? "bottom" : out
}

/// Which display currently hosts the Dock (needs Screen Recording on newer macOS; nil if unknown).
func currentDockDisplayID() -> CGDirectDisplayID? {
    guard let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        return nil
    }
    let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
    let displays = listDockDisplays()
    for window in windows {
        guard let owner = window[kCGWindowOwnerName as String] as? String, owner == "Dock",
              let layer = window[kCGWindowLayer as String] as? Int, layer == dockLevel,
              let bd = window[kCGWindowBounds as String] as? [String: Any] else { continue }
        let x = (bd["X"] as? NSNumber)?.doubleValue ?? 0
        let y = (bd["Y"] as? NSNumber)?.doubleValue ?? 0
        let w = (bd["Width"] as? NSNumber)?.doubleValue ?? 0
        let h = (bd["Height"] as? NSNumber)?.doubleValue ?? 0
        let rect = CGRect(x: x, y: y, width: w, height: h)
        // Skip the full-desktop window the Dock process also owns.
        if displays.contains(where: { rect.width >= $0.bounds.width && rect.height >= $0.bounds.height }) {
            continue
        }
        var displayID: CGDirectDisplayID = 0
        var n: UInt32 = 0
        CGGetDisplaysWithRect(rect, 1, &displayID, &n)
        if n > 0 { return displayID }
    }
    return nil
}

// MARK: - Dock pin controller

final class DockPinController {
    private(set) var targetName: String?
    fileprivate var targetDisplayID: CGDirectDisplayID = 0
    fileprivate var edge: DockEdge = .bottom
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    let zone: CGFloat = 6

    init(targetName: String?) { self.targetName = targetName }

    var isActive: Bool { eventTap != nil }

    /// Change the pinned display (nil = unpin) and (re)configure the tap.
    @discardableResult
    func setTarget(_ name: String?, promptForPermission: Bool) -> Bool {
        targetName = name
        return reapply(prompt: promptForPermission)
    }

    /// Re-resolve the current target against live displays/orientation and start or stop the tap.
    @discardableResult
    func reapply() -> Bool { return reapply(prompt: false) }

    @discardableResult
    private func reapply(prompt: Bool) -> Bool {
        edge = dockEdge(from: dockOrientationString())
        guard let name = targetName,
              let disp = listDockDisplays().first(where: { $0.name == name }) else {
            stopTap()
            return true
        }
        targetDisplayID = disp.id
        if !hasAccessibilityPermission(prompt: prompt) {
            stopTap()
            return false
        }
        return startTap()
    }

    /// Actively migrate the Dock onto the pinned display. macOS relocates the always-on
    /// Dock only when the pointer *presses* against a display's Dock edge — a mere warp
    /// isn't enough, it needs sustained movement (delta) into the edge. We approach the
    /// edge from just inside, then post repeated move events carrying downward/side delta
    /// against it, and finally restore the pointer. Runs off the main thread.
    func moveDockToTarget() {
        guard let name = targetName,
              let disp = listDockDisplays().first(where: { $0.name == name }) else { return }
        let b = disp.bounds
        let edge = self.edge
        let saved = CGEvent(source: nil)?.location

        // Push at a point on the target's Dock edge that is a TRUE outer edge (no display
        // beyond it). The edge's midpoint may be an internal boundary with an adjacent
        // display — pushing there just crosses over and never triggers migration.
        let edgePt = dockEdgeHotspot(b, edge)
        let approach: CGPoint, dx: Double, dy: Double
        switch edge {
        case .bottom: approach = CGPoint(x: edgePt.x, y: edgePt.y - 39); dx = 0; dy = 12
        case .left:   approach = CGPoint(x: edgePt.x + 39, y: edgePt.y); dx = -12; dy = 0
        case .right:  approach = CGPoint(x: edgePt.x - 39, y: edgePt.y); dx = 12; dy = 0
        }

        DispatchQueue.global(qos: .userInitiated).async {
            func post(_ p: CGPoint, dx: Double, dy: Double) {
                if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                   mouseCursorPosition: p, mouseButton: .left) {
                    e.setDoubleValueField(.mouseEventDeltaX, value: dx)
                    e.setDoubleValueField(.mouseEventDeltaY, value: dy)
                    e.post(tap: .cghidEventTap)
                }
            }
            // Hide the pointer so the migration nudge isn't visible (best-effort).
            CGDisplayHideCursor(CGMainDisplayID())
            CGWarpMouseCursorPosition(approach)
            CGAssociateMouseAndMouseCursorPosition(1)
            usleep(50_000)
            for i in 1...10 {
                let f = CGFloat(i) / 10.0
                post(CGPoint(x: approach.x + (edgePt.x - approach.x) * f,
                             y: approach.y + (edgePt.y - approach.y) * f), dx: dx, dy: dy)
                usleep(12_000)
            }
            for _ in 0..<40 { post(edgePt, dx: dx, dy: dy); usleep(12_000) }
            usleep(120_000)
            if let saved = saved {
                CGWarpMouseCursorPosition(saved)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    /// A point on the display's Dock edge that is a true outer edge (nothing beyond it),
    /// chosen at the middle of the longest such run so the Dock press actually registers.
    private func dockEdgeHotspot(_ b: CGRect, _ edge: DockEdge) -> CGPoint {
        let n = 60
        func pointAt(_ t: CGFloat) -> CGPoint {
            switch edge {
            case .bottom: return CGPoint(x: b.minX + b.width * t, y: b.maxY - 1)
            case .left:   return CGPoint(x: b.minX + 1, y: b.minY + b.height * t)
            case .right:  return CGPoint(x: b.maxX - 1, y: b.minY + b.height * t)
            }
        }
        var outer = [Bool](repeating: false, count: n + 1)
        for i in 0...n {
            let p = pointAt(CGFloat(i) / CGFloat(n))
            let probe = edgeProbePoint(point: p, displayBounds: b, dockEdge: edge)
            var d: CGDirectDisplayID = 0
            var c: UInt32 = 0
            CGGetDisplaysWithRect(CGRect(x: probe.x, y: probe.y, width: 1, height: 1), 1, &d, &c)
            outer[i] = (c == 0)
        }
        var bestStart = 0, bestLen = 0, curStart = 0, curLen = 0
        for i in 0...n {
            if outer[i] {
                if curLen == 0 { curStart = i }
                curLen += 1
                if curLen > bestLen { bestLen = curLen; bestStart = curStart }
            } else {
                curLen = 0
            }
        }
        if bestLen == 0 { return pointAt(0.5) }   // no outer edge (fully bordered); fall back
        return pointAt(CGFloat(bestStart + bestLen / 2) / CGFloat(n))
    }

    @discardableResult
    private func startTap() -> Bool {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return true
        }
        let mask: CGEventMask = (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dockPinCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func stopTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}

private func dockPinCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
    let c = Unmanaged<DockPinController>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = c.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }

    let point = event.location
    var displayID: CGDirectDisplayID = 0
    var count: UInt32 = 0
    CGGetDisplaysWithRect(CGRect(x: point.x, y: point.y, width: 1, height: 1), 1, &displayID, &count)
    guard count > 0 else { return Unmanaged.passUnretained(event) }

    let isTarget = (displayID == c.targetDisplayID)
    let bounds = CGDisplayBounds(displayID)
    if let clamped = clampedCursor(point: point, displayBounds: bounds,
                                   isTargetDisplay: isTarget, dockEdge: c.edge, zone: c.zone) {
        // Only enforce at a TRUE outer edge. If another display sits just beyond this edge,
        // it's an internal boundary — blocking it would trap the cursor between screens.
        let probe = edgeProbePoint(point: point, displayBounds: bounds, dockEdge: c.edge)
        var pd: CGDirectDisplayID = 0
        var pc: UInt32 = 0
        CGGetDisplaysWithRect(CGRect(x: probe.x, y: probe.y, width: 1, height: 1), 1, &pd, &pc)
        if pc == 0 {
            event.location = clamped
            // Rewriting the event location alone does NOT hold a real hardware cursor, so
            // forcibly warp it out of the Dock trigger zone, then re-associate so the
            // post-warp suppression window doesn't briefly freeze the pointer.
            CGWarpMouseCursorPosition(clamped)
            CGAssociateMouseAndMouseCursorPosition(1)
            return nil   // swallow the event; the warp already positioned the cursor
        }
    }
    return Unmanaged.passUnretained(event)
}
