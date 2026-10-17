import AppKit
import SwiftUI

/// Owns show/hide of the single editor window. Closing hides it so the hotkey can bring it back.
@MainActor
final class WindowController: NSObject, NSWindowDelegate {
    static let shared = WindowController()
    private(set) weak var window: NSWindow?

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
        NSApp.hide(nil)
    }

    func toggle() {
        if NSApp.isActive, window?.isKeyWindow == true { hide() } else { show() }
    }
}

/// Hands the hosting NSWindow to `WindowController`.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { WindowController.shared.attach(w) } }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Control + Option + Space
        hotKey = HotKey(keyCode: 49, modifiers: 0x1000 | 0x0800) {
            MainActor.assumeIsolated { WindowController.shared.toggle() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { WindowController.shared.show() }
        return false
    }
}
