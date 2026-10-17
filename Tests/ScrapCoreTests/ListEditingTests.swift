import XCTest
@testable import ScrapCore

final class ListEditingTests: XCTestCase {
    /// Applies an edit like the text view would, returning (text, selection).
    private func apply(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (result, edit.selection)
    }

    private func caret(_ text: String, at offset: Int? = nil) -> NSRange {
        NSRange(location: offset ?? (text as NSString).length, length: 0)
    }

    // MARK: Return

    func testReturnContinuesBullets() {
        for (text, expected) in [("- one", "- one\n- "), ("* one", "* one\n* "), ("+ one", "+ one\n+ "), ("  - nested", "  - nested\n  - ")] {
            let (out, sel) = apply(ListEditing.returnKey(in: text, selection: caret(text)), to: text)!
            XCTAssertEqual(out, expected)
            XCTAssertEqual(sel, caret(expected))
        }
    }

    func testReturnNumbersAndTasks() {
        XCTAssertEqual(apply(ListEditing.returnKey(in: "1. a", selection: caret("1. a")), to: "1. a")!.0, "1. a\n2. ")
        XCTAssertEqual(apply(ListEditing.returnKey(in: "9) a", selection: caret("9) a")), to: "9) a")!.0, "9) a\n10) ")
        XCTAssertEqual(apply(ListEditing.returnKey(in: "- [x] done", selection: caret("- [x] done")), to: "- [x] done")!.0, "- [x] done\n- [ ] ")
    }

    func testReturnOnEmptyItemEndsTheList() {
        let text = "- a\n- "
        let (out, sel) = apply(ListEditing.returnKey(in: text, selection: caret(text)), to: text)!
        XCTAssertEqual(out, "- a\n")
        XCTAssertEqual(sel, caret("- a\n"))
        let task = "- [ ] "
        XCTAssertEqual(apply(ListEditing.returnKey(in: task, selection: caret(task)), to: task)!.0, "")
    }

    func testReturnSplitsTheItemAtTheCursor() {
        let text = "- hello world"
        let (out, sel) = apply(ListEditing.returnKey(in: text, selection: caret(text, at: 7)), to: text)!
        XCTAssertEqual(out, "- hello\n-  world")
        XCTAssertEqual(sel, caret(out, at: 10))
    }

    func testReturnLeavesOtherLinesAlone() {
        for text in ["plain text", "", "# heading", "-not a list", "1.nope"] {
            XCTAssertNil(ListEditing.returnKey(in: text, selection: caret(text)), text)
        }
        let inMarker = "- item"
        XCTAssertNil(ListEditing.returnKey(in: inMarker, selection: caret(inMarker, at: 1)))
        XCTAssertNil(ListEditing.returnKey(in: "- a", selection: NSRange(location: 0, length: 3)), "a selection is left to the text view")
    }

    func testReturnInMiddleOfDocumentAndWithUnicode() {
        let text = "intro\n- café ☕\noutro"
        let at = ("intro\n- café ☕" as NSString).length
        let (out, sel) = apply(ListEditing.returnKey(in: text, selection: caret(text, at: at)), to: text)!
        XCTAssertEqual(out, "intro\n- café ☕\n- \noutro")
        XCTAssertEqual(sel, caret(out, at: at + 3))
    }

    // MARK: Indent

    func testIndentAndOutdentOneLine() {
        let text = "- a\n- b"
        let at = ("- a\n- b" as NSString).length
        let (out, sel) = apply(ListEditing.indent(in: text, selection: caret(text, at: at), outdent: false), to: text)!
        XCTAssertEqual(out, "- a\n  - b")
        XCTAssertEqual(sel, caret(out, at: at + 2))
        let (back, sel2) = apply(ListEditing.indent(in: out, selection: sel, outdent: true), to: out)!
        XCTAssertEqual(back, text)
        XCTAssertEqual(sel2, caret(text, at: at))
    }

    func testIndentSeveralLines() {
        let text = "- a\n- b\n- c"
        let (out, sel) = apply(ListEditing.indent(in: text, selection: NSRange(location: 0, length: 7), outdent: false), to: text)!
        XCTAssertEqual(out, "  - a\n  - b\n- c")
        XCTAssertEqual(sel, NSRange(location: 0, length: ("  - a\n  - b" as NSString).length))
    }

    func testOutdentWithNothingToRemoveAndNonListLines() {
        XCTAssertNil(ListEditing.indent(in: "- a", selection: caret("- a"), outdent: true))
        XCTAssertNil(ListEditing.indent(in: "plain", selection: caret("plain"), outdent: false))
        XCTAssertNil(ListEditing.indent(in: "- a\nplain", selection: NSRange(location: 0, length: 9), outdent: false))
    }

    // MARK: Checkbox

    func testToggleCheckbox() {
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: "- [ ] a", selection: caret("- [ ] a")), to: "- [ ] a")!.0, "- [x] a")
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: "- [x] a", selection: caret("- [x] a")), to: "- [x] a")!.0, "- [ ] a")
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: "* [X] a", selection: caret("* [X] a")), to: "* [X] a")!.0, "* [ ] a")
    }

    func testToggleTurnsItemsAndPlainLinesIntoTasks() {
        let (bullet, sel) = apply(ListEditing.toggleChecklist(in: "- a", selection: caret("- a")), to: "- a")!
        XCTAssertEqual(bullet, "- [ ] a")
        XCTAssertEqual(sel, caret(bullet))
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: "1. a", selection: caret("1. a")), to: "1. a")!.0, "1. [ ] a")
        let (plain, sel2) = apply(ListEditing.toggleChecklist(in: "buy milk", selection: caret("buy milk")), to: "buy milk")!
        XCTAssertEqual(plain, "- [ ] buy milk")
        XCTAssertEqual(sel2, caret(plain))
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: "  indented", selection: caret("  indented")), to: "  indented")!.0, "  - [ ] indented")
    }

    func testToggleOnlyTouchesTheCursorLine() {
        let text = "- [ ] a\n- [ ] b"
        let at = ("- [ ] a\n- [ ] " as NSString).length
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: text, selection: caret(text, at: at)), to: text)!.0, "- [ ] a\n- [x] b")
    }
}
