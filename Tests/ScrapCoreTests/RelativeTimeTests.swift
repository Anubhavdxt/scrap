import XCTest
@testable import ScrapCore

final class RelativeTimeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func text(_ secondsAgo: TimeInterval) -> String { RelativeTime.text(for: now.addingTimeInterval(-secondsAgo), now: now) }

    func testJustNow() {
        XCTAssertEqual(text(0), "just now")
        XCTAssertEqual(text(44), "just now")
        XCTAssertEqual(RelativeTime.text(for: now.addingTimeInterval(30), now: now), "just now", "a clock slightly ahead never shows a negative time")
    }

    func testMinutesAndHours() {
        XCTAssertEqual(text(45), "1 min ago")
        XCTAssertEqual(text(89), "1 min ago")
        XCTAssertEqual(text(5 * 60), "5 min ago")
        XCTAssertEqual(text(59 * 60), "59 min ago")
        XCTAssertEqual(text(60 * 60), "1 hr ago")
        XCTAssertEqual(text(3 * 3600), "3 hr ago")
        XCTAssertEqual(text(23 * 3600), "23 hr ago")
    }

    func testDaysAndDates() {
        XCTAssertEqual(text(3 * 86_400 + 3600), "3 days ago")
        let old = RelativeTime.text(for: now.addingTimeInterval(-40 * 86_400), now: now)
        XCTAssertFalse(old.contains("ago"), old)
        XCTAssertFalse(old.isEmpty)
        let lastYear = RelativeTime.text(for: now.addingTimeInterval(-500 * 86_400), now: now)
        XCTAssertTrue(lastYear.contains("20"), "an older year is spelled out: \(lastYear)")
    }
}
