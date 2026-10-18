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
        XCTAssertTrue(EditorFont.isBold(h1))
        XCTAssertNotNil(kern(tv, at: 0), "the # is hidden")
    }

    func testBoldItalicAndLinkStyles() {
        let (_, tv, _) = makeEditor("**b** *i* [t](https://x.y) end")
        tv.setSelectedRange(NSRange(location: 29, length: 0))
        XCTAssertTrue(EditorFont.isBold(font(tv, at: 2)!))
        XCTAssertTrue(EditorFont.isItalic(font(tv, at: 7)!))
        let linkAt = 11
        XCTAssertEqual(tv.textStorage?.attribute(.scrapURL, at: linkAt, effectiveRange: nil) as? String, "https://x.y")
        XCTAssertNotNil(tv.textStorage?.attribute(.underlineStyle, at: linkAt, effectiveRange: nil))
        XCTAssertFalse(EditorFont.isItalic(font(tv, at: linkAt)!), "links are never italic")
    }

    func testColourHighlightsOffUsesOneTextColour() {
        let source = "**bold** and *it* plain"
        let (_, on, _) = makeEditor(source, colors: true)
        let (_, off, _) = makeEditor(source, colors: false)
        on.setSelectedRange(NSRange(location: 22, length: 0)); off.setSelectedRange(NSRange(location: 22, length: 0))
        XCTAssertNotEqual(color(on, at: 3), color(on, at: 20), "bold has its own colour when highlights are on")
        XCTAssertEqual(color(off, at: 3), color(off, at: 20), "and the same colour as plain text when they are off")
        XCTAssertTrue(EditorFont.isBold(font(off, at: 3)!), "the weight stays")
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
        let style = MarkdownStyle(theme: theme, baseFont: EditorFont.font(size: 14, family: ""), codeFont: EditorFont.codeFont(size: 14, family: ""), colorHighlights: true, markers: .hide)
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
        guard let font = tv.textStorage?.attribute(.font, at: i, effectiveRange: nil) as? NSFont else { return [] }
        var t = font.fontDescriptor.symbolicTraits
        if EditorFont.isBold(font) { t.insert(.bold) }   // the heavy weight counts as bold
        return t
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
        XCTAssertTrue(font.map(EditorFont.isBold) == true)
    }
}

@MainActor
final class StatusIconTests: XCTestCase {
    private func template() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 2), xRadius: 2, yRadius: 2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func pixel(_ image: NSImage, x: Int, y: Int) -> NSColor {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    }

    func testTintedIconIsColouredNotATemplate() {
        let tinted = StatusIcon.tinted(template(), with: NSColor(deviceRed: 1, green: 0.2, blue: 0.1, alpha: 1))
        XCTAssertFalse(tinted.isTemplate, "a template would be recoloured by macOS")
        XCTAssertEqual(tinted.size, NSSize(width: 18, height: 18))
        let inside = pixel(tinted, x: 18, y: 18)
        XCTAssertEqual(inside.alphaComponent, 1, accuracy: 0.05)
        XCTAssertEqual(inside.redComponent, 1, accuracy: 0.05)
        XCTAssertEqual(inside.greenComponent, 0.2, accuracy: 0.05)
        let outside = pixel(tinted, x: 1, y: 1)
        XCTAssertEqual(outside.alphaComponent, 0, accuracy: 0.05, "transparent parts stay transparent")
    }

    func testEveryPadHasADistinctColourAndTheyRepeat() {
        let colors = (1...7).map { PadColors.nsColor(for: $0) }
        XCTAssertEqual(Set(colors.map(\.description)).count, 7)
        XCTAssertEqual(PadColors.nsColor(for: 8), PadColors.nsColor(for: 1))
        XCTAssertEqual(PadColors.nsColor(for: 0), PadColors.nsColor(for: 1), "never crashes on an odd number")
    }
}

/// The whole popover as the user sees it (opt-in, like the other snapshots).
@MainActor
final class PopoverSnapshotTests: XCTestCase {
    func testRenderPopover() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-snap-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        try "# Ideas\n- [ ] buy **milk**\n- [x] call back\nsee https://example.com".write(to: pads.appendingPathComponent("1.md"), atomically: true, encoding: .utf8)
        try "second pad".write(to: pads.appendingPathComponent("3.md"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        defer { UserDefaults.standard.removeObject(forKey: "sayHiDone") }

        let model = EditorModel()
        let size = WindowSize.current()
        let view = NSHostingView(rootView: ContentView(model: model).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("popover.png"))
    }
}

/// Proportional prose with monospaced code, and the raw (plain) view.
@MainActor
final class RenderedFontTests: XCTestCase {
    private final class Box { var text: String; var selection = NSRange(location: 0, length: 0); init(_ t: String) { text = t } }

    private func editor(_ text: String, family: String = "system", rendered: Bool = true, pad: Int = 3, box: Box? = nil) -> NSTextView {
        let box = box ?? Box(text)
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let selection = Binding(get: { box.selection }, set: { box.selection = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: theme, fontSize: 14, fontFamily: family, wrap: true, rendered: rendered,
                                                      selectionColor: PadColors.nsColor(for: pad), selection: selection).frame(width: 520, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
        let tv = find(view)!
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)) // caret on the last line
        _ = window
        return tv
    }

    private func font(_ tv: NSTextView, _ needle: String) -> NSFont? {
        let range = (tv.string as NSString).range(of: needle)
        return tv.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
    }

    func testTheFontChoices() {
        XCTAssertFalse(EditorFont.font(size: 14, family: "system").isFixedPitch, "proportional")
        XCTAssertTrue(EditorFont.font(size: 14, family: "").isFixedPitch)
        XCTAssertTrue(EditorFont.font(size: 14, family: "Menlo").isFixedPitch)
        for family in ["system", "", "Menlo", "Not A Font"] {
            XCTAssertTrue(EditorFont.codeFont(size: 14, family: family).isFixedPitch, "code is monospaced whatever the prose font (\(family))")
        }
        let mono = EditorFont.font(size: 14, family: "")
        XCTAssertEqual(EditorFont.cellWidth(mono), mono.maximumAdvancement.width, accuracy: 0.01)
        XCTAssertGreaterThan(EditorFont.cellWidth(.systemFont(ofSize: 14)), 5)
    }

    func testProseIsProportionalAndCodeIsMonospaced() {
        let tv = editor("# Title\nplain **bold** and `inline` text\n```\nblock line\n```\nlast")
        XCTAssertFalse(font(tv, "plain")!.isFixedPitch, "prose uses the proportional system font")
        XCTAssertFalse(font(tv, "Title")!.isFixedPitch, "headings too")
        XCTAssertFalse(font(tv, "bold")!.isFixedPitch)
        XCTAssertTrue(font(tv, "inline")!.isFixedPitch, "inline code stays monospaced")
        XCTAssertTrue(font(tv, "block line")!.isFixedPitch, "code blocks stay monospaced")
        XCTAssertTrue(EditorFont.isBold(font(tv, "bold")!), "and bold still works in the proportional font")
    }

    func testMonospacedChoiceKeepsEverythingMonospaced() {
        let tv = editor("plain text\n```\ncode\n```\nlast", family: "")
        XCTAssertTrue(font(tv, "plain")!.isFixedPitch)
        XCTAssertTrue(font(tv, "code")!.isFixedPitch)
    }

    func testHiddenMarkersAndIconsStayExactWithProportionalText() {
        let tv = editor("a **bold** b and ### x\n- [ ] task\n- plain\nlast line")
        let ns = tv.string as NSString
        let stars = ns.range(of: "**")
        let hidden = tv.textStorage!.attributedSubstring(from: stars)
        XCTAssertEqual(hidden.size().width, 0, accuracy: 0.6, "a hidden marker takes no room even in a proportional font")
        let marker = ns.range(of: "- [ ] ")
        let width = tv.textStorage!.attributedSubstring(from: marker).size().width
        XCTAssertEqual(width, (14 * 1.4).rounded(), accuracy: 0.6, "a task marker collapses to exactly the icon's width")
        let bullet = ns.range(of: "- plain")
        let bulletMarker = NSRange(location: bullet.location, length: 2)
        XCTAssertEqual(tv.textStorage!.attributedSubstring(from: bulletMarker).size().width, (14 * 1.4).rounded(), accuracy: 0.6)
    }

    func testRawModeIsTheSameColouredMarkdownWithEveryMarkVisible() {
        let source = "# Title\n**bold** and *it* and `code` and ~~gone~~\n- [ ] task\n- bullet\n> quote\n[link](https://x.y)\n```swift\nlet a = 1\n```\nend"
        let raw = editor(source, rendered: false)
        let rendered = editor(source, rendered: true)
        XCTAssertEqual(raw.string, source, "same text")
        let storage = raw.textStorage!
        let ns = source as NSString

        // Monospaced all through, nothing hidden, no drawn icons.
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, _, _ in
            XCTAssertTrue((attrs[.font] as? NSFont)?.isFixedPitch == true, "raw is monospaced")
            XCTAssertNil(attrs[.kern], "no marks are hidden")
            XCTAssertNil(attrs[.scrapMarker], "list markers stay text, not icons")
        }
        func color(_ tv: NSTextView, _ needle: String, offset: Int = 0) -> NSColor? {
            tv.textStorage?.attribute(.foregroundColor, at: ns.range(of: needle).location + offset, effectiveRange: nil) as? NSColor
        }
        // The marks wear their element's colour, so `**bold**` is one gold word and `# Title` one gold line.
        XCTAssertEqual(color(raw, "**bold**"), color(raw, "bold"), "the ** is coloured like the bold word")
        XCTAssertEqual(color(raw, "# Title"), color(raw, "Title"), "the # is coloured like the heading")
        XCTAssertNotEqual(color(raw, "bold"), color(raw, "end"), "and bold is coloured differently from plain text")
        XCTAssertGreaterThan(color(raw, "**bold**")?.alphaComponent ?? 0, 0.9, "marks aren't dimmed")

        // The elements are all still styled: weight, slant, strike, code chip, link, panel, quote bar.
        func traits(_ tv: NSTextView, _ needle: String) -> NSFontDescriptor.SymbolicTraits {
            (tv.textStorage?.attribute(.font, at: ns.range(of: needle).location, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits ?? []
        }
        XCTAssertTrue(traits(raw, "bold").contains(.bold))
        XCTAssertTrue(traits(raw, "*it*").contains(.italic))
        XCTAssertNotNil(storage.attribute(.strikethroughStyle, at: ns.range(of: "gone").location, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.backgroundColor, at: ns.range(of: "`code`").location + 1, effectiveRange: nil), "inline code keeps its chip")
        XCTAssertNotNil(storage.attribute(.underlineStyle, at: ns.range(of: "link").location, effectiveRange: nil))
        XCTAssertNotNil(storage.attribute(.scrapBlock, at: ns.range(of: "let a").location, effectiveRange: nil), "the code panel")
        XCTAssertNotNil(storage.attribute(.scrapQuote, at: ns.range(of: "quote").location, effectiveRange: nil))
        let headingFont = storage.attribute(.font, at: ns.range(of: "Title").location, effectiveRange: nil) as? NSFont
        let bodyFont = storage.attribute(.font, at: ns.range(of: "end").location, effectiveRange: nil) as? NSFont
        XCTAssertGreaterThan(headingFont?.pointSize ?? 0, bodyFont?.pointSize ?? 99, "headings are still larger")

        // Rendered, by contrast, hides those marks and draws the icons.
        rendered.setSelectedRange(NSRange(location: ns.length, length: 0))
        XCTAssertNotNil(rendered.textStorage?.attribute(.kern, at: ns.range(of: "**bold**").location, effectiveRange: nil), "rendered hides the **")
        XCTAssertNotNil(rendered.textStorage?.attribute(.scrapMarker, at: ns.range(of: "- [ ]").location, effectiveRange: nil), "rendered draws the task icon")
    }

    func testSwitchingBetweenRawAndRenderedChangesNothingInTheText() {
        let source = "# T\n**b** - [ ] x"
        XCTAssertEqual(editor(source, rendered: true).string, source)
        XCTAssertEqual(editor(source, rendered: false).string, source)
    }

    func testSelectionIsHighlightedInThePadColourAndPublished() {
        let box = Box("select some of this text")
        let tv = editor(box.text, pad: 3, box: box)
        let background = tv.selectedTextAttributes[.backgroundColor] as? NSColor
        let expected = PadColors.nsColor(for: 3).usingColorSpace(.deviceRGB)!
        let got = background?.usingColorSpace(.deviceRGB)
        XCTAssertEqual(got?.redComponent ?? -1, expected.redComponent, accuracy: 0.02)
        XCTAssertEqual(got?.greenComponent ?? -1, expected.greenComponent, accuracy: 0.02)
        XCTAssertEqual(got?.alphaComponent ?? -1, 0.35, accuracy: 0.02)

        tv.setSelectedRange(NSRange(location: 7, length: 4))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(box.selection, NSRange(location: 7, length: 4), "the footer is told what is selected")
    }
}

/// The footer while text is selected, as a picture (opt-in).
@MainActor
final class SelectionFooterSnapshotTests: XCTestCase {
    func testRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-snaps-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        let text = "# Salary discussion\nI'm open to **negotiations** as per market standards.\n- [ ] Send a follow-up e-mail after 48 hours\n- plain bullet with `code` inside\n\n```swift\nlet x = 1\n```\nSee https://example.com now."
        try text.write(to: pads.appendingPathComponent("3.md"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        UserDefaults.standard.set(3, forKey: "lastPad")
        defer { ["sayHiDone", "lastPad", "rendered"].forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        let model = EditorModel()
        let size = WindowSize.current()
        let view = NSHostingView(rootView: ContentView(model: model).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
        let tv = try XCTUnwrap(find(view))
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        func shot(_ name: String) throws {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        try shot("rendered.png")
        tv.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        try shot("selected.png")
        UserDefaults.standard.set(false, forKey: "rendered")
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        try shot("raw.png")
    }
}

/// Bold is one weight heavier than the system's regular "Bold", in every kind of font.
@MainActor
final class BoldWeightTests: XCTestCase {
    private let heavy = NSFont.Weight.heavy.rawValue

    func testProportionalSystemFont() {
        let f = EditorFont.styled(.systemFont(ofSize: 14), bold: true, italic: false)
        XCTAssertGreaterThanOrEqual(EditorFont.weight(of: f), heavy - 0.01)
        XCTAssertFalse(EditorFont.isItalic(f))
        XCTAssertFalse(f.isFixedPitch)
        let old = NSFont(descriptor: NSFont.systemFont(ofSize: 14).fontDescriptor.withSymbolicTraits(.bold), size: 14)!
        XCTAssertGreaterThan(EditorFont.weight(of: f), EditorFont.weight(of: old), "heavier than the old bold")
    }

    func testMonospacedSystemFontWasOnlySemiboldBefore() {
        let mono = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let f = EditorFont.styled(mono, bold: true, italic: false)
        XCTAssertGreaterThanOrEqual(EditorFont.weight(of: f), heavy - 0.01)
        XCTAssertTrue(f.isFixedPitch, "still monospaced")
        XCTAssertEqual(f.pointSize, 14)
        let old = NSFont(descriptor: mono.fontDescriptor.withSymbolicTraits(.bold), size: 14)!
        XCTAssertLessThan(EditorFont.weight(of: old), 0.35, "the old bold in a monospaced font was too light to read as bold")
    }

    func testBoldAndItalicTogetherInEveryFont() {
        for base in [NSFont.systemFont(ofSize: 14), .monospacedSystemFont(ofSize: 14, weight: .regular)] {
            let both = EditorFont.styled(base, bold: true, italic: true)
            XCTAssertTrue(EditorFont.isBold(both) && EditorFont.weight(of: both) >= heavy - 0.01, base.fontName)
            XCTAssertTrue(EditorFont.isItalic(both), base.fontName)
            XCTAssertEqual(both.isFixedPitch, base.isFixedPitch, "family kind is kept")
            // Adding italic to bold text, then bold to italic text, gives the same thing.
            let a = EditorFont.styled(EditorFont.styled(base, bold: true, italic: false), bold: false, italic: true)
            let b = EditorFont.styled(EditorFont.styled(base, bold: false, italic: true), bold: true, italic: false)
            for f in [a, b] { XCTAssertTrue(EditorFont.weight(of: f) >= heavy - 0.01 && EditorFont.isItalic(f), base.fontName) }
        }
    }

    func testInstalledFamiliesFallBackToTheirBold() {
        guard let menlo = NSFontManager.shared.font(withFamily: "Menlo", traits: [], weight: 5, size: 14) else { return }
        let f = EditorFont.styled(menlo, bold: true, italic: false)
        XCTAssertTrue(EditorFont.isBold(f), "Menlo only has Regular and Bold, so bold is its Bold")
        XCTAssertTrue(f.isFixedPitch)
    }

    func testNotBoldStaysAtItsWeightAndSizeChangesSurvive() {
        let regular = EditorFont.styled(.systemFont(ofSize: 14), bold: false, italic: true, size: 20)
        XCTAssertEqual(EditorFont.weight(of: regular), 0, accuracy: 0.01)
        XCTAssertEqual(regular.pointSize, 20)
        XCTAssertTrue(EditorFont.isItalic(regular))
        let bigBold = EditorFont.styled(.monospacedSystemFont(ofSize: 14, weight: .regular), bold: true, italic: false, size: 22)
        XCTAssertEqual(bigBold.pointSize, 22)
        XCTAssertGreaterThanOrEqual(EditorFont.weight(of: bigBold), heavy - 0.01)
    }

    func testBoldTextInTheEditorIsHeavyInBothRenderedFonts() {
        func weight(_ family: String, rendered: Bool, _ needle: String) -> CGFloat {
            let tv = HeavyEditor.make("# Head\n**strong** and plain\nlast", family: family, rendered: rendered)
            let r = (tv.string as NSString).range(of: needle)
            return EditorFont.weight(of: tv.textStorage!.attribute(.font, at: r.location, effectiveRange: nil) as! NSFont)
        }
        XCTAssertGreaterThanOrEqual(weight("system", rendered: true, "strong"), heavy - 0.01, "rendered, proportional")
        XCTAssertGreaterThanOrEqual(weight("", rendered: true, "strong"), heavy - 0.01, "rendered, monospaced")
        XCTAssertGreaterThanOrEqual(weight("system", rendered: true, "Head"), heavy - 0.01, "headings too")
        XCTAssertEqual(weight("system", rendered: true, "plain"), 0, accuracy: 0.01, "plain text is untouched")
    }
}

@MainActor
private enum HeavyEditor {
    static func make(_ text: String, family: String, rendered: Bool) -> NSTextView {
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let view = NSHostingView(rootView: EditorView(text: .constant(text), theme: theme, fontSize: 14, fontFamily: family, wrap: true, rendered: rendered)
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
}

/// Smart bullets and the symbol picker, in the real editor.
@MainActor
final class SmartBulletEditorTests: XCTestCase {
    private final class Box { var text: String; init(_ t: String) { text = t } }

    private func editor(_ text: String, rendered: Bool = true, box: Box? = nil) -> (NSWindow, ScrapTextView, EditorView.Coordinator, Box) {
        let box = box ?? Box(text)
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: theme, fontSize: 14, fontFamily: "", wrap: true, rendered: rendered)
            .frame(width: 520, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func find(_ v: NSView) -> ScrapTextView? { (v as? ScrapTextView) ?? v.subviews.lazy.compactMap(find).first }
        let tv = find(view)!
        return (window, tv, tv.delegate as! EditorView.Coordinator, box)
    }

    private func glyphCentre(_ tv: ScrapTextView, at index: Int, length: Int = 1) -> NSPoint {
        let lm = tv.layoutManager!
        let r = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: index, length: length), actualCharacterRange: nil), in: tv.textContainer!)
        return NSPoint(x: r.midX + tv.textContainerOrigin.x, y: r.midY + tv.textContainerOrigin.y)
    }

    private func click(_ tv: ScrapTextView, _ window: NSWindow, at point: NSPoint) {
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: tv.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        tv.mouseDown(with: event)
    }

    // MARK: Look

    func testBulletsAreTintedClickableAndHangWrappedLines() {
        let (_, tv, _, _) = editor("○ open item that is long enough to wrap onto a second line when the window is narrow, yes\n● done item\nplain")
        tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
        let storage = tv.textStorage!
        XCTAssertNotNil(storage.attribute(.scrapSmartBullet, at: 0, effectiveRange: nil), "the bullet is a click target")
        XCTAssertNil(storage.attribute(.scrapSmartBullet, at: 1, effectiveRange: nil), "the space after it is not")
        XCTAssertNotNil(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        let paragraph = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThan(paragraph?.headIndent ?? 0, 8, "wrapped lines hang under the text")
        XCTAssertEqual(paragraph?.firstLineHeadIndent, 0)
        let done = (tv.string as NSString).range(of: "done item")
        XCTAssertNotNil(storage.attribute(.strikethroughStyle, at: done.location, effectiveRange: nil), "finished items are struck through")
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: 3, effectiveRange: nil), "open items are not")
        XCTAssertEqual(tv.string, "○ open item that is long enough to wrap onto a second line when the window is narrow, yes\n● done item\nplain", "the text is untouched")
    }

    func testRawModeShowsTheCharactersWithoutClickTargets() {
        let (_, tv, _, _) = editor("○ open\n● done\nplain", rendered: false)
        XCTAssertNil(tv.textStorage!.attribute(.scrapSmartBullet, at: 0, effectiveRange: nil))
    }

    // MARK: Clicking

    func testClickingABulletFlipsItAndLeavesTheCaret() {
        let (window, tv, _, box) = editor("○ first\n● second\n❌ third\nplain text")
        tv.setSelectedRange(NSRange(location: 28, length: 0))
        click(tv, window, at: glyphCentre(tv, at: 0))
        XCTAssertEqual(box.text, "● first\n● second\n❌ third\nplain text")
        click(tv, window, at: glyphCentre(tv, at: 8))
        XCTAssertEqual(box.text, "● first\n○ second\n❌ third\nplain text")
        let emoji = (tv.string as NSString).range(of: "❌")
        click(tv, window, at: glyphCentre(tv, at: emoji.location, length: emoji.length))
        XCTAssertEqual(box.text, "● first\n○ second\n✅ third\nplain text", "emoji pairs flip too")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 28, length: 0), "the caret doesn't jump")
    }

    func testOnlyTheBulletItselfIsATarget() {
        let (_, tv, _, box) = editor("○ item with text\nplain line")
        XCTAssertEqual(tv.smartBulletIndex(at: glyphCentre(tv, at: 0)), 0)
        XCTAssertNil(tv.smartBulletIndex(at: glyphCentre(tv, at: 8)), "the item's text")
        XCTAssertNil(tv.smartBulletIndex(at: glyphCentre(tv, at: 20)), "a plain line")
        XCTAssertNil(tv.smartBulletIndex(at: NSPoint(x: 400, y: 200)), "empty space")
        XCTAssertEqual(box.text, "○ item with text\nplain line")
    }

    // MARK: The picker's choices

    func testChoosingASmartBulletOnDifferentLines() {
        let (_, tv, coordinator, box) = editor("buy milk\n- dash item\n● old\n1. numbered")
        let ns = tv.string as NSString
        for (needle, expected) in [("buy", "▷ buy milk"), ("dash", "▷ dash item"), ("old", "▷ old"), ("numbered", "▷ numbered")] {
            tv.setSelectedRange(NSRange(location: ns.range(of: needle).location + 1, length: 0))
            coordinator.insert(.smartBullet(2), in: tv)
            XCTAssertTrue(box.text.contains(expected), "\(needle): \(box.text)")
        }
    }

    func testChoosingTextADividerAndATask() {
        let (_, tv, coordinator, box) = editor("alpha beta\nsecond line")
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        coordinator.insert(.text("→"), in: tv)
        XCTAssertEqual(box.text, "alpha→ beta\nsecond line")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 6, length: 0), "the caret moves past it")

        tv.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.insert(.divider("────"), in: tv)
        XCTAssertEqual(box.text, "alpha→ beta\n────\nsecond line")

        tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
        coordinator.insert(.markdownTask, in: tv)
        XCTAssertTrue(box.text.hasSuffix("- [ ] second line"))
        coordinator.insert(.markdownTask, in: tv)
        XCTAssertTrue(box.text.hasSuffix("- [ ] second line"), "choosing task again on a task changes nothing")
    }

    func testEveryItemInTheCatalogCanBeInserted() {
        let (_, tv, coordinator, box) = editor("x")
        for group in SymbolCatalog.groups {
            for item in group.items {
                box.text = "line"
                tv.string = "line"
                tv.setSelectedRange(NSRange(location: 4, length: 0))
                let before = tv.string
                coordinator.insert(item.kind, in: tv)
                XCTAssertNotEqual(tv.string, before, "\(group.name): \(item.label) did something")
            }
        }
    }

    func testChoosingAnItemInsertsAndClosesThePicker() {
        let item = SymbolCatalog.groups[2].items[0]   // a bullet character
        var inserted: SymbolItem.Kind?
        var closed = false
        let a = NotificationCenter.default.addObserver(forName: .insertSymbol, object: nil, queue: nil) { note in inserted = (note.object as? SymbolRequest)?.kind }
        let b = NotificationCenter.default.addObserver(forName: .closeSymbols, object: nil, queue: nil) { _ in closed = true }
        defer { NotificationCenter.default.removeObserver(a); NotificationCenter.default.removeObserver(b) }
        SymbolPicker.send(item)
        XCTAssertEqual(inserted, item.kind)
        XCTAssertTrue(closed)
    }

    func testInsertionWorksWhileTheEditorIsNotTheKeyWindow() {
        // The picker is a window of its own, so when something is chosen the editor's window is not key.
        let (window, tv, _, box) = editor("alpha beta")
        XCTAssertFalse(window.isKeyWindow)
        tv.setSelectedRange(NSRange(location: 5, length: 0))
        SymbolRequest(.text("→")).post()
        XCTAssertEqual(box.text, "alpha→ beta")
        SymbolRequest(.smartBullet(0)).post()
        XCTAssertEqual(box.text, "○ alpha→ beta")
    }

    func testThePickerAnchorsToTheStarButtonInTheFooter() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-anchor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        defer { UserDefaults.standard.removeObject(forKey: "sayHiDone") }
        let size = WindowSize.current()
        let view = NSHostingView(rootView: ContentView(model: EditorModel()).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let anchor = try XCTUnwrap(SymbolAnchor.view, "the footer's * button registers itself")
        XCTAssertTrue(anchor.window === window)
        let inWindow = anchor.convert(anchor.bounds, to: nil)
        XCTAssertLessThan(inWindow.midY, window.contentLayoutRect.height * 0.15, "it sits in the footer, at the bottom of the window")
        XCTAssertGreaterThan(inWindow.midX, window.contentLayoutRect.width * 0.6, "towards the right, with the other footer buttons")
        XCTAssertFalse(anchor.isFlipped, "so .minY puts the picker below it")
    }

    // MARK: Raw mode and bold (follow-up to the heavier bold)

    func testBoldIsHeavyInRawModeToo() {
        let (_, tv, _, _) = editor("**strong** and plain\nlast", rendered: false)
        tv.setSelectedRange(NSRange(location: tv.string.utf16.count, length: 0))
        let r = (tv.string as NSString).range(of: "strong")
        let font = tv.textStorage!.attribute(.font, at: r.location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(font.isFixedPitch, "raw is monospaced")
        XCTAssertGreaterThanOrEqual(EditorFont.weight(of: font), NSFont.Weight.heavy.rawValue - 0.01)
    }
}

/// The picker as a picture (opt-in).
@MainActor
final class PickerSnapshotTests: XCTestCase {
    func testRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-pick-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        try "# Weekend\n○ call the dentist\n● book the flights\n✅ pay rent\n❌ fix the bike\n☆ ideas\n– dash item\n➕ plus item\n−  minus item\n✓ checked\nSee https://example.com".write(to: pads.appendingPathComponent("1.md"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        defer { UserDefaults.standard.removeObject(forKey: "sayHiDone") }
        let model = EditorModel()
        let size = WindowSize.current()
        let view = NSHostingView(rootView: ContentView(model: model).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        func shot(_ name: String) throws {
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            view.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        try shot("bullets.png")
        // The picker's own content (it opens as a popover below the footer, not over the note).
        let picker = NSHostingView(rootView: SymbolPicker().background(Color(nsColor: .windowBackgroundColor)))
        picker.frame = NSRect(origin: .zero, size: SymbolPicker.size)
        let pickerWindow = NSWindow(contentRect: picker.frame, styleMask: [.titled], backing: .buffered, defer: false)
        pickerWindow.contentView = picker
        picker.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let rep = try XCTUnwrap(picker.bitmapImageRepForCachingDisplay(in: picker.bounds))
        picker.cacheDisplay(in: picker.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("picker.png"))
    }
}

/// The picker as a real popover: where does it land?
@MainActor
final class SymbolPopoverPlacementTests: XCTestCase {
    func testThePickerOpensBelowTheEditorAndNotOverIt() throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.main?.visibleFrame, screen.height > 700 else { throw XCTSkip("needs a display with room below a window") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-place-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        defer { UserDefaults.standard.removeObject(forKey: "sayHiDone") }

        let size = CGSize(width: 560, height: 300)
        let view = NSHostingView(rootView: ContentView(model: EditorModel()).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        // Near the top of the screen, so there is room underneath.
        window.setFrameTopLeftPoint(NSPoint(x: screen.minX + 200, y: screen.maxY - 40))
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let anchor = try XCTUnwrap(SymbolAnchor.view)

        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(rootView: SymbolPicker())
        popover.contentSize = SymbolPicker.size
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        defer { popover.performClose(nil); window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let picker = try XCTUnwrap(popover.contentViewController?.view.window).frame
        let editor = window.frame
        XCTAssertLessThanOrEqual(picker.maxY, editor.minY + 20, "the picker hangs below the window (its arrow may overlap the window's bottom edge): picker \(picker), window \(editor)")
        XCTAssertFalse(picker.intersects(editor.insetBy(dx: 0, dy: 20)), "so it doesn't cover the note: picker \(picker), window \(editor)")
        XCTAssertEqual(picker.midX, anchor.convert(anchor.bounds, to: nil).midX + editor.minX, accuracy: 40, "under the * button")
    }
}

/// The code block's look: no visible backticks, the language at the top right.
@MainActor
final class CodeBlockLookTests: XCTestCase {
    private func editor(_ text: String, markers: String = "hide", rendered: Bool = true, caretAtEnd: Bool = true) -> NSTextView {
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let view = NSHostingView(rootView: EditorView(text: .constant(text), theme: theme, fontSize: 14, fontFamily: "system", wrap: true,
                                                      markers: markers, rendered: rendered).frame(width: 520, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }
        let tv = find(view)!
        if caretAtEnd { tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0)) }
        _ = window
        return tv
    }

    private let source = "intro\n```js\nconst add = (a, b) => a + b;\n```\nafter"

    private func attrs(_ tv: NSTextView, _ needle: String, offset: Int = 0) -> [NSAttributedString.Key: Any] {
        tv.textStorage!.attributes(at: (tv.string as NSString).range(of: needle).location + offset, effectiveRange: nil)
    }

    func testTheFencesDisappearAndTheLanguageMovesToTheCorner() {
        let tv = editor(source)
        let open = attrs(tv, "```js"), close = attrs(tv, "```\nafter")
        for fence in [open, close] {
            XCTAssertEqual((fence[.foregroundColor] as? NSColor)?.alphaComponent, 0, "the backticks are invisible")
            XCTAssertLessThan((fence[.font] as? NSFont)?.pointSize ?? 99, 8, "and the line collapses to a thin strip")
            XCTAssertNotNil(fence[.scrapBlock], "but it is still part of the panel")
        }
        XCTAssertEqual(open[.scrapBlockLabel] as? String, "js", "the language is kept to draw in the corner")
        XCTAssertNil(close[.scrapBlockLabel], "only the opening fence has one")
        let code = attrs(tv, "const")
        XCTAssertGreaterThan((code[.foregroundColor] as? NSColor)?.alphaComponent ?? 0, 0.9, "the code itself is untouched")
        XCTAssertTrue((code[.font] as? NSFont)?.isFixedPitch == true)
        XCTAssertEqual(tv.string, source, "the text still has the backticks")
    }

    func testTheOpeningFenceComesBackWhenTheCaretIsOnIt() {
        let tv = editor(source, caretAtEnd: false)
        tv.setSelectedRange(NSRange(location: (source as NSString).range(of: "```js").location + 3, length: 0))
        let open = attrs(tv, "```js")
        XCTAssertGreaterThan((open[.foregroundColor] as? NSColor)?.alphaComponent ?? 0, 0.2, "visible, so the language can be edited")
        XCTAssertGreaterThan((open[.font] as? NSFont)?.pointSize ?? 0, 10)
        XCTAssertNil(open[.scrapBlockLabel], "and the corner label steps aside")
        let close = attrs(tv, "```\nafter")
        XCTAssertEqual((close[.foregroundColor] as? NSColor)?.alphaComponent, 0, "the other fence stays hidden")
        tv.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        XCTAssertEqual(attrs(tv, "```js")[.scrapBlockLabel] as? String, "js", "and it hides again when the caret leaves")
    }

    func testDimAndShowModesKeepTheFencesVisible() {
        for mode in ["dim", "show"] {
            let tv = editor(source, markers: mode)
            let open = attrs(tv, "```js")
            XCTAssertGreaterThan((open[.foregroundColor] as? NSColor)?.alphaComponent ?? 0, 0.2, mode)
            XCTAssertGreaterThan((open[.font] as? NSFont)?.pointSize ?? 0, 10, mode)
            XCTAssertNil(open[.scrapBlockLabel], "\(mode): the language is already visible on the fence")
        }
    }

    func testRawModeShowsTheFences() {
        let tv = editor(source, rendered: false)
        let open = attrs(tv, "```js")
        XCTAssertGreaterThan((open[.foregroundColor] as? NSColor)?.alphaComponent ?? 0, 0.2)
        XCTAssertGreaterThan((open[.font] as? NSFont)?.pointSize ?? 0, 10)
        XCTAssertNil(open[.scrapBlockLabel])
    }

    func testABlockWithNoLanguageHasNoLabel() {
        let tv = editor("a\n```\nplain code\n```\nb")
        XCTAssertNil(attrs(tv, "```\nplain")[.scrapBlockLabel])
        XCTAssertEqual((attrs(tv, "```\nplain")[.foregroundColor] as? NSColor)?.alphaComponent, 0, "still hidden")
    }
}

/// Custom smart bullets in the real editor.
@MainActor
final class CustomBulletEditorTests: XCTestCase {
    private final class Box { var text: String; init(_ t: String) { text = t } }

    override func tearDown() { SmartBullets.custom = [] }

    private func editor(_ text: String, bullets: [SmartBullets.Pair]) -> (NSWindow, ScrapTextView, Box) {
        let box = Box(text)
        let theme = Themes.all.first { $0.id == "cobalt2-dark" }!
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: theme, fontSize: 14, fontFamily: "", wrap: true,
                                                      customBullets: CustomBullets.encode(bullets)).frame(width: 520, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        func find(_ v: NSView) -> ScrapTextView? { (v as? ScrapTextView) ?? v.subviews.lazy.compactMap(find).first }
        let tv = find(view)!
        tv.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return (window, tv, box)
    }

    private func centre(_ tv: ScrapTextView, at index: Int, length: Int = 1) -> NSPoint {
        let lm = tv.layoutManager!
        let r = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: index, length: length), actualCharacterRange: nil), in: tv.textContainer!)
        return NSPoint(x: r.midX + tv.textContainerOrigin.x, y: r.midY + tv.textContainerOrigin.y)
    }

    private let pair = SmartBullets.Pair(open: "◇", done: "◆")

    func testACustomBulletIsStyledStruckAndClickable() {
        let (window, tv, box) = editor("◇ idea\n◆ shipped\nplain", bullets: [pair])
        let storage = tv.textStorage!
        XCTAssertNotNil(storage.attribute(.scrapSmartBullet, at: 0, effectiveRange: nil), "the custom glyph is a click target")
        let done = (tv.string as NSString).range(of: "shipped")
        XCTAssertNotNil(storage.attribute(.strikethroughStyle, at: done.location, effectiveRange: nil), "finished items are struck through")
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: tv.convert(centre(tv, at: 0), to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        tv.mouseDown(with: event)
        XCTAssertEqual(box.text, "◆ idea\n◆ shipped\nplain", "a click flips it")
    }

    func testWithoutTheCustomPairTheSameTextIsPlainText() {
        let (_, tv, _) = editor("◇ idea\n◆ shipped", bullets: [])
        XCTAssertNil(tv.textStorage!.attribute(.scrapSmartBullet, at: 0, effectiveRange: nil), "an unknown symbol is just text")
        XCTAssertNil(tv.textStorage!.attribute(.strikethroughStyle, at: 8, effectiveRange: nil))
    }

    func testBuiltInBulletsKeepWorkingAlongsideCustomOnes() {
        let (_, tv, _) = editor("○ built in\n◇ custom", bullets: [pair])
        XCTAssertNotNil(tv.textStorage!.attribute(.scrapSmartBullet, at: 0, effectiveRange: nil))
        let custom = (tv.string as NSString).range(of: "◇")
        XCTAssertNotNil(tv.textStorage!.attribute(.scrapSmartBullet, at: custom.location, effectiveRange: nil))
    }

    func testChoosingTheCustomBulletFromThePickerAndItsListing() {
        let (_, tv, box) = editor("buy milk", bullets: [pair])
        let coordinator = tv.delegate as! EditorView.Coordinator
        tv.setSelectedRange(NSRange(location: 2, length: 0))
        coordinator.insert(.smartBullet(8), in: tv)
        XCTAssertEqual(box.text, "◇ buy milk")
        let labels = SymbolCatalog.groups(custom: [pair])[0].items.map(\.label)
        XCTAssertEqual(labels.last, "◇◆")
    }
}

/// Settings > Appearance with a couple of custom bullets, as a picture (opt-in).
@MainActor
final class SettingsAppearanceSnapshotTests: XCTestCase {
    func testRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-setsnap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set("Appearance", forKey: "settingsTab")
        let samples: [SmartBullets.Pair] = [SmartBullets.Pair(open: "◇", done: "◆"), SmartBullets.Pair(open: "🟡", done: "🟢")]
        UserDefaults.standard.set(CustomBullets.encode(samples), forKey: "customBullets")
        defer { ["settingsTab", "customBullets"].forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        // The bullets editor on its own (in the real pane it sits below the theme swatches and the text options).
        let size = CGSize(width: SettingsView.size.width - 40, height: 250)
        let full = CGSize(width: size.width + 40, height: size.height)
        let background = Color(red: 0.1, green: 0.2, blue: 0.29)
        let content = CustomBulletsEditor()
            .padding(20)
            .frame(width: full.width, height: full.height, alignment: .topLeading)
            .background(background)
            .foregroundStyle(Color.white)
        let view = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: full), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: .darkAqua)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-bullets.png"))
    }
}
