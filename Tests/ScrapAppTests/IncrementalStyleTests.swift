import XCTest
import AppKit
@testable import ScrapApp
import ScrapCore

/// Restyling only what an edit touched must give exactly what restyling everything gives.
final class IncrementalStyleTests: XCTestCase {
    private let corpus = """
    # Heading one
    Some **bold** and *italic* text with `code` and a [link](https://example.com).
    - [ ] task one
    - [x] task two
    1. first
    2. second
    > a quote
    ```swift
    let x = 1
    // comment
    ```
    plain paragraph here

    ○ smart bullet
    ## Second heading
    https://www.example.com/path
    """

    private func style() -> MarkdownStyle {
        MarkdownStyle(theme: Themes.all[0], baseFont: .systemFont(ofSize: 14), codeFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
                      colorHighlights: true, markers: .hide)
    }

    private func paragraph(_ caret: Int, in text: String) -> NSRange {
        let ns = text as NSString
        return ns.paragraphRange(for: NSRange(location: min(caret, ns.length), length: 0))
    }

    private func full(_ text: String, caret: Int) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownStyler.apply(MarkdownHighlighter.spans(in: text), to: storage, range: NSRange(location: 0, length: storage.length),
                             reveal: paragraph(caret, in: text), style: style())
        return storage
    }

    private func assertSame(_ a: NSTextStorage, _ b: NSTextStorage, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.string, b.string, file: file, line: line)
        var i = 0
        while i < a.length {
            var ra = NSRange(), rb = NSRange()
            let x = a.attributes(at: i, effectiveRange: &ra) as NSDictionary
            let y = b.attributes(at: i, effectiveRange: &rb) as NSDictionary
            if !x.isEqual(y) {
                XCTFail("attributes differ at \(i) (\((a.string as NSString).substring(with: NSRange(location: max(0, i - 10), length: min(30, a.length - max(0, i - 10)))))): \(message)", file: file, line: line)
                return
            }
            i = max(NSMaxRange(ra), i + 1)
        }
    }

    /// One edit, as the text view would make it: the new characters take on the attributes beside them.
    private func edit(_ storage: NSTextStorage, range: NSRange, with string: String) {
        storage.replaceCharacters(in: range, with: string)
    }

    func testEditsGiveTheSameStylingAsRestylingEverything() {
        var seed: UInt64 = 42
        func next(_ n: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(max(n, 1)))
        }
        let pieces = ["a", " ", "\n", "**", "*", "`", "```", "```swift\n", "- ", "- [ ] ", "1. ", "# ", "> ", "[x](http://a.b)", "○ ", "\n\n", "x y"]
        for round in 0..<60 {
            var text = corpus
            var caret = next(text.utf16.count)
            let storage = full(text, caret: caret)
            var spans = MarkdownHighlighter.spans(in: text)
            var reveal = paragraph(caret, in: text)
            for step in 0..<12 {
                let ns = text as NSString
                let location = next(ns.length + 1)
                let length = next(4) == 0 ? min(next(8), ns.length - location) : 0
                let insert = next(5) == 0 ? "" : pieces[next(pieces.count)]
                let oldText = text
                let range = NSRange(location: location, length: length)
                edit(storage, range: range, with: insert)
                text = storage.string
                caret = location + (insert as NSString).length
                let newSpans = MarkdownHighlighter.spans(in: text)
                let newReveal = paragraph(caret, in: text)
                MarkdownStyler.applyEdit(oldText: oldText, oldSpans: spans, newSpans: newSpans, oldReveal: reveal, newReveal: newReveal,
                                         to: storage, style: style())
                spans = newSpans
                reveal = newReveal
                assertSame(storage, full(text, caret: caret), "round \(round) step \(step): replaced \(range) with \(insert.debugDescription)")
            }
        }
    }

    func testTypingInOneParagraphOfALargePadRestylesOnlyThatParagraph() {
        var text = ""
        for i in 0..<400 { text += "Line \(i) with **bold** and a [link](https://x.com)\n" }
        let storage = full(text, caret: 5)
        let old = text
        let oldSpans = MarkdownHighlighter.spans(in: old)
        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: "Z")
        let ranges = MarkdownStyler.applyEdit(oldText: old, oldSpans: oldSpans, newSpans: MarkdownHighlighter.spans(in: storage.string),
                                              oldReveal: paragraph(5, in: old), newReveal: paragraph(6, in: storage.string), to: storage, style: style())
        XCTAssertEqual(ranges.count, 1)
        XCTAssertLessThan(ranges[0].length, 80, "only the edited line")
    }

    func testOpeningAFenceRestylesTheBlockBelow() {
        let text = "intro\ncode line\nmore code\n```\nafter\n"
        let storage = full(text, caret: 0)
        let oldSpans = MarkdownHighlighter.spans(in: text)
        storage.replaceCharacters(in: NSRange(location: 6, length: 0), with: "```\n")
        let new = storage.string
        let ranges = MarkdownStyler.applyEdit(oldText: text, oldSpans: oldSpans, newSpans: MarkdownHighlighter.spans(in: new),
                                              oldReveal: paragraph(0, in: text), newReveal: paragraph(10, in: new), to: storage, style: style())
        XCTAssertGreaterThan(ranges.map(\.length).reduce(0, +), 20)
        assertSame(storage, full(new, caret: 10), "fence")
    }
}

extension IncrementalStyleTests {
    func testTypingStaysFastOnALargePad() {
        var text = ""
        while text.utf8.count < 100 * 1024 { text += "# Heading\nSome **bold** and *italic* text with `code` and a [link](https://x.com).\n- [ ] task\n```swift\nlet x = 1\n```\n\n" }
        let storage = NSTextStorage(string: text)
        let spans = MarkdownHighlighter.spans(in: text)
        MarkdownStyler.apply(spans, to: storage, range: NSRange(location: 0, length: storage.length), reveal: NSRange(location: 0, length: 0), style: style())
        let started = Date()
        var oldText = text, oldSpans = spans
        for i in 0..<5 {
            storage.replaceCharacters(in: NSRange(location: 500 + i, length: 0), with: "z")
            let newSpans = MarkdownHighlighter.spans(in: storage.string)
            MarkdownStyler.applyEdit(oldText: oldText, oldSpans: oldSpans, newSpans: newSpans, oldReveal: NSRange(location: 0, length: 0),
                                     newReveal: paragraph(501 + i, in: storage.string), to: storage, style: style())
            oldText = storage.string; oldSpans = newSpans
        }
        let each = Date().timeIntervalSince(started) / 5
        print("PROBE 100KB keystroke \(Int(each * 1000)) ms")
        XCTAssertLessThan(each, 0.5, "a keystroke in a 100 KB pad (debug build) should not restyle the whole pad")
    }
}
