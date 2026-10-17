import AppKit
import SwiftUI

extension Notification.Name {
    static let focusEditor = Notification.Name("scrap.focusEditor")
    static let closePopover = Notification.Name("scrap.closePopover")
    static let toggleSettings = Notification.Name("scrap.toggleSettings")
}

/// The gear button registers itself here so the settings popover can attach to it.
enum SettingsAnchor {
    static weak var view: NSView?
}

/// Menu bar icon, the editor popover it drops down, and a settings popover attached to the gear.
/// Both popovers stay open together; we handle dismissal ourselves (click elsewhere, Esc, app switch).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let settingsPopover = NSPopover()
    private var hotKey: HotKey?
    private var monitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = EditorModel.shared

        popover.behavior = .applicationDefined
        popover.contentViewController = hosting(ContentView(model: model))
        settingsPopover.behavior = .applicationDefined
        settingsPopover.contentViewController = hosting(SettingsView(model: model))
        settingsPopover.contentSize = SettingsView.size
        applyLayout()

        let center = NotificationCenter.default
        center.addObserver(forName: NSPopover.willCloseNotification, object: popover, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                model.flush()
                self?.settingsPopover.performClose(nil)
                self?.removeMonitors()
            }
        }
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyLayout() }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAll() }
        }
        center.addObserver(forName: .closePopover, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAll() }
        }
        center.addObserver(forName: .toggleSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggleSettings() }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "scrap")
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // Control + Option + Space
        hotKey = HotKey(keyCode: 49, modifiers: 0x1000 | 0x0800) { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        }
    }

    private func hosting<V: View>(_ view: V) -> NSHostingController<V> {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [] // the popover's contentSize decides, not the SwiftUI ideal size
        return controller
    }

    /// Applies the saved window size and light/dark choice to both popovers.
    private func applyLayout() {
        let size = WindowSize.current()
        if popover.contentSize != size { popover.contentSize = size }
        let appearance: NSAppearance? = switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
        popover.appearance = appearance
        settingsPopover.appearance = appearance
    }

    // MARK: Status item

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    private func showMenu() {
        closeAll()
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

    @objc private func openSettings() {
        if !popover.isShown { show() }
        if !settingsPopover.isShown { toggleSettings() }
    }

    // MARK: Show and hide

    private func toggle() {
        if popover.isShown { closeAll() } else { show() }
    }

    private func show() {
        guard let button = statusItem?.button else { return }
        applyLayout()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        installMonitors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    private func closeAll() {
        settingsPopover.performClose(nil)
        popover.performClose(nil)
    }

    private func toggleSettings() {
        if settingsPopover.isShown {
            settingsPopover.performClose(nil)
            return
        }
        if !popover.isShown { show() }
        guard let anchor = SettingsAnchor.view ?? statusItem?.button else { return }
        settingsPopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    // MARK: Dismissal

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        // Clicks in other apps or the menu bar close both popovers.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAll() }
        }) { monitors.append(global) }
        // A click in the editor popover closes settings only (the gear toggles it itself).
        if let click = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.settingsPopover.isShown,
                      event.window === self.popover.contentViewController?.view.window else { return event }
                if let anchor = SettingsAnchor.view {
                    let point = anchor.convert(event.locationInWindow, from: nil)
                    if anchor.bounds.insetBy(dx: -6, dy: -6).contains(point) { return event }
                }
                self.settingsPopover.performClose(nil)
                return event
            }
        }) { monitors.append(click) }
        // Esc closes settings first, then the editor, unless an overlay (palette, clear) is using it.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard event.keyCode == 53, let self else { return event }
                let model = EditorModel.shared
                if model.showPalette || model.showClear { return event }
                if self.settingsPopover.isShown { self.settingsPopover.performClose(nil) } else { self.closeAll() }
                return nil
            }
        }) { monitors.append(local) }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
