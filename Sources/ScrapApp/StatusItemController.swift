import AppKit
import SwiftUI

extension Notification.Name {
    static let focusEditor = Notification.Name("scrap.focusEditor")
}

/// Menu bar icon plus the popover it drops down, like Tot. Menu-bar-only app (no Dock icon).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = EditorModel.shared

        popover.behavior = .transient
        popover.contentSize = NSSize(width: ContentView.size.width, height: ContentView.size.height)
        popover.contentViewController = NSHostingController(rootView: ContentView(model: model))
        NotificationCenter.default.addObserver(forName: NSPopover.willCloseNotification, object: popover, queue: .main) { _ in
            MainActor.assumeIsolated { model.flush() }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "scrap")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item

        // Control + Option + Space
        hotKey = HotKey(keyCode: 49, modifiers: 0x1000 | 0x0800) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
    }

    @objc func toggle() {
        if popover.isShown { popover.performClose(nil) } else { show() }
    }

    private func show() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }
}
