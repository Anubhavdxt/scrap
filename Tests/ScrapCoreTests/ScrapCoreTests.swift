import XCTest
@testable import ScrapCore

final class ScrapCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(Scrap.version.isEmpty)
    }
}
