import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

@MainActor
final class SearchTests: XCTestCase {
    private var home: URL!
    private var pads: URL!
    private var oldHome: String?

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-search-\(UUID().uuidString)")
        pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        for key in ["lastPad", "sayHiDone"] { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: "sayHiDone")
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in ["lastPad", "sayHiDone"] { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ n: Int, _ s: String) throws { try s.write(to: pads.appendingPathComponent("\(n).md"), atomically: true, encoding: .utf8) }

    func testPadTextsUsesUnsavedTextOfTheOpenPad() throws {
        try write(2, "second pad needle")
        let model = EditorModel()
        model.text = "typed but unsaved"
        let texts = model.padTexts()
        XCTAssertTrue(texts.contains { $0.number == model.pad.number && $0.text == "typed but unsaved" })
        XCTAssertTrue(texts.contains { $0.number == 2 && $0.text.contains("needle") })
    }

    func testOpeningAResultSwitchesPadAndClosesSearch() throws {
        try write(3, "alpha\nfind the needle here")
        let model = EditorModel()
        model.showSearch = true
        let hit = PadSearch.search("needle", in: model.padTexts()).hits[0]
        model.openResult(hit)
        XCTAssertEqual(model.pad.number, 3)
        XCTAssertFalse(model.showSearch)
        XCTAssertEqual((model.text as NSString).substring(with: hit.target), "needle")
    }

    func testRevealSelectsTheMatchInTheEditor() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: EditorView(text: .constant("one\ntwo needle\nthree"), theme: Themes.all[0], fontSize: 14, fontFamily: "", wrap: true))
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        window.layoutIfNeeded()
        NotificationCenter.default.post(name: .revealRange, object: nil, userInfo: ["location": 8, "length": 6])
        let done = expectation(description: "selected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2)
        let tv = findTextView(host)
        XCTAssertEqual(tv?.selectedRange(), NSRange(location: 8, length: 6))
    }

    private func findTextView(_ view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews { if let found = findTextView(sub) { return found } }
        return nil
    }

    func testSearchFieldTakesTheKeyboardWhenItAppears() {
        var text = ""
        let view = SearchField(text: Binding(get: { text }, set: { text = $0 }), placeholder: "", onMove: { _ in }, onSubmit: {}, onCancel: {})
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        let done = expectation(description: "focus")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
        wait(for: [done], timeout: 2)
        let editor = window.firstResponder as? NSTextView
        XCTAssertNotNil(editor, "the field editor is active, so typing goes to the field")
        XCTAssertTrue(editor?.delegate is FocusingField)
    }

    func testFieldHandlesListKeys() {
        var moves: [Int] = []
        var submitted = 0, cancelled = 0
        var text = ""
        let field = SearchField(text: Binding(get: { text }, set: { text = $0 }), placeholder: "",
                                onMove: { moves.append($0) }, onSubmit: { submitted += 1 }, onCancel: { cancelled += 1 })
        let c = field.makeCoordinator()
        let tf = NSTextField()
        let tv = NSTextView()
        _ = c.control(tf, textView: tv, doCommandBy: #selector(NSResponder.moveDown(_:)))
        _ = c.control(tf, textView: tv, doCommandBy: #selector(NSResponder.moveUp(_:)))
        XCTAssertTrue(c.control(tf, textView: tv, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(c.control(tf, textView: tv, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertFalse(c.control(tf, textView: tv, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
        XCTAssertEqual(moves, [1, -1])
        XCTAssertEqual(submitted, 1)
        XCTAssertEqual(cancelled, 1)
    }
}

@MainActor
final class SearchModelTests: XCTestCase {
    private let pads: [(number: Int, text: String)] = [(1, "https://x.com/watch?v=abc\nvisualize the data"), (2, "other")]

    func testOnlyTheLatestQueryIsShown() async {
        let m = SearchModel(pads: { self.pads })
        for ch in "visualize" { m.query.append(ch) }
        await m.settle()
        XCTAssertEqual(m.result.hits.map(\.pad), [1])
        XCTAssertEqual(m.result.hits[0].line, 2)
    }

    func testPadsAreReadOnceNotOnEveryKeystroke() async {
        var reads = 0
        let m = SearchModel(pads: { reads += 1; return self.pads })
        for ch in "visualize" { m.query.append(ch) }
        await m.settle()
        XCTAssertEqual(reads, 1)
        XCTAssertFalse(m.result.hits.isEmpty)
    }

    func testNoMatchesClearsEarlierResults() async {
        let m = SearchModel(pads: { self.pads })
        m.query = "v"
        await m.settle()
        XCTAssertFalse(m.result.hits.isEmpty)
        m.query = "vzzzzzzz"
        await m.settle()
        XCTAssertTrue(m.result.hits.isEmpty)
    }

    func testBlankQueryClearsAndSelectionStaysInRange() async {
        let m = SearchModel(pads: { self.pads })
        m.query = "e"
        await m.settle()
        m.move(5); XCTAssertEqual(m.selection, m.result.hits.count - 1)
        m.move(-9); XCTAssertEqual(m.selection, 0)
        m.query = "  "
        XCTAssertEqual(m.result, .empty)
    }
}
