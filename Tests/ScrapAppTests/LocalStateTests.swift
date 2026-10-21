import XCTest
import SwiftUI
import Vision
@testable import ScrapApp

/// `Local` has to behave like `@State`: changes redraw the view, and `$` hands out a working binding.
@MainActor
final class LocalStateTests: XCTestCase {
    private struct Child: View {
        @Binding var count: Int
        var body: some View { Button("bump") { count += 10 }.buttonStyle(.plain) }
    }

    private struct Counter: View {
        @Local private var count = 0
        var body: some View {
            VStack(spacing: 0) {
                Button("tap") { count += 1 }.buttonStyle(.plain).frame(maxWidth: .infinity).frame(height: 30).contentShape(Rectangle())
                Child(count: $count).frame(maxWidth: .infinity).frame(height: 30).contentShape(Rectangle())
                Text("count \(count)").font(.system(size: 20)).frame(height: 40)
            }
            .frame(width: 200, height: 120, alignment: .top)
            .background(Color.white)
            .foregroundStyle(Color.black)
        }
    }

    private func click(_ window: NSWindow, at p: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
    }

    private func text(_ view: NSView) throws -> String {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: try XCTUnwrap(rep.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    func testChangesRedrawAndTheBindingWritesBack() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Counter())
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        var shown = try text(host)
        XCTAssertTrue(shown.contains("count 0"), shown)

        // The buttons stack at the top of the content: "tap" first, then "bump".
        let h = host.bounds.height
        click(window, at: NSPoint(x: host.bounds.midX, y: h - 15))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        shown = try text(host)
        XCTAssertTrue(shown.contains("count 1"), "tapping bumps the value and redraws: \(shown)")
        click(window, at: NSPoint(x: host.bounds.midX, y: h - 45))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        shown = try text(host)
        XCTAssertTrue(shown.contains("count 11"), "the child's binding writes back: \(shown)")
    }
}
