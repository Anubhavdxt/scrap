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

    /// The share of pixels that differ between two captures (the caret blinks and a window losing focus recolours its
    /// title bar, so a few are allowed to; a line drawn in the wrong place moves hundreds).
    private func differing(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height else { return 1 }
        let ra = NSBitmapImageRep(cgImage: a), rb = NSBitmapImageRep(cgImage: b)
        guard let da = ra.bitmapData, let db = rb.bitmapData else { return 1 }
        let top = Int(Double(a.height) * 0.10)   // below the title bar
        let margin = 20                          // and inside the window's edge, whose corners change with focus
        let bytesPerPixel = ra.bitsPerPixel / 8
        var different = 0, total = 0
        for y in top..<(a.height - margin) {
            let row = y * ra.bytesPerRow
            for x in margin..<(a.width - margin) {
                let i = row + x * bytesPerPixel
                total += 1
                if abs(Int(da[i]) - Int(db[i])) + abs(Int(da[i + 1]) - Int(db[i + 1])) + abs(Int(da[i + 2]) - Int(db[i + 2])) > 24 { different += 1 }
            }
        }
        return Double(different) / Double(max(total, 1))
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
            let shown = try ScreenCapture.usable(windowImage(window))
            tv.setNeedsDisplay(tv.bounds)
            tv.displayIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let redrawn = try ScreenCapture.usable(windowImage(window))
            XCTAssertLessThan(differing(shown, redrawn), 0.012, "caret at \(caret): the screen differs from a full redraw")
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
        let shown = try ScreenCapture.usable(windowImage(window))
        tv.setNeedsDisplay(tv.bounds)
        tv.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let redrawn = try ScreenCapture.usable(windowImage(window))
        if let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] {
            for (name, image) in [("shown", shown), ("redrawn", redrawn)] {
                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("refresh-\(name).png"))
            }
        }
        XCTAssertLessThan(differing(shown, redrawn), 0.012, "the screen differs from a full redraw")
    }
}
