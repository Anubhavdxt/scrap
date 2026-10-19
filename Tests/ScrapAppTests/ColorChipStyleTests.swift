import XCTest
import AppKit
import SwiftUI
@testable import ScrapApp
import ScrapCore

final class ColorChipStyleTests: XCTestCase {
    private func styled(_ text: String, chips: Bool) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let style = MarkdownStyle(theme: Themes.all[0], baseFont: .systemFont(ofSize: 14), codeFont: .monospacedSystemFont(ofSize: 14, weight: .regular),
                                  colorHighlights: true, markers: .hide, raw: false, colorChips: chips)
        MarkdownStyler.apply(MarkdownHighlighter.spans(in: text), to: storage, range: NSRange(location: 0, length: storage.length), reveal: NSRange(location: 0, length: 0), style: style)
        return storage
    }

    func testAChipIsTheColourWithReadableText() throws {
        let storage = styled("x\n\nbrand #0352BF end\n", chips: true)
        let index = (storage.string as NSString).range(of: "#0352BF").location
        let fill = try XCTUnwrap(storage.attribute(.backgroundColor, at: index, effectiveRange: nil) as? NSColor).usingColorSpace(.sRGB)
        XCTAssertEqual(fill?.redComponent ?? -1, 3.0 / 255, accuracy: 0.01)
        XCTAssertEqual(fill?.blueComponent ?? -1, 191.0 / 255, accuracy: 0.01)
        let text = try XCTUnwrap(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor).usingColorSpace(.sRGB)
        XCTAssertEqual(text?.redComponent ?? -1, 1, accuracy: 0.01, "white on a dark blue")
        XCTAssertNil(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil), "ordinary text has no chip")
    }

    func testALightColourGetsDarkText() throws {
        let storage = styled("#FFD60A", chips: true)
        let text = try XCTUnwrap(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor).usingColorSpace(.sRGB)
        XCTAssertLessThan(text?.redComponent ?? 1, 0.2)
    }

    func testChipsCanBeTurnedOff() {
        let storage = styled("#0352BF", chips: false)
        XCTAssertNil(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }

    func testAChipInsideInlineCodeWins() throws {
        let storage = styled("`#0352BF`", chips: true)
        let fill = try XCTUnwrap(storage.attribute(.backgroundColor, at: 1, effectiveRange: nil) as? NSColor).usingColorSpace(.sRGB)
        XCTAssertEqual(fill?.alphaComponent ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(fill?.blueComponent ?? -1, 191.0 / 255, accuracy: 0.01)
    }

    /// Writes a picture to look at (set SCRAP_SNAPSHOT_DIR).
    func testSnapshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR") }
        let text = "# Palette\n\nBrand blue #0352BF, accent #FFD60A and a see-through #FF000080.\n\n- primary `#0af`\n- issue #123 is not a colour\n- [link](https://x.com/#0352BF)\n\n```css\ncolor: #0352BF;\n```\n"
        for (name, theme) in [("dark", Themes.all[0]), ("light", Themes.all[1])] {
            let view = NSHostingView(rootView: EditorView(text: .constant(text), theme: theme, fontSize: 15, fontFamily: "", wrap: true).frame(width: 520, height: 320))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("chips-\(name).png"))
            window.close()
        }
    }
}
