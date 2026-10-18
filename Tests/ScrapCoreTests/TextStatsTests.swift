import XCTest
@testable import ScrapCore

final class TextStatsTests: XCTestCase {
    func testCounts() {
        XCTAssertEqual(TextStats.summary(""), "0 lines · 0 words · 0 characters")
        XCTAssertEqual(TextStats.summary("a"), "1 line · 1 word · 1 character")
        XCTAssertEqual(TextStats.summary("one two\nthree"), "2 lines · 3 words · 13 characters")
        XCTAssertEqual(TextStats.summary("café ☕"), "1 line · 2 words · 6 characters")
    }

    func testSelectionWording() {
        XCTAssertEqual(TextStats.summary("two words", selection: true), "1 line · 2 words · 9 characters selected")
    }
}
