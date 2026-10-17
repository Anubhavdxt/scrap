import AppKit
import SwiftUI

extension Notification.Name {
    static let focusEditor = Notification.Name("scrap.focusEditor")
    static let closePopover = Notification.Name("scrap.closePopover")
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
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        NotificationCenter.default.addObserver(forName: .closePopover, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
        statusItem = item

        // Control + Option + Space
        hotKey = HotKey(keyCode: 49, modifiers: 0x1000 | 0x0800) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit scrap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Attach the menu only for this click so left-clicks keep toggling the popover.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openSettings() { SettingsWindow.shared.show() }

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
