import AppKit
import SwiftUI
import XCTest
@testable import ScrapApp
import ScrapCore

/// Renders the editor to a PNG so the look can be checked by eye. Runs only when SCRAP_SNAPSHOT_DIR is set:
///   SCRAP_SNAPSHOT_DIR=/tmp/shots swift test --filter SnapshotTests
@MainActor
final class SnapshotTests: XCTestCase {
    private let sample = """
    # Groceries & plans

    - [ ] buy milk and some eggs from the market on the way home, then call back about the thing that was agreed
    - [x] book the dentist
    - [ ] nested items too
      - [ ] one level down
      - [x] and done down here
    - plain bullet
    - another bullet with a [link](https://example.com/docs) and https://example.com/raw.
    1. first
    2. second

    > a quote with www.example.com

    **bold** and *italic* and ~~gone~~ and `code`
    """

    private func render(_ text: String, themeID: String, size: CGSize = CGSize(width: 520, height: 420)) -> NSBitmapImageRep? {
        let theme = Themes.all.first { $0.id == themeID }!
        let model = text
        let view = NSHostingView(rootView: EditorView(text: .constant(model), theme: theme, fontSize: 14, fontFamily: "", wrap: true)
            .frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    func testRenderSamples() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for id in ["cobalt2-dark", "dracula-light"] {
            let rep = try XCTUnwrap(render(sample, themeID: id))
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(id).png"))
        }
    }
}

/// Real mouse events against the editor: clicking task icons toggles them, other clicks don't.
@MainActor
final class EditorClickTests: XCTestCase {
    private final class Box { var text: String; init(_ t: String) { text = t } }

    private func makeEditor(_ text: String, box: Box) -> (NSWindow, ScrapTextView) {
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: theme, fontSize: 14, fontFamily: "", wrap: true)
            .frame(width: 520, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        func find(_ v: NSView) -> ScrapTextView? {
            if let tv = v as? ScrapTextView { return tv }
            for s in v.subviews { if let f = find(s) { return f } }
            return nil
        }
        return (window, find(view)!)
    }

    private func click(_ tv: ScrapTextView, window: NSWindow, at point: NSPoint, modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: tv.convert(point, to: nil), modifierFlags: modifiers, timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        tv.mouseDown(with: event)
    }

    private func iconCenter(_ tv: ScrapTextView, markerAt index: Int) -> NSPoint {
        let rect = (tv.layoutManager as! ScrapLayoutManager).iconRect(forMarkerAt: index, origin: tv.textContainerOrigin)!
        return NSPoint(x: rect.midX, y: rect.midY)
    }

    func testClickingATaskIconTogglesItAndLeavesTheCaretAlone() {
        let box = Box("- [ ] first\n- [x] second\n- plain\ntext")
        // The editor starts from the binding; put the text in the view the way the app does.
        let (window, tv) = makeEditor(box.text, box: box)
        XCTAssertEqual(tv.string, box.text)
        tv.setSelectedRange(NSRange(location: 31, length: 0))

        click(tv, window: window, at: iconCenter(tv, markerAt: 0))
        XCTAssertEqual(box.text, "- [x] first\n- [x] second\n- plain\ntext")
        click(tv, window: window, at: iconCenter(tv, markerAt: 12))
        XCTAssertEqual(box.text, "- [x] first\n- [ ] second\n- plain\ntext")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 31, length: 0), "the caret doesn't jump to the clicked line")
    }

    func testOnlyTaskIconsAreHitTargets() {
        let box = Box("- [ ] first\n- plain bullet\nsome text")
        let (_, tv) = makeEditor(box.text, box: box)
        // (A click that misses falls through to NSTextView's own mouse tracking, which blocks until mouse-up, so test the hit
        // detection directly.)
        XCTAssertEqual(tv.taskMarkerIndex(at: iconCenter(tv, markerAt: 0)), 0)
        XCTAssertNil(tv.taskMarkerIndex(at: iconCenter(tv, markerAt: 12)), "a bullet dot is not a button")
        XCTAssertNil(tv.taskMarkerIndex(at: NSPoint(x: 300, y: 200)), "empty space")
        XCTAssertNil(tv.taskMarkerIndex(at: NSPoint(x: tv.textContainerOrigin.x + 80, y: iconCenter(tv, markerAt: 0).y)), "the task's text")
        XCTAssertNil(tv.taskMarkerIndex(at: NSPoint(x: tv.textContainerOrigin.x + 80, y: iconCenter(tv, markerAt: 12).y)))
        XCTAssertEqual(box.text, "- [ ] first\n- plain bullet\nsome text")
    }

    func testLinksAreFoundUnderThePointer() {
        let box = Box("see https://example.com/a and [docs](www.example.org/x)")
        let (_, tv) = makeEditor(box.text, box: box)
        let lm = tv.layoutManager!, container = tv.textContainer!
        func center(ofCharacter i: Int) -> NSPoint {
            let r = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: i), length: 1), in: container)
            return NSPoint(x: r.midX + tv.textContainerOrigin.x, y: r.midY + tv.textContainerOrigin.y)
        }
        XCTAssertEqual(tv.linkURL(at: center(ofCharacter: 10))?.absoluteString, "https://example.com/a")
        XCTAssertEqual(tv.linkURL(at: center(ofCharacter: 32))?.absoluteString, "https://www.example.org/x", "the link text points at its URL")
        XCTAssertNil(tv.linkURL(at: center(ofCharacter: 1)), "plain text")
        XCTAssertNil(tv.linkURL(at: NSPoint(x: 400, y: 250)), "empty space")
    }
}
