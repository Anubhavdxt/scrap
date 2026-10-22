import XCTest
@testable import ScrapApp

@MainActor
final class WindowFollowerTests: XCTestCase {
    private let screens = [PointerPlacement.Screen(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), visible: NSRect(x: 0, y: 0, width: 1440, height: 875))]
    private let size = NSSize(width: 500, height: 350)

    func testTheWindowMovesByHowFarThePointerMoved() {
        let origin = WindowFollower.origin(start: NSPoint(x: 1000, y: 800), pointer: NSPoint(x: 940, y: 700), windowOrigin: NSPoint(x: 700, y: 480), size: size, screens: screens)
        XCTAssertEqual(origin, NSPoint(x: 640, y: 380))
    }

    func testTheTopStaysBelowTheMenuBar() {
        let origin = WindowFollower.origin(start: NSPoint(x: 1000, y: 800), pointer: NSPoint(x: 1000, y: 899), windowOrigin: NSPoint(x: 700, y: 480), size: size, screens: screens)
        XCTAssertEqual(origin.y + size.height, 875, accuracy: 0.01, "the window's top is the bottom of the menu bar")
    }

    func testSomeOfTheWindowAlwaysStaysOnTheScreen() {
        let far = WindowFollower.origin(start: NSPoint(x: 500, y: 500), pointer: NSPoint(x: 1400, y: 500), windowOrigin: NSPoint(x: 700, y: 100), size: size, screens: screens)
        XCTAssertLessThan(far.x, 1440 - 40, "the pointer is on the screen and so is a good part of the window")
        let left = WindowFollower.origin(start: NSPoint(x: 500, y: 500), pointer: NSPoint(x: 5, y: 500), windowOrigin: NSPoint(x: 100, y: 100), size: size, screens: screens)
        XCTAssertGreaterThan(left.x + size.width, 40)
    }

    func testItFollowsEveryDragUntilTheButtonComesUp() {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let start = window.frame.origin
        var positions = [NSPoint(x: 500, y: 500), NSPoint(x: 520, y: 480), NSPoint(x: 560, y: 440), NSPoint(x: 900, y: 100)]
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        var queue = [event(.leftMouseDragged), event(.leftMouseDragged), event(.leftMouseUp), event(.leftMouseDragged)]
        var current = positions[0]
        WindowFollower.follow(window, nextEvent: {
            guard !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            positions.removeFirst()          // each event brings the pointer to the next position
            current = positions.first ?? current
            return next
        }, pointer: { current }, screens: screens)
        // Start was (500,500); two drags later the pointer is at (560,440): the window moved by (+60,-60); the release stopped it.
        XCTAssertEqual(window.frame.origin.x, start.x + 60, accuracy: 0.01)
        XCTAssertEqual(window.frame.origin.y, start.y - 60, accuracy: 0.01)
        XCTAssertEqual(queue.count, 1, "the event after the release was left alone")
    }
}
