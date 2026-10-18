import XCTest
@testable import ScrapCore

final class HighlightPerformanceTests: XCTestCase {
    func testLargeCodeBlockIsFastEnoughToHighlightOnEveryKeystroke() {
        let line = "def handler(self, request, *args, **kwargs):  # comment with \"quotes\" and 12345\n    return {'ok': True, \"n\": len(args) + 42}\n"
        let body = String(repeating: line, count: 1500)   // about 200 KB
        let text = "```python\n" + body + "```\n"
        let start = Date()
        let spans = MarkdownHighlighter.spans(in: text)
        let elapsed = Date().timeIntervalSince(start)
        print("highlighted \(text.utf16.count) chars into \(spans.count) spans in \(elapsed)s")
        XCTAssertGreaterThan(spans.count, 10_000)
        XCTAssertLessThan(elapsed, 0.5, "must stay well under a frame budget per keystroke for realistic sizes")
    }
}
