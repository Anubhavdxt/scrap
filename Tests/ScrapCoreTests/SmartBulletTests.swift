import XCTest
@testable import ScrapCore

final class SmartBulletTests: XCTestCase {
    private func apply(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }
    private func caret(_ text: String, _ at: Int? = nil) -> NSRange { NSRange(location: at ?? (text as NSString).length, length: 0) }

    // MARK: The pairs

    func testPairsAreDistinctAndNeverMarkdownBullets() {
        XCTAssertEqual(SmartBullets.pairs.count, 8)
        let glyphs = SmartBullets.pairs.flatMap { [$0.open, $0.done] }
        XCTAssertEqual(Set(glyphs).count, glyphs.count, "no glyph is used twice, so a bullet always flips back")
        for pair in SmartBullets.pairs { XCTAssertNotEqual(pair.open, pair.done) }
        for glyph in glyphs { XCTAssertFalse(["-", "*", "+"].contains(glyph), "\(glyph) would be a Markdown bullet") }
    }

    func testMarkerDetection() throws {
        let m = try XCTUnwrap(SmartBullets.marker(in: "○ buy milk"))
        XCTAssertEqual(m.pair, 0)
        XCTAssertFalse(m.isDone)
        XCTAssertEqual(m.indentLength, 0)
        XCTAssertEqual(m.glyphLength, 1)
        XCTAssertEqual(m.length, 2)
        XCTAssertTrue(try XCTUnwrap(SmartBullets.marker(in: "● done")).isDone)
        XCTAssertEqual(try XCTUnwrap(SmartBullets.marker(in: "    ☆ nested")).indentLength, 4)
        XCTAssertEqual(try XCTUnwrap(SmartBullets.marker(in: "\t□ tabbed")).indentLength, 1)
    }

    func testEveryGlyphIsRecognisedIncludingEmoji() throws {
        for (i, pair) in SmartBullets.pairs.enumerated() {
            let open = try XCTUnwrap(SmartBullets.marker(in: "\(pair.open) x"), pair.open)
            XCTAssertEqual(open.pair, i)
            XCTAssertFalse(open.isDone)
            XCTAssertEqual(open.glyphLength, (pair.open as NSString).length)
            let done = try XCTUnwrap(SmartBullets.marker(in: "\(pair.done) x"), pair.done)
            XCTAssertEqual(done.pair, i)
            XCTAssertTrue(done.isDone)
            XCTAssertEqual(done.glyphLength, (pair.done as NSString).length, "emoji are two UTF-16 units")
            XCTAssertEqual(done.length, done.glyphLength + 1)
        }
    }

    func testNotABulletWithoutASpaceOrNotAtTheStart() {
        for line in ["", "plain", "○no space", "text ○ later", "-- x", "○○ x", "- ○ x"] {
            XCTAssertNil(SmartBullets.marker(in: line), line)
        }
        XCTAssertNotNil(SmartBullets.marker(in: "○"), "a bullet alone on its line is an empty item")
    }

    // MARK: Flipping

    func testToggleFlipsBetweenOpenAndDone() {
        let text = "○ one\n● two"
        XCTAssertEqual(apply(SmartBullets.toggle(in: text, at: 2), to: text)?.0, "● one\n● two")
        XCTAssertEqual(apply(SmartBullets.toggle(in: text, at: 8), to: text)?.0, "○ one\n○ two")
    }

    func testToggleWorksForEveryPairBothWays() {
        for pair in SmartBullets.pairs {
            let open = "\(pair.open) x", done = "\(pair.done) x"
            XCTAssertEqual(apply(SmartBullets.toggle(in: open, at: 0), to: open)?.0, done)
            XCTAssertEqual(apply(SmartBullets.toggle(in: done, at: 0), to: done)?.0, open)
        }
    }

    func testToggleKeepsIndentationTextAndCaret() {
        let text = "intro\n  □ item with ○ inside"
        let (out, sel) = apply(SmartBullets.toggle(in: text, at: 12), to: text)!
        XCTAssertEqual(out, "intro\n  ■ item with ○ inside")
        XCTAssertEqual(sel, NSRange(location: 12, length: 0))
        XCTAssertNil(SmartBullets.toggle(in: "plain line", at: 3))
        XCTAssertNil(SmartBullets.toggle(in: "x", at: 99))
    }

    func testCommandReturnFlipsASmartBulletBeforeAnythingElse() {
        let text = "☆ star"
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: text, selection: caret(text)), to: text)?.0, "★ star")
    }

    // MARK: Return and Backspace

    func testReturnContinuesWithTheOpenBullet() {
        let text = "● finished item"
        let (out, sel) = apply(ListEditing.returnKey(in: text, selection: caret(text)), to: text)!
        XCTAssertEqual(out, "● finished item\n○ ")
        XCTAssertEqual(sel, caret(out))
        let indented = "  ■ nested"
        XCTAssertEqual(apply(ListEditing.returnKey(in: indented, selection: caret(indented)), to: indented)?.0, "  ■ nested\n  □ ")
    }

    func testReturnOnAnEmptyBulletEndsTheList() {
        let text = "○ a\n○ "
        let (out, sel) = apply(ListEditing.returnKey(in: text, selection: caret(text)), to: text)!
        XCTAssertEqual(out, "○ a\n")
        XCTAssertEqual(sel, caret(out))
    }

    func testReturnSplitsAnItemAndLeavesTheBulletAloneWhenInsideIt() {
        let text = "⭕ hello world"
        let at = ("⭕ hello" as NSString).length
        XCTAssertEqual(apply(ListEditing.returnKey(in: text, selection: caret(text, at)), to: text)?.0, "⭕ hello\n⭕  world")
        XCTAssertNil(ListEditing.returnKey(in: "○ item", selection: caret("○ item", 1)), "caret between the bullet and its space")
        XCTAssertNil(ListEditing.returnKey(in: "○ item", selection: caret("○ item"), continueLists: false, keepIndent: false))
    }

    func testBackspaceRightAfterTheBulletRemovesIt() {
        let text = "  ✅ done thing"
        let at = ("  ✅ " as NSString).length
        let (out, sel) = apply(ListEditing.backspace(in: text, selection: caret(text, at)), to: text)!
        XCTAssertEqual(out, "  done thing")
        XCTAssertEqual(sel, caret(out, 2))
        XCTAssertNil(ListEditing.backspace(in: "○ item", selection: caret("○ item", 4)), "only right after the bullet")
    }

    func testTabIndentsASmartBulletLine() {
        let text = "○ item"
        XCTAssertEqual(apply(ListEditing.indent(in: text, selection: caret(text), outdent: false), to: text)?.0, "  ○ item")
    }

    // MARK: Choosing a bullet from the picker

    private func insert(_ pair: Int, _ text: String, _ at: Int? = nil) -> (String, NSRange)? {
        apply(ListEditing.insertSmartBullet(pair, in: text, selection: caret(text, at)), to: text)
    }

    func testInsertOnAPlainLineGoesInFrontOfTheText() {
        let (out, sel) = insert(2, "buy milk", 3)!
        XCTAssertEqual(out, "▷ buy milk")
        XCTAssertEqual(sel, caret(out, 5), "the caret stays on the same letter")
        XCTAssertEqual(insert(0, "")?.0, "○ ")
        XCTAssertEqual(insert(3, "  indented", 6)?.0, "  ☆ indented", "after the indentation")
    }

    func testInsertReplacesAnExistingBulletOrMarkdownMarker() {
        XCTAssertEqual(insert(1, "○ item")?.0, "□ item")
        XCTAssertEqual(insert(1, "● done item")?.0, "□ done item", "a chosen bullet starts open")
        XCTAssertEqual(insert(0, "- plain")?.0, "○ plain")
        XCTAssertEqual(insert(0, "- [ ] task")?.0, "○ task")
        XCTAssertEqual(insert(0, "- [x] task")?.0, "○ task")
        XCTAssertEqual(insert(7, "3. numbered")?.0, "⭕ numbered")
        XCTAssertNil(insert(99, "x"))
    }

    func testInsertOnlyTouchesTheCursorLine() {
        let text = "one\ntwo\nthree"
        XCTAssertEqual(insert(0, text, 5)?.0, "one\n○ two\nthree")
    }
}

final class SymbolCatalogTests: XCTestCase {
    func testTheGroupsTotShows() {
        XCTAssertEqual(SymbolCatalog.groups.map(\.name),
                       ["Smart Bullets", "Dividers", "Bullets", "Checkmarks", "Arrows", "Numbers", "Technical", "Symbols"])
    }

    func testNothingIsEmptyOrDuplicatedWithinAGroup() {
        for group in SymbolCatalog.groups {
            XCTAssertFalse(group.items.isEmpty, group.name)
            XCTAssertEqual(Set(group.items.map(\.id)).count, group.items.count, "\(group.name) has a duplicate")
            for item in group.items {
                XCTAssertFalse(item.label.trimmingCharacters(in: .whitespaces).isEmpty, "\(group.name) has a blank label")
                XCTAssertFalse(item.title.isEmpty)
            }
        }
    }

    func testSmartBulletsGroupCoversTheTaskAndEveryPair() {
        let group = SymbolCatalog.groups[0]
        XCTAssertEqual(group.items.first?.kind, .markdownTask)
        let pairIndexes = group.items.compactMap { item -> Int? in if case .smartBullet(let i) = item.kind { return i } else { return nil } }
        XCTAssertEqual(pairIndexes, Array(SmartBullets.pairs.indices))
    }

    func testDividersAreWholeLinesAndTheRestAreSingleCharacters() {
        for item in SymbolCatalog.groups[1].items {
            guard case .divider(let line) = item.kind else { return XCTFail("not a divider") }
            XCTAssertGreaterThan(line.count, 5)
            XCTAssertFalse(line.contains("\n"))
        }
        for group in SymbolCatalog.groups.dropFirst(2) {
            for item in group.items {
                guard case .text(let s) = item.kind else { return XCTFail("\(group.name) has a non-text item") }
                XCTAssertEqual(s.count, 1, "\(s) in \(group.name)")
            }
        }
    }
}

final class SymbolInsertionTests: XCTestCase {
    func testInsertTextReplacesTheSelectionAndMovesOn() {
        let edit = Formatting.insertText("→", in: "a b c", selection: NSRange(location: 2, length: 1))
        XCTAssertEqual(("a b c" as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "a → c")
        XCTAssertEqual(edit.selection, NSRange(location: 3, length: 0))
        let emoji = Formatting.insertText("🔴", in: "", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(emoji.selection, NSRange(location: 2, length: 0), "an emoji is two UTF-16 units")
    }

    func testDividerGoesOnItsOwnLine() {
        let text = "title"
        let edit = Formatting.insertDividerLine("────", in: text, selection: NSRange(location: 5, length: 0))
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(out, "title\n────\n")
        XCTAssertEqual(edit.selection, NSRange(location: out.utf16.count, length: 0))
    }

    func testDividerInTheMiddleLeavesNoStrayBlankLine() {
        let text = "one\ntwo\nthree"
        let edit = Formatting.insertDividerLine("────", in: text, selection: NSRange(location: 1, length: 0))
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        XCTAssertEqual(out, "one\n────\ntwo\nthree")
        XCTAssertEqual((out as NSString).substring(from: edit.selection.location), "two\nthree", "the caret is at the start of the next line")
    }

    func testDividerOnABlankLineReplacesIt() {
        let text = "a\n\nb"
        let edit = Formatting.insertDividerLine("━━━", in: text, selection: NSRange(location: 2, length: 0))
        XCTAssertEqual((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), "a\n━━━\nb", "the blank line becomes the divider")
        XCTAssertEqual(edit.selection, NSRange(location: 6, length: 0), "the caret lands at the start of the next line")
    }
}

final class SmartBulletHighlightTests: XCTestCase {
    private func markers(_ text: String) -> [ListMarker] { MarkdownHighlighter.spans(in: text).compactMap(\.marker) }

    func testOpenAndDoneMarkers() {
        XCTAssertEqual(markers("○ open"), [ListMarker(kind: .smartOpen, indentColumns: 0, columns: 2, glyphLength: 1)])
        XCTAssertEqual(markers("● done"), [ListMarker(kind: .smartDone, indentColumns: 0, columns: 2, glyphLength: 1)])
        XCTAssertEqual(markers("  🔴 x"), [ListMarker(kind: .smartDone, indentColumns: 2, columns: 3, glyphLength: 2)])
    }

    func testDoneItemsAreStruckThroughAndOpenOnesAreNot() {
        let done = MarkdownHighlighter.spans(in: "✅ shipped")
        XCTAssertEqual(done.first { $0.strike }.map { ("✅ shipped" as NSString).substring(with: $0.range) }, "shipped")
        XCTAssertNil(MarkdownHighlighter.spans(in: "❌ todo").first { $0.strike })
    }

    func testTheTextAfterABulletIsStillStyled() {
        let spans = MarkdownHighlighter.spans(in: "○ do **this** now")
        XCTAssertTrue(spans.contains { $0.bold })
        XCTAssertEqual(spans.filter(\.syntax).count, 2)
    }

    func testMarkdownListsAreUnchanged() {
        XCTAssertEqual(markers("- [ ] task").first?.kind, .taskOpen)
        XCTAssertEqual(markers("- item").first?.kind, .bullet)
        XCTAssertEqual(markers("+ item").first?.kind, .bullet, "a plus is a Markdown bullet, never a smart one")
        XCTAssertEqual(markers("1. step").first?.kind, .number)
    }

    func testNotInsideCode() {
        XCTAssertTrue(markers("```\n○ not a bullet\n```").isEmpty)
    }
}
