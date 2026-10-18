import XCTest
@testable import ScrapCore

final class FormattingTests: XCTestCase {
    /// Applies an edit and returns the new text with the selection marked by [ ] (or | for a caret).
    private func run(_ edit: TextEdit?, on text: String) -> String? {
        guard let edit else { return nil }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement) as NSString
        let sel = edit.selection
        if sel.length == 0 { return out.replacingCharacters(in: sel, with: "|") }
        let closed = out.replacingCharacters(in: NSRange(location: sel.upperBound, length: 0), with: "]") as NSString
        return closed.replacingCharacters(in: NSRange(location: sel.location, length: 0), with: "[")
    }

    private func toggle(_ style: Formatting.Style, _ text: String, _ location: Int, _ length: Int = 0) -> String? {
        run(Formatting.toggle(style, in: text, selection: NSRange(location: location, length: length)), on: text)
    }

    // MARK: Wrapping

    func testWrapsASelection() {
        XCTAssertEqual(toggle(.bold, "make this loud", 5, 4), "make **[this]** loud")
        XCTAssertEqual(toggle(.italic, "make this loud", 5, 4), "make *[this]* loud")
        XCTAssertEqual(toggle(.strikethrough, "make this loud", 5, 4), "make ~~[this]~~ loud")
        XCTAssertEqual(toggle(.code, "run make now", 4, 4), "run `[make]` now")
    }

    func testWrapsTheWordAtTheCaret() {
        XCTAssertEqual(toggle(.bold, "one two three", 5), "one **[two]** three")   // inside the word
        XCTAssertEqual(toggle(.bold, "one two three", 3), "**[one]** two three")   // right after a word
        XCTAssertEqual(toggle(.italic, "café ☕ time", 2), "*[café]* ☕ time")
    }

    func testEmptyPairWhenThereIsNoWord() {
        XCTAssertEqual(toggle(.bold, "a  b", 2), "a **|** b")
        XCTAssertEqual(toggle(.code, "", 0), "`|`")
    }

    func testSelectionSpacesStayOutsideTheMarkers() {
        XCTAssertEqual(toggle(.bold, "a  word  b", 1, 8), "a  **[word]**  b")
        XCTAssertEqual(toggle(.bold, "    ", 0, 4), "**|**", "only spaces selected: nothing to wrap")
    }

    // MARK: Unwrapping

    func testUnwrapsWhenMarkersSurroundTheTarget() {
        XCTAssertEqual(toggle(.bold, "make **this** loud", 7, 4), "make [this] loud")
        XCTAssertEqual(toggle(.bold, "make **this** loud", 8), "make [this] loud", "caret inside a bold word")
        XCTAssertEqual(toggle(.italic, "make *this* loud", 6, 4), "make [this] loud")
        XCTAssertEqual(toggle(.strikethrough, "~~gone~~", 2, 4), "[gone]")
        XCTAssertEqual(toggle(.code, "`x`", 1, 1), "[x]")
    }

    func testUnwrapsWhenTheSelectionIncludesTheMarkers() {
        XCTAssertEqual(toggle(.bold, "a **b** c", 2, 5), "a [b] c")
        XCTAssertEqual(toggle(.italic, "*b*", 0, 3), "[b]")
    }

    func testBoldAndItalicCoexist() {
        XCTAssertEqual(toggle(.bold, "*x*", 1, 1), "***[x]***", "bold on italic text adds, not removes")
        XCTAssertEqual(toggle(.italic, "**x**", 2, 1), "***[x]***", "italic on bold text adds, not removes")
        XCTAssertEqual(toggle(.italic, "***x***", 3, 1), "**[x]**", "removing italic leaves bold")
        XCTAssertEqual(toggle(.bold, "***x***", 3, 1), "*[x]*", "removing bold leaves italic")
    }

    func testToggleTwiceRestoresTheText() {
        for style in Formatting.Style.allCases {
            let first = Formatting.toggle(style, in: "hello world", selection: NSRange(location: 6, length: 5))!
            let styled = ("hello world" as NSString).replacingCharacters(in: first.range, with: first.replacement)
            let second = Formatting.toggle(style, in: styled, selection: first.selection)!
            XCTAssertEqual((styled as NSString).replacingCharacters(in: second.range, with: second.replacement), "hello world", "\(style)")
        }
    }

    // MARK: Several lines

    func testStylesEachSelectedLine() {
        let text = "one\n\ntwo words\nthree"
        let out = run(Formatting.toggle(.bold, in: text, selection: NSRange(location: 0, length: text.utf16.count)), on: text)!
        XCTAssertEqual(out, "[**one**\n\n**two words**\n**three**]")
    }

    func testUnwrapsEveryLineWhenAllAreStyled() {
        let text = "**one**\n**two**"
        let out = run(Formatting.toggle(.bold, in: text, selection: NSRange(location: 0, length: text.utf16.count)), on: text)!
        XCTAssertEqual(out, "[one\ntwo]")
    }

    func testOnlyStylesTheLinesThatAreNotStyleYet() {
        let text = "**one**\ntwo"
        let out = run(Formatting.toggle(.bold, in: text, selection: NSRange(location: 0, length: text.utf16.count)), on: text)!
        XCTAssertEqual(out, "[**one**\n**two**]")
    }

    func testBadSelectionsAreRejected() {
        XCTAssertNil(Formatting.toggle(.bold, in: "abc", selection: NSRange(location: 2, length: 5)))
    }

    // MARK: Divider

    func testDividerGoesBelowANonBlankLineWithABlankLineAbove() {
        let text = "title"
        let edit = Formatting.insertDivider(in: text, selection: NSRange(location: 5, length: 0))
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(out, "title\n\n---\n", "a blank line keeps it from turning `title` into a heading")
        XCTAssertEqual(edit.selection, NSRange(location: out.utf16.count, length: 0))
    }

    func testDividerOnABlankLineReplacesIt() {
        let text = "a\n\nb"
        let edit = Formatting.insertDivider(in: text, selection: NSRange(location: 2, length: 0))
        XCTAssertEqual((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "a\n---\n\nb")
        XCTAssertEqual(edit.selection, NSRange(location: 6, length: 0))
    }
}

final class TaskAndIndentTests: XCTestCase {
    private func run(_ edit: TextEdit?, on text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }

    func testToggleTaskAddsAndRemovesTheBox() {
        func toggle(_ t: String, _ at: Int) -> String? { run(ListEditing.toggleTask(in: t, selection: NSRange(location: at, length: 0)), on: t)?.0 }
        XCTAssertEqual(toggle("buy milk", 3), "- [ ] buy milk")
        XCTAssertEqual(toggle("", 0), "- [ ] ")
        XCTAssertEqual(toggle("  nested", 8), "  - [ ] nested")
        XCTAssertEqual(toggle("- item", 6), "- [ ] item")
        XCTAssertEqual(toggle("1. item", 7), "1. [ ] item")
        XCTAssertEqual(toggle("- [ ] item", 10), "- item")
        XCTAssertEqual(toggle("- [x] done", 10), "- done")
    }

    func testToggleTaskKeepsTheCaretOnTheSameText() {
        let (out, sel) = run(ListEditing.toggleTask(in: "buy milk", selection: NSRange(location: 4, length: 0)), on: "buy milk")!
        XCTAssertEqual(out, "- [ ] buy milk")
        XCTAssertEqual(sel, NSRange(location: 10, length: 0))
        let (back, sel2) = run(ListEditing.toggleTask(in: out, selection: sel), on: out)!
        XCTAssertEqual(back, "- buy milk")
        XCTAssertEqual(sel2, NSRange(location: 6, length: 0), "still right after `buy `")
    }

    func testReturnKeepsIndentationOnPlainLines() {
        let text = "    code line"
        let (out, sel) = run(ListEditing.returnKey(in: text, selection: NSRange(location: text.utf16.count, length: 0)), on: text)!
        XCTAssertEqual(out, "    code line\n    ")
        XCTAssertEqual(sel, NSRange(location: out.utf16.count, length: 0))
        XCTAssertEqual(run(ListEditing.returnKey(in: "\tx", selection: NSRange(location: 2, length: 0)), on: "\tx")!.0, "\tx\n\t")
    }

    func testReturnOnAnIndentOnlyLineClearsIt() {
        let text = "a\n    "
        let (out, sel) = run(ListEditing.returnKey(in: text, selection: NSRange(location: text.utf16.count, length: 0)), on: text)!
        XCTAssertEqual(out, "a\n")
        XCTAssertEqual(sel, NSRange(location: 2, length: 0))
    }

    func testReturnInsideTheIndentAndOnUnindentedLinesIsLeftAlone() {
        XCTAssertNil(ListEditing.returnKey(in: "    x", selection: NSRange(location: 2, length: 0)), "caret inside the leading spaces")
        XCTAssertNil(ListEditing.returnKey(in: "plain", selection: NSRange(location: 5, length: 0)))
    }

    func testTheTwoSettingsTurnTheBehavioursOff() {
        let list = "- a"
        XCTAssertNil(ListEditing.returnKey(in: list, selection: NSRange(location: 3, length: 0), continueLists: false, keepIndent: false))
        XCTAssertNotNil(ListEditing.returnKey(in: list, selection: NSRange(location: 3, length: 0), continueLists: true, keepIndent: false))
        let indented = "  - a"
        XCTAssertEqual(run(ListEditing.returnKey(in: indented, selection: NSRange(location: 5, length: 0), continueLists: false, keepIndent: true), on: indented)!.0,
                       "  - a\n  ", "with lists off an indented item is just an indented line")
        XCTAssertNil(ListEditing.returnKey(in: "    x", selection: NSRange(location: 5, length: 0), continueLists: true, keepIndent: false))
    }
}
