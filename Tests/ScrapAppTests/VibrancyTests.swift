import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

@MainActor
final class VibrancyTests: XCTestCase {
    private func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }

    func testVibrantBackgroundsKeepOnlyPartOfTheThemeColour() {
        let color = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        XCTAssertEqual(Vibrancy.background(color, vibrant: false).alphaComponent, 1)
        XCTAssertEqual(Vibrancy.background(color, vibrant: true).alphaComponent, Vibrancy.backgroundAlpha, accuracy: 0.001)
        XCTAssertLessThan(Vibrancy.backgroundAlpha, 1)
        XCTAssertGreaterThan(Vibrancy.backgroundAlpha, 0.4, "text must stay readable")
    }

    func testTheEditorDrawsItsBackgroundSeeThroughOnlyWhenVibrant() throws {
        for vibrant in [false, true] {
            let view = NSHostingView(rootView: EditorView(text: .constant("hello"), theme: Themes.all[0], fontSize: 14, fontFamily: "", wrap: true, vibrant: vibrant)
                .frame(width: 300, height: 200))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            let tv = try XCTUnwrap(find(view))
            let alpha = tv.backgroundColor.usingColorSpace(.sRGB)?.alphaComponent ?? -1
            XCTAssertEqual(alpha, vibrant ? Vibrancy.backgroundAlpha : 1, accuracy: 0.001)
            window.close()
        }
    }

    /// Writes a picture of the window over a striped backdrop, to look at (set SCRAP_SNAPSHOT_DIR).
    func testSnapshot() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write the picture") }
        let backdrop = NSWindow(contentRect: NSRect(x: 100, y: 200, width: 700, height: 460), styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        let stripes = NSHostingView(rootView: LinearGradient(colors: [.red, .orange, .green, .blue, .purple], startPoint: .leading, endPoint: .trailing))
        backdrop.contentView = stripes
        backdrop.orderFront(nil)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-vib-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        try "# Heading\nSome **bold** text and `code`\n- [ ] a task".write(to: pads.appendingPathComponent("1.md"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "vibrant")
        defer { UserDefaults.standard.removeObject(forKey: "vibrant"); backdrop.close(); try? FileManager.default.removeItem(at: home) }
        let model = EditorModel()
        let window = NSWindow(contentRect: NSRect(x: 160, y: 240, width: 460, height: 340), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(rootView: ContentView(model: model).environment(\.scrapWindowed, true))
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(.null, .optionOnScreenBelowWindow.union(.optionIncludingWindow), id, [.bestResolution]) ?? CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else { return XCTFail("no capture") }
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent("vibrant.png"))
        window.close()
    }
}
