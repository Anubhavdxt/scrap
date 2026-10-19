import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

/// What is on screen must match what a full redraw gives. A code fence collapses and grows as the caret leaves and
/// enters it, which moves the lines below; lines left drawn at their old position overlapped each other.
@MainActor
final class DisplayRefreshTests: XCTestCase {
    private final class Box { var text = "" }

    private func windowImage(_ window: NSWindow) -> CGImage? {
        CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])
    }

    private func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }

    private func pixels(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    func testTheScreenMatchesAFullRedrawAfterEditingAndMovingAroundACodeBlock() throws {
        let box = Box()
        box.text = "hello\n\n"
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: Themes.all[0], fontSize: 14, fontFamily: "", wrap: true).frame(width: 560, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: 100, y: 300))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let tv = try XCTUnwrap(find(view))
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: 7, length: 0))
        for ch in "```\nfootprint $(pgrep ScrapApp)\nsecond\n```" {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        }

        for caret in [14, 8, 30, 3, 8] {
            tv.setSelectedRange(NSRange(location: caret, length: 0))
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            guard let shown = windowImage(window) else { throw XCTSkip("window capture is not available here") }
            tv.setNeedsDisplay(tv.bounds)
            tv.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            guard let redrawn = windowImage(window) else { throw XCTSkip("window capture is not available here") }
            XCTAssertEqual(pixels(shown), pixels(redrawn), "caret at \(caret): the screen differs from a full redraw")
        }
    }

    func testAFreshlyOpenedPadIsDrawnAsAFullRedrawWouldDrawIt() throws {
        let box = Box()
        box.text = "hello\n\n```\nfootprint $(pgrep ScrapApp)\nsecond\n```\n"
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let view = NSHostingView(rootView: EditorView(text: binding, theme: Themes.all[0], fontSize: 14, fontFamily: "", wrap: true).frame(width: 560, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: 100, y: 300))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let tv = try XCTUnwrap(find(view))
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: 8, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let shown = windowImage(window) else { throw XCTSkip("window capture is not available here") }
        tv.setNeedsDisplay(tv.bounds)
        tv.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guard let redrawn = windowImage(window) else { throw XCTSkip("window capture is not available here") }
        XCTAssertEqual(pixels(shown), pixels(redrawn), "the screen differs from a full redraw")
    }
}
