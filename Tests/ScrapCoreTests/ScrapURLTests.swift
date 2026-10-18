import XCTest
@testable import ScrapCore

final class ScrapURLTests: XCTestCase {
    private func parse(_ s: String) -> Result<ScrapURL.Action, ScrapURL.Problem> { ScrapURL.parse(URL(string: s)!) }

    func testOpen() {
        XCTAssertEqual(parse("scrap://open"), .success(.open(pad: nil)))
        XCTAssertEqual(parse("scrap://open?pad=3"), .success(.open(pad: 3)))
        XCTAssertEqual(parse("scrap://open/?pad=12"), .success(.open(pad: 12)))
    }

    func testAdd() {
        XCTAssertEqual(parse("scrap://add?text=hello"), .success(.add(text: "hello", pad: nil)))
        XCTAssertEqual(parse("scrap://add?text=hello&pad=2"), .success(.add(text: "hello", pad: 2)))
        XCTAssertEqual(parse("scrap://add?pad=2&text=hello"), .success(.add(text: "hello", pad: 2)), "order doesn't matter")
    }

    func testPercentDecodingAndPlus() {
        XCTAssertEqual(parse("scrap://add?text=hello%20world%0Asecond%20line"), .success(.add(text: "hello world\nsecond line", pad: nil)))
        XCTAssertEqual(parse("scrap://add?text=caf%C3%A9%20%E2%98%95"), .success(.add(text: "café ☕", pad: nil)))
        XCTAssertEqual(parse("scrap://add?text=a%2Bb%26c%3Dd"), .success(.add(text: "a+b&c=d", pad: nil)), "encoded separators stay in the text")
        XCTAssertEqual(parse("scrap://add?text=1+1"), .success(.add(text: "1+1", pad: nil)), "a plus is a plus, not a space")
    }

    func testCaseInsensitiveSchemeActionAndNames() {
        XCTAssertEqual(parse("SCRAP://ADD?TEXT=x&PAD=4"), .success(.add(text: "x", pad: 4)))
    }

    func testUnknownExtraParametersAreIgnored() {
        XCTAssertEqual(parse("scrap://add?text=x&source=safari&x-success=https://evil.example"), .success(.add(text: "x", pad: nil)),
                       "callbacks are never honoured: there is nothing to call back with")
    }

    func testRefusals() {
        XCTAssertEqual(parse("https://example.com/add?text=x"), .failure(.notScrap))
        XCTAssertEqual(parse("scrap://read?pad=1"), .failure(.unknownAction("read")), "there is no way to read a pad out")
        XCTAssertEqual(parse("scrap://get?pad=1"), .failure(.unknownAction("get")))
        XCTAssertEqual(parse("scrap://"), .failure(.unknownAction("")))
        XCTAssertEqual(parse("scrap://add"), .failure(.missingText))
        XCTAssertEqual(parse("scrap://add?text="), .failure(.missingText))
        XCTAssertEqual(parse("scrap://add?text=%20%0A%20"), .failure(.missingText), "only whitespace")
        XCTAssertEqual(parse("scrap://open?pad=abc"), .failure(.badPad("abc")))
        XCTAssertEqual(parse("scrap://open?pad=0"), .failure(.badPad("0")))
        XCTAssertEqual(parse("scrap://open?pad=-2"), .failure(.badPad("-2")))
        XCTAssertEqual(parse("scrap://add?text=x&pad="), .failure(.badPad("")))
    }

    func testTheSizeLimit() {
        let limit = ScrapURL.maxTextBytes
        XCTAssertEqual(parse("scrap://add?text=" + String(repeating: "a", count: limit)), .success(.add(text: String(repeating: "a", count: limit), pad: nil)))
        XCTAssertEqual(parse("scrap://add?text=" + String(repeating: "a", count: limit + 1)), .failure(.tooLong(limit + 1)))
        // The limit is in bytes, so multi-byte text counts for more.
        let emoji = String(repeating: "%F0%9F%98%80", count: limit / 4 + 1)
        if case .failure(.tooLong) = parse("scrap://add?text=" + emoji) {} else { XCTFail("4-byte characters count as 4 bytes") }
    }

    func testEveryProblemSaysSomething() {
        let problems: [ScrapURL.Problem] = [.notScrap, .unknownAction("x"), .missingText, .tooLong(30000), .badPad("q")]
        for p in problems { XCTAssertFalse((p.errorDescription ?? "").isEmpty) }
    }
}
