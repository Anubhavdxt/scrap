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
    # Weekend plans

    ## Groceries

    - [ ] buy **oat milk** and some eggs from the market on the way home, then call back about the thing that was agreed
    - [x] book the dentist
    - plain bullet with a [link](https://example.com/docs) and https://example.com/raw.

    ### Notes
    1. first *step*
    2. second ~~skipped~~ step

    > a quote with `inline code` and www.example.com

    ```swift
    func greet(_ name: String) -> String {
        return "hi \\(name)" // done
    }
    ```

    **bold** and *italic* and ~~gone~~ and `code`

    ***both*** and **bold *nested italic* bold** and *italic **nested bold** italic* and _**mixed**_
    """

    private func render(_ text: String, themeID: String, size: CGSize = CGSize(width: 560, height: 640)) -> NSBitmapImageRep? {
        let theme = Themes.all.first { $0.id == themeID }!
        let model = text
        let view = NSHostingView(rootView: EditorView(text: .constant(model), theme: theme, fontSize: 14, fontFamily: "", wrap: true)
            .frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        // Park the caret at the end so the earlier lines show their rendered (marker-hidden) form.
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
        if let tv = find(view) {
            window.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
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


/// What the live Markdown styling does to the text storage, checked through the real editor view.
@MainActor
final class LiveStyleTests: XCTestCase {
    private final class Box { var text: String; init(_ t: String) { text = t } }

    private func makeEditor(_ text: String, markers: String = "hide", colors: Bool = true) -> (NSWindow, NSTextView, Box) {
        let box = Box(text)
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: theme, fontSize: 14, fontFamily: "", wrap: true,
                                                      colorHighlights: colors, markers: markers).frame(width: 520, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
        return (window, find(view)!, box)
    }

    private func kern(_ tv: NSTextView, at i: Int) -> CGFloat? { tv.textStorage?.attribute(.kern, at: i, effectiveRange: nil) as? CGFloat }
    private func color(_ tv: NSTextView, at i: Int) -> NSColor? { tv.textStorage?.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor }
    private func font(_ tv: NSTextView, at i: Int) -> NSFont? { tv.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont }

    func testMarkersAreHiddenAwayFromTheCaretAndShownOnItsLine() {
        let (_, tv, _) = makeEditor("a **bold** b\nsecond line")
        tv.setSelectedRange(NSRange(location: 20, length: 0)) // on the second line
        XCTAssertNotNil(kern(tv, at: 2), "the ** is collapsed to nothing")
        XCTAssertEqual(color(tv, at: 2)?.alphaComponent, 0, "and invisible")
        XCTAssertNil(kern(tv, at: 4), "the word itself is untouched")

        tv.setSelectedRange(NSRange(location: 5, length: 0)) // inside the bold word
        XCTAssertNil(kern(tv, at: 2), "markers come back on the line being edited")
        XCTAssertGreaterThan(color(tv, at: 2)?.alphaComponent ?? 0, 0.2)

        tv.setSelectedRange(NSRange(location: 20, length: 0))
        XCTAssertNotNil(kern(tv, at: 2), "and go away again when the caret leaves")
    }

    func testDimAndShowKeepTheMarkersVisible() {
        for mode in ["dim", "show"] {
            let (_, tv, _) = makeEditor("a **bold** b\nsecond", markers: mode)
            tv.setSelectedRange(NSRange(location: 15, length: 0))
            XCTAssertNil(kern(tv, at: 2), mode)
            let alpha = color(tv, at: 2)?.alphaComponent ?? 0
            XCTAssertGreaterThan(alpha, 0.2, mode)
            XCTAssertLessThan(alpha, 0.9, "\(mode): fainter than text")
        }
    }

    func testHeadingsAreLargerAndBold() {
        let (_, tv, _) = makeEditor("# Title\n## Sub\nplain")
        tv.setSelectedRange(NSRange(location: 18, length: 0))
        let h1 = font(tv, at: 3)!, h2 = font(tv, at: 11)!, body = font(tv, at: 17)!
        XCTAssertGreaterThan(h1.pointSize, h2.pointSize)
        XCTAssertGreaterThan(h2.pointSize, body.pointSize)
        XCTAssertTrue(h1.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertNotNil(kern(tv, at: 0), "the # is hidden")
    }

    func testBoldItalicAndLinkStyles() {
        let (_, tv, _) = makeEditor("**b** *i* [t](https://x.y) end")
        tv.setSelectedRange(NSRange(location: 29, length: 0))
        XCTAssertTrue(font(tv, at: 2)!.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(font(tv, at: 7)!.fontDescriptor.symbolicTraits.contains(.italic))
        let linkAt = 11
        XCTAssertEqual(tv.textStorage?.attribute(.scrapURL, at: linkAt, effectiveRange: nil) as? String, "https://x.y")
        XCTAssertNotNil(tv.textStorage?.attribute(.underlineStyle, at: linkAt, effectiveRange: nil))
        XCTAssertFalse(font(tv, at: linkAt)!.fontDescriptor.symbolicTraits.contains(.italic), "links are never italic")
    }

    func testColourHighlightsOffUsesOneTextColour() {
        let source = "**bold** and *it* plain"
        let (_, on, _) = makeEditor(source, colors: true)
        let (_, off, _) = makeEditor(source, colors: false)
        on.setSelectedRange(NSRange(location: 22, length: 0)); off.setSelectedRange(NSRange(location: 22, length: 0))
        XCTAssertNotEqual(color(on, at: 3), color(on, at: 20), "bold has its own colour when highlights are on")
        XCTAssertEqual(color(off, at: 3), color(off, at: 20), "and the same colour as plain text when they are off")
        XCTAssertTrue(font(off, at: 3)!.fontDescriptor.symbolicTraits.contains(.bold), "the weight stays")
    }

    func testCodeBlocksAndQuotesAreMarkedForDrawing() {
        let (_, tv, _) = makeEditor("```\ncode\n```\n> quote\nplain")
        tv.setSelectedRange(NSRange(location: 26, length: 0))
        let ns = tv.string as NSString
        XCTAssertNotNil(tv.textStorage?.attribute(.scrapBlock, at: ns.range(of: "code").location, effectiveRange: nil))
        XCTAssertNotNil(tv.textStorage?.attribute(.scrapQuote, at: ns.range(of: "quote").location, effectiveRange: nil))
        XCTAssertNil(tv.textStorage?.attribute(.scrapBlock, at: ns.range(of: "plain").location, effectiveRange: nil))
        XCTAssertNil(tv.textStorage?.attribute(.scrapQuote, at: ns.range(of: "plain").location, effectiveRange: nil))
    }

    func testTextIsNeverChangedByStyling() {
        let source = "# T\n**b** `c` [l](https://x.y)\n```swift\nlet a = 1\n```\n> q"
        let (_, tv, box) = makeEditor(source)
        tv.setSelectedRange(NSRange(location: 3, length: 0))
        tv.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        XCTAssertEqual(tv.string, source, "the file stays exactly the Markdown that was typed")
        XCTAssertEqual(box.text, source)
    }
}

@MainActor
final class StylingPerformanceTests: XCTestCase {
    func testStylingAHundredKilobytesOfMarkdownStaysFast() {
        let block = "# Heading\n- [ ] task with **bold** and *italic* and `code` and [link](https://example.com/x)\n> quote ~~gone~~\n```swift\nlet a = 1 // c\n```\n\n"
        let text = String(repeating: block, count: 700)   // about 100 KB
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let storage = NSTextStorage(string: text)
        let style = MarkdownStyle(theme: theme, baseFont: EditorFont.font(size: 14, family: ""), colorHighlights: true, markers: .hide)
        let t0 = Date()
        let spans = MarkdownHighlighter.spans(in: text)
        let t1 = Date()
        MarkdownStyler.apply(spans, to: storage, range: NSRange(location: 0, length: storage.length), reveal: NSRange(location: 0, length: 0), style: style)
        let t2 = Date()
        print("100 KB: analysis \(t1.timeIntervalSince(t0))s, styling \(t2.timeIntervalSince(t1))s, \(spans.count) spans")
        XCTAssertLessThan(t2.timeIntervalSince(t0), 3.0, "a full restyle of a large document must not be unusable (debug build)")
        // Moving the caret restyles two paragraphs only.
        let t3 = Date()
        MarkdownStyler.apply(spans, to: storage, range: (text as NSString).paragraphRange(for: NSRange(location: 5000, length: 0)), reveal: NSRange(location: 5000, length: 0), style: style)
        XCTAssertLessThan(Date().timeIntervalSince(t3), 0.5, "restyling one paragraph filters the spans but touches only that paragraph")
    }
}

/// Bold and italic together, as drawn by the real editor.
@MainActor
final class NestedEmphasisStyleTests: XCTestCase {
    private func editor(_ text: String) -> NSTextView {
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let view = NSHostingView(rootView: EditorView(text: .constant(text), theme: theme, fontSize: 14, fontFamily: "", wrap: true)
            .frame(width: 520, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
        let tv = find(view)!
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        _ = window
        return tv
    }

    private func traits(_ tv: NSTextView, at i: Int) -> NSFontDescriptor.SymbolicTraits {
        (tv.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits ?? []
    }

    func testTripleMarkersAreBoldAndItalic() {
        let tv = editor("***both*** and\nplain")
        let t = traits(tv, at: 4)
        XCTAssertTrue(t.contains(.bold) && t.contains(.italic), "the word is bold and italic at once")
        XCTAssertFalse(traits(tv, at: 16).contains(.bold))
    }

    func testItalicInsideBoldKeepsBothWeights() {
        let tv = editor("**bold *both* bold** x\nplain")
        XCTAssertTrue(traits(tv, at: 3).contains(.bold) && !traits(tv, at: 3).contains(.italic), "bold part is only bold")
        let inner = traits(tv, at: 9)
        XCTAssertTrue(inner.contains(.bold) && inner.contains(.italic), "the nested word is both")
        XCTAssertTrue(traits(tv, at: 16).contains(.bold) && !traits(tv, at: 16).contains(.italic), "and back to bold after it")
    }

    func testBoldInsideItalicKeepsBothWeights() {
        let tv = editor("*it **both** it* x\nplain")
        XCTAssertTrue(traits(tv, at: 2).contains(.italic) && !traits(tv, at: 2).contains(.bold))
        let inner = traits(tv, at: 8)
        XCTAssertTrue(inner.contains(.bold) && inner.contains(.italic))
    }

    func testMixedMarkerStylesStack() {
        for (source, index) in [("_**x**_ y\nz", 3), ("**_x_** y\nz", 3), ("*__x__* y\nz", 3)] {
            let t = traits(editor(source), at: index)
            XCTAssertTrue(t.contains(.bold) && t.contains(.italic), source)
        }
    }

    func testHeadingsStillGetTheirSizeWhenEmphasisIsInside() {
        let tv = editor("# Title\nplain")
        let font = tv.textStorage?.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(font?.pointSize ?? 0, 14)
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }
}
