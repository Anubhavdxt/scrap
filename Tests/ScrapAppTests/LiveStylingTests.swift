import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

/// The styling a real text view ends up with, after typing, deleting and moving the caret, equals a full restyle.
@MainActor
final class LiveStylingTests: XCTestCase {
    private final class Box { var text = "" }
    private func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }

    func testRandomEditingInATextViewGivesTheSameAttributesAsRestylingEverything() throws {
        for seed0 in [7, 21, 99] { try fuzz(seed0: UInt64(seed0)) }
    }

    private func fuzz(seed0: UInt64) throws {
        var seed = seed0
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(max(n, 1))) }
        let pieces = ["a", " ", "\n", "```", "```swift\n", "x\n", "- ", "# ", "**b**", "ोई "]
        let box = Box()
        box.text = "intro line\n\n```\nfootprint $(pgrep ScrapApp)\nsecond\n```\nafter\n"
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: Themes.all[0], fontSize: 14, fontFamily: "", wrap: true).frame(width: 560, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let tv = try XCTUnwrap(find(view))
        window.makeFirstResponder(tv)
        let theme = Themes.all[0]
        let style = MarkdownStyle(theme: theme, baseFont: EditorFont.font(size: 14, family: ""), codeFont: EditorFont.codeFont(size: 14, family: ""),
                                  colorHighlights: true, markers: .hide)

        for step in 0..<150 {
            let length = (tv.string as NSString).length
            let op = next(10)
            tv.setSelectedRange(NSRange(location: next(length + 1), length: 0))
            if op >= 5 { tv.insertText(pieces[next(pieces.count)], replacementRange: tv.selectedRange()) }
            else if op == 4 { tv.deleteBackward(nil) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))

            let text = tv.string
            let fresh = NSTextStorage(string: text)
            let caret = (text as NSString).paragraphRange(for: NSRange(location: min(tv.selectedRange().location, (text as NSString).length), length: 0))
            MarkdownStyler.apply(MarkdownHighlighter.spans(in: text), to: fresh, range: NSRange(location: 0, length: fresh.length), reveal: caret, style: style)
            let live = try XCTUnwrap(tv.textStorage)
            // The same text laid out from scratch must put every line where the live view has it.
            let freshLayout = ScrapLayoutManager()
            fresh.addLayoutManager(freshLayout)
            let freshContainer = NSTextContainer(size: NSSize(width: tv.textContainer!.size.width, height: CGFloat.greatestFiniteMagnitude))
            freshContainer.lineFragmentPadding = tv.textContainer!.lineFragmentPadding
            freshLayout.addTextContainer(freshContainer)
            freshLayout.ensureLayout(for: freshContainer)
            tv.layoutManager!.ensureLayout(for: tv.textContainer!)
            func fragments(_ layout: NSLayoutManager, _ container: NSTextContainer) -> [String] {
                var out: [String] = []
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { rect, used, _, range, _ in
                    out.append("\(range.location)+\(range.length) y=\(Int(rect.minY)) h=\(Int(rect.height)) x=\(Int(used.minX))")
                }
                return out
            }
            let liveFragments = fragments(tv.layoutManager!, tv.textContainer!), freshFragments = fragments(freshLayout, freshContainer)
            if liveFragments != freshFragments {
                return XCTFail("step \(step) op \(op): layout differs in \(text.debugDescription)\n live:  \(liveFragments)\n fresh: \(freshFragments)")
            }
            var i = 0
            while i < live.length {
                var ra = NSRange(), rb = NSRange()
                let x = live.attributes(at: i, effectiveRange: &ra) as NSDictionary
                let y = fresh.attributes(at: i, effectiveRange: &rb) as NSDictionary
                if !x.isEqual(y) {
                    let differing = x.allKeys.compactMap { key -> String? in
                        let a = x[key], b = y[key]
                        return (a as AnyObject).isEqual(b) ? nil : "\(key)"
                    }
                    return XCTFail("step \(step) op \(op): attributes differ at \(i) in \(text.debugDescription): \(differing)")
                }
                i = max(NSMaxRange(ra), i + 1)
            }
        }
    }
}
