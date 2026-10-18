import AppKit

/// Where the detached window goes when the hotkey brings it up "at the pointer".
enum PointerPlacement {
    struct Screen: Equatable {
        /// The whole screen, in the global coordinate space (origin bottom-left).
        var frame: NSRect
        /// The part not covered by the menu bar and Dock.
        var visible: NSRect
    }

    /// How far above the pointer the window's top edge sits, so the pointer lands in the top bar.
    static let topOffset: CGFloat = 24
    static let margin: CGFloat = 8

    /// A frame of `size` with the pointer near the middle of its top bar, kept inside the visible area of the screen the
    /// pointer is on (the nearest one if it is outside them all).
    static func frame(size: NSSize, pointer: NSPoint, screens: [Screen]) -> NSRect {
        guard let screen = screens.first(where: { $0.frame.contains(pointer) }) ?? nearest(to: pointer, in: screens) else {
            return NSRect(origin: NSPoint(x: pointer.x - size.width / 2, y: pointer.y + topOffset - size.height), size: size)
        }
        let area = screen.visible.insetBy(dx: margin, dy: margin)
        var origin = NSPoint(x: pointer.x - size.width / 2, y: pointer.y + topOffset - size.height)
        // Keep it on the screen; a window bigger than the screen is pinned to its top-left corner.
        origin.x = size.width >= area.width ? area.minX : min(max(origin.x, area.minX), area.maxX - size.width)
        origin.y = size.height >= area.height ? area.maxY - size.height : min(max(origin.y, area.minY), area.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }

    private static func nearest(to point: NSPoint, in screens: [Screen]) -> Screen? {
        func distance(_ r: NSRect) -> CGFloat {
            let dx = max(r.minX - point.x, 0, point.x - r.maxX), dy = max(r.minY - point.y, 0, point.y - r.maxY)
            return (dx * dx + dy * dy).squareRoot()
        }
        return screens.min { distance($0.frame) < distance($1.frame) }
    }

    static var currentScreens: [Screen] { NSScreen.screens.map { Screen(frame: $0.frame, visible: $0.visibleFrame) } }
}
