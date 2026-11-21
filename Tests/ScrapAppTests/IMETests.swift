import AppKit
import SwiftUI
import XCTest
@testable import ScrapApp
import ScrapCore

@MainActor
final class IMETests: XCTestCase {
    private var home: URL!
    private var oldHome: String?

    override func setUpWithError() throws {
        _ = NSApplication.shared
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-ime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in ["sayHiDone", "lastPad"] { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        (view as? NSTextView) ?? view.subviews.lazy.compactMap(findTextView).first
    }

    func testMarkedTextSurvivesSelectionUpdatesAndCommitsCleanly() throws {
        let model = EditorModel()
        let hosting = NSHostingView(rootView: ContentView(model: model).frame(width: 520, height: 320))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let tv = try XCTUnwrap(findTextView(in: hosting))
        window.makeFirstResponder(tv)

        // Simulate IME composition: "n", then "nihao", then commit "你好".
        tv.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(tv.hasMarkedText(), "marked text must survive selection update and SwiftUI updateNSView")
        XCTAssertEqual(tv.string, "n")
        XCTAssertEqual(tv.markedRange(), NSRange(location: 0, length: 1))

        tv.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(tv.hasMarkedText())
        XCTAssertEqual(tv.string, "nihao")
        XCTAssertEqual(tv.markedRange(), NSRange(location: 0, length: 5))

        // Commit Chinese text via IME.
        tv.insertText("你好", replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(tv.hasMarkedText())
        XCTAssertEqual(tv.string, "你好")
        XCTAssertEqual(model.text, "你好")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testMarkedTextInsideMarkdownHeadingAndCancelAndPadSwitch() throws {
        let model = EditorModel()
        model.text = "# "
        let hosting = NSHostingView(rootView: ContentView(model: model).frame(width: 520, height: 320))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let tv = try XCTUnwrap(findTextView(in: hosting))
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: 2, length: 0))

        tv.setMarkedText("bt", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(tv.hasMarkedText())
        XCTAssertEqual(tv.string, "# bt")
        XCTAssertEqual(model.text, "# ", "uncommitted marked text should not overwrite model.text")

        // Cancelling composition returns to original text.
        tv.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(tv.hasMarkedText())
        XCTAssertEqual(tv.string, "# ")

        // Composing then committing styles the heading and updates model.text.
        tv.setMarkedText("biaoti", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        tv.insertText("标题", replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(tv.string, "# 标题")
        XCTAssertEqual(model.text, "# 标题")

        // Switching pads while composing discards marked text and loads the new pad.
        tv.setMarkedText("ce", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(tv.hasMarkedText())
        model.open(number: 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(tv.hasMarkedText())
        XCTAssertEqual(tv.string, "")
    }

    func testSearchFieldPreservesMarkedTextAndDelegatesCommandsToIME() throws {
        var query = ""
        let binding = Binding(get: { query }, set: { query = $0 })
        var submitted = false
        let fieldView = SearchField(text: binding, placeholder: "Search", onMove: { _ in }, onSubmit: { submitted = true }, onCancel: {})
        let hosting = NSHostingView(rootView: fieldView.frame(width: 300, height: 30))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 30), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let tf = try XCTUnwrap(hosting.subviews.lazy.compactMap { $0 as? NSTextField ?? $0.subviews.compactMap { $0 as? NSTextField }.first }.first)
        window.makeFirstResponder(tf)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let editor = try XCTUnwrap(tf.currentEditor() as? NSTextView)
        editor.setMarkedText("sousuo", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertFalse(tf.delegate!.control!(tf, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertFalse(submitted)
    }
}
