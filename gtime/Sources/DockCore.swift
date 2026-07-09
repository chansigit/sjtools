import CoreGraphics

// MARK: - Pure Dock-pinning logic (testable, no event-tap side effects)

/// Which screen edge the Dock lives on (from `com.apple.dock orientation`).
enum DockEdge: String {
    case bottom, left, right
}

func dockEdge(from orientation: String) -> DockEdge {
    return DockEdge(rawValue: orientation) ?? .bottom
}

/// If the cursor is on a non-target display and inside that display's Dock trigger
/// zone, return the point pushed just outside the zone so the Dock can't activate
/// there. Returns nil when no clamping is needed (on the target display, or away
/// from the edge). Coordinates are the global top-left display space (y grows down).
func clampedCursor(point: CGPoint, displayBounds b: CGRect,
                   isTargetDisplay: Bool, dockEdge: DockEdge, zone: CGFloat) -> CGPoint? {
    if isTargetDisplay { return nil }
    switch dockEdge {
    case .bottom:
        if point.y >= b.maxY - zone { return CGPoint(x: point.x, y: b.maxY - zone - 1) }
    case .left:
        if point.x <= b.minX + zone { return CGPoint(x: b.minX + zone + 1, y: point.y) }
    case .right:
        if point.x >= b.maxX - zone { return CGPoint(x: b.maxX - zone - 1, y: point.y) }
    }
    return nil
}
