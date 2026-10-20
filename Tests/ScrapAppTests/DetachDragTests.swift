import XCTest
@testable import ScrapApp

final class DetachDragTests: XCTestCase {
    func testASmallWobbleIsNotAnAttempt() {
        XCTAssertFalse(DetachDrag.shouldDetach(from: NSPoint(x: 100, y: 100), to: NSPoint(x: 103, y: 102)))
    }

    func testDraggingFarEnoughInAnyDirectionPullsItOff() {
        let start = NSPoint(x: 100, y: 100)
        for end in [NSPoint(x: 100, y: 90), NSPoint(x: 112, y: 100), NSPoint(x: 94, y: 94), NSPoint(x: 100, y: 108)] {
            XCTAssertTrue(DetachDrag.shouldDetach(from: start, to: end), "\(end)")
        }
    }
}
