import XCTest
@testable import ScrapCore

final class CustomBulletsTests: XCTestCase {
    private typealias Pair = SmartBullets.Pair

    override func setUp() { SmartBullets.custom = [] }
    override func tearDown() { SmartBullets.custom = [] }   // the custom list is global, so never leak it into other tests

    private func apply(_ edit: TextEdit?, to text: String) -> String? {
        edit.map { (text as NSString).replacingCharacters(in: $0.range, with: $0.replacement) }
    }

    // MARK: Rules for one glyph

    func testASymbolOrEmojiIsAccepted() {
        for glyph in ["◇", "♥", "⬜", "🔹", "🟢", "✧", "☐", "¶", "§"] { XCTAssertNil(CustomBullets.problem(withGlyph: glyph), glyph) }
    }

    func testLettersDigitsAndKeyboardCharactersAreRefused() {
        for glyph in ["a", "Z", "7", "x", "é", "ж", "中", "-", "+", "*", ">", "#", "`", "_", ".", "!", " ", "\t"] {
            XCTAssertEqual(CustomBullets.problem(withGlyph: glyph), .notASymbol(glyph), "'\(glyph)' would turn ordinary lines into bullets")
        }
    }

    func testExactlyOneCharacter() {
        XCTAssertEqual(CustomBullets.problem(withGlyph: ""), .notOneCharacter(""))
        XCTAssertEqual(CustomBullets.problem(withGlyph: "◇◆"), .notOneCharacter("◇◆"))
        XCTAssertNil(CustomBullets.problem(withGlyph: "👍🏽"), "an emoji with a skin tone is one character")
        XCTAssertNil(CustomBullets.problem(withGlyph: "🏳️‍🌈"), "and so is a joined sequence")
    }

    // MARK: Rules for the list

    func testAValidListHasNoProblem() {
        XCTAssertNil(CustomBullets.validate([]))
        XCTAssertNil(CustomBullets.validate([Pair(open: "◇", done: "◆"), Pair(open: "♡", done: "♥")]))
    }

    func testDuplicatesAndBuiltInsAreRefused() {
        XCTAssertEqual(CustomBullets.validate([Pair(open: "○", done: "◆")]), .taken("○"), "a built-in glyph")
        XCTAssertEqual(CustomBullets.validate([Pair(open: "◇", done: "✅")]), .taken("✅"))
        XCTAssertEqual(CustomBullets.validate([Pair(open: "◇", done: "◆"), Pair(open: "◆", done: "♥")]), .taken("◆"), "a glyph of another custom pair")
        XCTAssertEqual(CustomBullets.validate([Pair(open: "◇", done: "◇")]), .same("◇"))
    }

    func testAtMostEight() {
        let nine = (0..<9).map { Pair(open: String(UnicodeScalar(0x1F300 + $0 * 2)!), done: String(UnicodeScalar(0x1F301 + $0 * 2)!)) }
        XCTAssertEqual(CustomBullets.validate(nine), .tooMany)
        XCTAssertNil(CustomBullets.validate(Array(nine.prefix(8))))
    }

    func testEveryProblemHasAReadableMessage() {
        let problems: [CustomBullets.Problem] = [.notOneCharacter("ab"), .notASymbol("a"), .same("◇"), .taken("○"), .tooMany]
        for problem in problems { XCTAssertFalse((problem.errorDescription ?? "").isEmpty) }
        XCTAssertTrue(CustomBullets.Problem.taken("○").errorDescription!.contains("○"))
    }

    // MARK: Storage

    func testEncodeDecodeRoundTrip() {
        let pairs = [Pair(open: "◇", done: "◆"), Pair(open: "🟡", done: "🟢")]
        XCTAssertEqual(CustomBullets.decode(CustomBullets.encode(pairs)), pairs)
        XCTAssertEqual(CustomBullets.decode(CustomBullets.encode([])), [])
    }

    func testDamagedOrHandEditedSettingsNeverPutABadBulletInPlay() {
        XCTAssertEqual(CustomBullets.decode(""), [])
        XCTAssertEqual(CustomBullets.decode("not json"), [])
        XCTAssertEqual(CustomBullets.decode("{\"open\":\"◇\"}"), [], "wrong shape")
        let mixed = #"[{"open":"◇","done":"◆"},{"open":"a","done":"b"},{"open":"○","done":"♥"},{"open":"♡","done":"♥"}]"#
        XCTAssertEqual(CustomBullets.decode(mixed), [Pair(open: "◇", done: "◆"), Pair(open: "♡", done: "♥")],
                       "the letters and the built-in clash are dropped, the rest kept in order")
        let twelve = "[" + (0..<12).map { #"{"open":"\#(String(UnicodeScalar(0x1F300 + $0 * 2)!))","done":"\#(String(UnicodeScalar(0x1F301 + $0 * 2)!))"}"# }.joined(separator: ",") + "]"
        XCTAssertEqual(CustomBullets.decode(twelve).count, SmartBullets.maxCustom, "capped at eight")
    }

    // MARK: Suggestions

    func testSuggestionsFitAndRunOut() {
        var list: [Pair] = []
        while let next = CustomBullets.nextSuggestion(after: list) {
            XCTAssertNil(CustomBullets.validate(list + [next]))
            list.append(next)
        }
        XCTAssertEqual(list.count, SmartBullets.maxCustom, "eight suggestions in a row, then none")
        XCTAssertNil(CustomBullets.nextSuggestion(after: list))
        XCTAssertEqual(CustomBullets.nextSuggestion(after: []), Pair(open: "◇", done: "◆"))
    }

    func testASuggestionSkipsWhatIsAlreadyTaken() {
        let taken = [Pair(open: "◇", done: "◆")]
        XCTAssertEqual(CustomBullets.nextSuggestion(after: taken), Pair(open: "△", done: "▲"))
    }

    // MARK: A custom bullet works everywhere a built-in one does

    func testPairsListBuiltInsFirstThenYours() {
        SmartBullets.custom = [Pair(open: "◇", done: "◆")]
        XCTAssertEqual(SmartBullets.pairs.count, 9)
        XCTAssertEqual(Array(SmartBullets.pairs.prefix(8)), SmartBullets.builtIn, "built-in indexes never move")
        XCTAssertEqual(SmartBullets.pairs[8], Pair(open: "◇", done: "◆"))
        SmartBullets.custom = []
        XCTAssertEqual(SmartBullets.pairs.count, 8)
    }

    func testDetectionFollowsTheCustomList() throws {
        XCTAssertNil(SmartBullets.marker(in: "◇ idea"), "not a bullet yet")
        SmartBullets.custom = [Pair(open: "◇", done: "◆")]
        let open = try XCTUnwrap(SmartBullets.marker(in: "◇ idea"))
        XCTAssertEqual(open.pair, 8)
        XCTAssertFalse(open.isDone)
        XCTAssertTrue(try XCTUnwrap(SmartBullets.marker(in: "  ◆ done")).isDone)
        SmartBullets.custom = []
        XCTAssertNil(SmartBullets.marker(in: "◇ idea"), "and not a bullet again once removed")
    }

    func testFlippingReturnBackspaceAndTabAllWork() {
        SmartBullets.custom = [Pair(open: "🟡", done: "🟢")]
        let text = "🟡 ship it"
        XCTAssertEqual(apply(SmartBullets.toggle(in: text, at: 3), to: text), "🟢 ship it")
        XCTAssertEqual(apply(SmartBullets.toggle(in: "🟢 ship it", at: 3), to: "🟢 ship it"), "🟡 ship it")
        XCTAssertEqual(apply(ListEditing.returnKey(in: "🟢 ship it", selection: NSRange(location: 10, length: 0)), to: "🟢 ship it"), "🟢 ship it\n🟡 ", "Return continues with the open form")
        XCTAssertEqual(apply(ListEditing.backspace(in: "🟡 ship it", selection: NSRange(location: 3, length: 0)), to: "🟡 ship it"), "ship it")
        XCTAssertEqual(apply(ListEditing.indent(in: text, selection: NSRange(location: 4, length: 0), outdent: false), to: text), "  🟡 ship it")
        XCTAssertEqual(apply(ListEditing.toggleChecklist(in: text, selection: NSRange(location: 4, length: 0)), to: text), "🟢 ship it", "⌘Return")
    }

    func testChoosingACustomBulletFromThePicker() {
        SmartBullets.custom = [Pair(open: "◇", done: "◆")]
        let edit = ListEditing.insertSmartBullet(8, in: "buy milk", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(apply(edit, to: "buy milk"), "◇ buy milk")
        XCTAssertNil(ListEditing.insertSmartBullet(9, in: "x", selection: NSRange(location: 0, length: 0)), "an index that is not there")
    }

    func testTheHighlighterAndPickerSeeCustomBullets() {
        SmartBullets.custom = [Pair(open: "◇", done: "◆")]
        XCTAssertEqual(MarkdownHighlighter.spans(in: "◆ finished").compactMap(\.marker).first?.kind, .smartDone)
        XCTAssertNotNil(MarkdownHighlighter.spans(in: "◆ finished").first { $0.strike }, "done items are struck through")
        let items = SymbolCatalog.groups[0].items.compactMap { item -> Int? in if case .smartBullet(let i) = item.kind { return i } else { return nil } }
        XCTAssertEqual(items, Array(0..<9), "the picker lists the custom one after the built-ins")
        XCTAssertEqual(SymbolCatalog.groups[0].items.last?.label, "◇◆")
        XCTAssertEqual(SymbolCatalog.groups(custom: []).first?.items.count, 9, "the markdown task plus the 8 built in, whatever the global holds")
    }

    func testChangingThePairsRebuildsTheMatcher() throws {
        SmartBullets.custom = [Pair(open: "◇", done: "◆")]
        XCTAssertNotNil(SmartBullets.marker(in: "◇ a"))
        SmartBullets.custom = [Pair(open: "♡", done: "♥")]
        XCTAssertNil(SmartBullets.marker(in: "◇ a"), "the old pair is gone")
        XCTAssertNotNil(SmartBullets.marker(in: "♡ a"))
    }

    func testMarkdownListsStayMarkdown() {
        SmartBullets.custom = [Pair(open: "◇", done: "◆")]
        XCTAssertEqual(MarkdownHighlighter.spans(in: "- item").compactMap(\.marker).first?.kind, .bullet)
        XCTAssertEqual(MarkdownHighlighter.spans(in: "+ item").compactMap(\.marker).first?.kind, .bullet)
    }
}

final class CustomBulletsFormTests: XCTestCase {
    private typealias Pair = SmartBullets.Pair
    private func evaluate(_ rows: [(String, String)]) -> CustomBullets.FormResult { CustomBullets.evaluate(rows.map { (open: $0.0, done: $0.1) }) }

    func testCompleteValidRowsAreStored() {
        let r = evaluate([("◇", "◆"), ("♡", "♥")])
        XCTAssertEqual(r.store, [Pair(open: "◇", done: "◆"), Pair(open: "♡", done: "♥")])
        XCTAssertNil(r.message)
    }

    func testNoRowsStoresAnEmptyList() {
        XCTAssertEqual(evaluate([]).store, [])
        XCTAssertNil(evaluate([]).message)
    }

    func testHalfTypedRowsAreSkippedWithAGentleNote() {
        let r = evaluate([("◇", "◆"), ("♡", "")])
        XCTAssertEqual(r.store, [Pair(open: "◇", done: "◆")], "the finished row is kept")
        XCTAssertEqual(r.message, "Fill in both sides to use a bullet.")
        XCTAssertEqual(evaluate([("", "")]).store, [])
    }

    func testABadGlyphIsReportedAtOnceAndNothingIsStored() {
        let r = evaluate([("◇", "◆"), ("a", "")])
        XCTAssertNil(r.store, "the stored bullets stay as they were until it is fixed")
        XCTAssertTrue(r.message!.contains("a"))
        XCTAssertNil(evaluate([("◇◆", "x")]).store)
    }

    func testClashesAreReported() {
        XCTAssertTrue(evaluate([("○", "◆")]).message!.contains("already used"))
        XCTAssertTrue(evaluate([("◇", "◆"), ("◆", "♥")]).message!.contains("already used"))
        XCTAssertTrue(evaluate([("◇", "◇")]).message!.contains("both"))
        XCTAssertNil(evaluate([("○", "◆")]).store)
    }

    func testTooManyRows() {
        let rows = (0..<9).map { (String(UnicodeScalar(0x1F300 + $0 * 2)!), String(UnicodeScalar(0x1F301 + $0 * 2)!)) }
        XCTAssertNil(evaluate(rows).store)
        XCTAssertEqual(evaluate(rows).message, "At most 8 of your own.")
    }
}
