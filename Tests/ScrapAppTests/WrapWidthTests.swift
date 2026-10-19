import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

@MainActor
final class WrapWidthTests: XCTestCase {
    private final class Box { var text = "" }
    private func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }

    /// Changing a setting re-applied the wrap with a container as wide as the whole view, so text and code panels ran
    /// 24 points under the right edge.
    func testTheTextContainerStaysInsideTheViewAfterASettingChanges() throws {
        let box = Box()
        box.text = "```\nlet pads = 7 // a long line that wraps around the edge of a narrow window for sure, really\n```\n"
        var theme = Themes.all[0]
        let binding = Binding(get: { box.text }, set: { box.text = $0 })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: EditorView(text: binding, theme: theme, fontSize: 14, fontFamily: "", wrap: true))
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        spin(0.3)
        let tv = try XCTUnwrap(find(host))
        func inner() -> CGFloat { tv.bounds.width - tv.textContainerInset.width * 2 }
        XCTAssertEqual(tv.textContainer!.size.width, inner(), accuracy: 0.5, "at first")

        theme = Themes.all[3]
        host.rootView = EditorView(text: binding, theme: theme, fontSize: 16, fontFamily: "", wrap: true)
        host.layoutSubtreeIfNeeded()
        spin(0.3)
        XCTAssertEqual(tv.textContainer!.size.width, inner(), accuracy: 0.5, "after a theme and font change")
    }

    private func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
}
