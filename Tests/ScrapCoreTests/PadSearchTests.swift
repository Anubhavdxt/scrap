import XCTest
@testable import ScrapCore

final class PadSearchTests: XCTestCase {
    private func search(_ q: String, _ pads: [String]) -> SearchResult {
        var list: [(number: Int, text: String)] = []
        for (i, t) in pads.enumerated() { list.append((i + 1, t)) }
        return PadSearch.search(q, in: list)
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertEqual(search("  ", ["hello"]), .empty)
        XCTAssertEqual(search("x", []), .empty)
    }

    func testFindsTextCaseAndAccentInsensitively() {
        let r = search("CAFE", ["Meet at the café\nnothing"])
        XCTAssertEqual(r.hits.count, 1)
        XCTAssertEqual(r.hits[0].line, 1)
        XCTAssertFalse(r.isClosest)
    }

    func testAllWordsMustBeOnTheLine() {
        let r = search("milk eggs", ["milk and eggs\nonly milk here"])
        XCTAssertEqual(r.hits.map(\.line), [1])
        XCTAssertFalse(r.isClosest)
    }

    func testWholeWordsRankAboveWordPartsAbovePartsInside() {
        let r = search("cat", ["concatenate\ncatalog\nthe cat sat"])
        XCTAssertEqual(r.hits.map(\.line), [3, 2, 1])
    }

    func testTypoStillFindsTheWordAndSaysClosest() {
        let r = search("recipie", ["a good recipe for soup"])
        XCTAssertEqual(r.hits.count, 1)
        XCTAssertTrue(r.isClosest)
        XCTAssertEqual(r.hits[0].matches.count, 1)
    }

    func testSwappedLettersCountAsOneTypo() {
        XCTAssertEqual(search("teh", ["teh"]).hits.count, 1)
        XCTAssertFalse(search("frist", ["the first one"]).hits.isEmpty)
    }

    func testShortWordsAreNotTypoMatched() {
        XCTAssertTrue(search("cot", ["cat"]).hits.isEmpty)
    }

    func testPartialLinesAreOfferedAsClosestWhenNothingHasEveryWord() {
        let r = search("milk bread", ["only milk here"])
        XCTAssertEqual(r.hits.count, 1)
        XCTAssertTrue(r.isClosest)
    }

    func testExactMatchesHideTypoOnes() {
        let r = search("recipe", ["recipe", "recipie"])
        XCTAssertEqual(r.hits.map(\.pad), [1])
        XCTAssertFalse(r.isClosest)
    }

    func testCapsHitsPerPad() {
        let r = search("x", [String(repeating: "x line\n", count: 10)])
        XCTAssertEqual(r.hits.count, 3)
    }

    func testTargetPointsAtTheMatchInThePad() {
        let text = "first\nsecond has needle in it"
        let r = search("needle", [text])
        let t = r.hits[0].target
        XCTAssertEqual((text as NSString).substring(with: t), "needle")
        XCTAssertEqual(r.hits[0].line, 2)
    }

    func testLongLinesAreCroppedAroundTheMatch() {
        let line = String(repeating: "lorem ipsum ", count: 20) + "needle" + String(repeating: " dolor", count: 30)
        let hit = search("needle", [line]).hits[0]
        XCTAssertLessThan(hit.text.count, 100)
        XCTAssertTrue(hit.text.hasPrefix("…"))
        XCTAssertTrue(hit.text.hasSuffix("…"))
        let m = hit.matches[0]
        XCTAssertEqual((hit.text as NSString).substring(with: m), "needle")
    }

    func testIndentationIsTrimmedAndMatchRangesFollow() {
        let hit = search("milk", ["    - buy milk"]).hits[0]
        XCTAssertEqual(hit.text, "- buy milk")
        XCTAssertEqual((hit.text as NSString).substring(with: hit.matches[0]), "milk")
    }

    func testEditDistance() {
        XCTAssertEqual(PadSearch.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(PadSearch.editDistance("ab", "ba"), 1)
        XCTAssertEqual(PadSearch.editDistance("", "abc"), 3)
    }

    func testSomeoneStillTypingFindsTheLongerWord() {
        XCTAssertFalse(search("grocer", ["grocery list"]).hits.isEmpty)
    }

    func testResultsAreRankedByRelevanceThenPad() {
        let r = search("tea", ["steam tea", "tea"])
        XCTAssertEqual(r.hits.first?.pad, 2)
    }
}
