import AppKit

/// Carries a window along with the pointer while the mouse button is held, from wherever the window is now. Used when the
/// popover is pulled off the menu bar icon: the window appears under the pointer and keeps following it, with no second
/// grab needed (the first version handed the drag to AppKit's `performDrag`, which didn't keep hold of the window).
enum WindowFollower {
    /// Where the window's origin should be: moved by how far the pointer has travelled since `start`, with the top edge
    /// kept below the menu bar and some of the window kept on the screen.
    static func origin(start: NSPoint, pointer: NSPoint, windowOrigin: NSPoint, size: NSSize, screens: [PointerPlacement.Screen], keepVisible: CGFloat = 80) -> NSPoint {
        var origin = NSPoint(x: windowOrigin.x + (pointer.x - start.x), y: windowOrigin.y + (pointer.y - start.y))
        guard let screen = screens.first(where: { $0.frame.contains(pointer) }) ?? screens.first else { return origin }
        let visible = screen.visible
        origin.y = min(origin.y, visible.maxY - size.height)                        // the top bar stays below the menu bar
        origin.x = min(max(origin.x, visible.minX + keepVisible - size.width), visible.maxX - keepVisible)
        return origin
    }

    /// Follows the pointer until `nextEvent` returns a mouse-up (or nothing). `pointer` is where the pointer is now.
    @MainActor
    static func follow(_ window: NSWindow, nextEvent: () -> NSEvent?, pointer: () -> NSPoint = { NSEvent.mouseLocation },
                       screens: [PointerPlacement.Screen] = PointerPlacement.currentScreens) {
        let start = pointer()
        let windowOrigin = window.frame.origin
        while let event = nextEvent() {
            if event.type == .leftMouseUp { break }
            window.setFrameOrigin(origin(start: start, pointer: pointer(), windowOrigin: windowOrigin, size: window.frame.size, screens: screens))
        }
    }

    /// The real event source: the next drag or release, taken straight off the queue while the button is down.
    @MainActor
    static func nextMouseEvent() -> NSEvent? {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { return nil }
        return NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true)
    }
}
