import XCTest
@testable import ScrapCore

final class HelloTests: XCTestCase {
    func testEmailValidation() {
        for ok in ["a@b.co", "first.last+tag@example.com", "x@sub.domain.org"] { XCTAssertTrue(EmailValidator.isValid(ok), ok) }
        for bad in ["", "plain", "a@b", "a@@b.co", "a b@c.de", "@b.co", "a@.co "] { XCTAssertFalse(EmailValidator.isValid(bad), bad) }
    }

    func testEntryEmptiness() {
        XCTAssertTrue(HelloEntry(name: " ", email: "", message: "\n").isEmpty)
        XCTAssertFalse(HelloEntry(name: "", email: "a@b.co", message: "").isEmpty)
    }

    func testStoreAppendsAndNeverMarksSent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HelloStore(directory: dir)
        XCTAssertEqual(store.load(), [])
        try store.save(HelloEntry(name: "A", email: "a@b.co", message: "hi", date: Date(timeIntervalSince1970: 0)))
        try store.save(HelloEntry(name: "B", email: "", message: "more", date: Date(timeIntervalSince1970: 60)))
        let all = store.load()
        XCTAssertEqual(all.map(\.name), ["A", "B"])
        XCTAssertTrue(all.allSatisfy { !$0.sentToServer })
        XCTAssertEqual(all[0].date, Date(timeIntervalSince1970: 0))
    }
}
