import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

@MainActor
final class AnchorTests: XCTestCase {
    /// With a second editor (the detached window) built but hidden, the settings popover must still attach to the gear of the
    /// editor that is showing: it once attached to the hidden window's gear and never appeared.
    func testTheGearOfTheVisibleEditorIsTheAnchor() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-anchor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        let model = EditorModel()

        func makeWindow(_ x: CGFloat) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: x, y: 300, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ContentView(model: model))
            return window
        }
        let first = makeWindow(100)    // the popover's editor, showing
        first.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        let second = makeWindow(700)   // the detached window's editor, built later and never shown
        second.contentView?.layoutSubtreeIfNeeded()
        second.orderFront(nil); second.orderOut(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        defer { first.close(); second.close() }

        let anchor = try XCTUnwrap(SettingsAnchor.view, "an anchor in the window that is showing")
        XCTAssertTrue(anchor.window === first, "the gear in the showing editor, not the hidden one")
        first.orderOut(nil)
        XCTAssertNil(SettingsAnchor.view, "no editor showing, no anchor")
    }
}
