import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

@MainActor
final class SearchBlurTests: XCTestCase {
    private func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }

    /// How abruptly the picture changes between neighbouring pixels, relative to its overall contrast: 1 is razor sharp.
    /// (Dimming lowers the contrast, so comparing this ratio isolates the blur.)
    private func sharpness(_ rep: NSBitmapImageRep, rows: ClosedRange<Int>) -> Double {
        var steepest = 0.0, lowest = Double.infinity, highest = -Double.infinity
        for y in rows {
            var last: Double?
            for x in 24..<(rep.pixelsWide - 24) {   // inside the window's edge, which is a sharp step to transparent
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let v = Double(c.redComponent + c.greenComponent + c.blueComponent) / 3
                lowest = min(lowest, v); highest = max(highest, v)
                if let last { steepest = max(steepest, abs(v - last)) }
                last = v
            }
        }
        return highest > lowest ? steepest / (highest - lowest) : 0
    }

    func testTheEditorBehindTheSearchPanelIsSlightlyBlurred() throws {
        try checkBlur { $0.showSearch = $1 }
    }

    func testTheEditorBehindSayHiIsBlurredTheSame() throws {
        try checkBlur { $0.showSayHi = $1 }
    }

    /// Opens a panel over the editor with `toggle(model, true)` and closes it with `toggle(model, false)`.
    private func checkBlur(_ toggle: (EditorModel, Bool) -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-blur-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; ["sayHiDone", "themeFamily", "appearance"].forEach { UserDefaults.standard.removeObject(forKey: $0) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        UserDefaults.standard.set("one", forKey: "themeFamily")
        UserDefaults.standard.set("light", forKey: "appearance")
        try String(repeating: "The quick brown fox jumps over the lazy dog\n", count: 12).write(to: pads.appendingPathComponent("1.md"), atomically: true, encoding: .utf8)

        let model = EditorModel()
        let size = CGSize(width: 520, height: 400)
        let view = NSHostingView(rootView: ContentView(model: model).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: .aqua)
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        window.setFrameOrigin(NSPoint(x: 120, y: 260))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        /// What is on screen (layer filters such as the blur only show in the composited window, not in `cacheDisplay`).
        func picture() throws -> NSBitmapImageRep {
            let image = try ScreenCapture.usable(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]))
            return NSBitmapImageRep(cgImage: image)
        }
        let first = try picture()
        // Text lines below the search panel (which sits near the top) and above the end of the text, whatever the scale.
        let rows = Int(Double(first.pixelsHigh) * 0.47)...Int(Double(first.pixelsHigh) * 0.60)
        let sharp = sharpness(first, rows: rows)
        toggle(model, true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let blurredPicture = try picture()
        let blurred = sharpness(blurredPicture, rows: rows)
        XCTAssertLessThan(blurred, sharp * 0.8, "the text behind the search panel should be softer (sharpness \(sharp) -> \(blurred))")
        toggle(model, false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        XCTAssertEqual(sharpness(try picture(), rows: rows), sharp, accuracy: 0.05, "and gets it back when the panel closes")
    }
}
