import AppKit
import Combine
import ScrapCore
import SwiftUI

extension Notification.Name {
    static let focusEditor = Notification.Name("scrap.focusEditor")
    static let closePopover = Notification.Name("scrap.closePopover")
    static let toggleSettings = Notification.Name("scrap.toggleSettings")
    static let editorCommand = Notification.Name("scrap.editorCommand")
    static let toggleDetach = Notification.Name("scrap.toggleDetach")
    static let insertSymbol = Notification.Name("scrap.insertSymbol")
    static let toggleSymbols = Notification.Name("scrap.toggleSymbols")
    static let closeSymbols = Notification.Name("scrap.closeSymbols")
}

/// Formatting and list commands sent from menus and buttons to the text view.
enum EditorCommand: String {
    case bold, italic, strikethrough, code, divider, task, checkbox

    func post() { NotificationCenter.default.post(name: .editorCommand, object: nil, userInfo: ["command": rawValue]) }
}

/// Something chosen in the symbol picker, to be put into the text at the cursor.
final class SymbolRequest {
    let kind: SymbolItem.Kind
    init(_ kind: SymbolItem.Kind) { self.kind = kind }
    func post() { NotificationCenter.default.post(name: .insertSymbol, object: self) }
}

/// The gear button registers itself here so the settings popover can attach to it.
enum SettingsAnchor {
    static weak var view: NSView?
}

/// The `*` footer button registers itself here so the symbol picker can open below it.
enum SymbolAnchor {
    static weak var view: NSView?
}

/// The editor's home. Depending on the Settings it is a popover hanging from the menu bar icon, or a normal window
/// (detached, or when there is no menu bar icon), with a menu bar icon, a Dock icon, or both. A settings popover attaches
/// to the gear in either. Popovers are dismissed here (click elsewhere, Esc, app switch); the window stays until closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let settingsPopover = NSPopover()
    private let symbolPopover = NSPopover()
    private lazy var windowController = EditorWindowController(model: EditorModel.shared)
    private var clickMonitors: [Any] = []
    private var keyMonitor: Any?
    private var padObserver: AnyCancellable?
    private var policy = DisplayPolicy.current()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenu.install()
        DispatchQueue.global(qos: .utility).async { _ = EditorFont.families } // warm the font list for Settings
        let model = EditorModel.shared

        popover.behavior = .applicationDefined
        popover.contentViewController = hosting(ContentView(model: model))
        settingsPopover.behavior = .applicationDefined
        settingsPopover.contentViewController = hosting(SettingsView(model: model))
        settingsPopover.contentSize = SettingsView.size
        symbolPopover.behavior = .applicationDefined
        symbolPopover.contentViewController = hosting(SymbolPicker())
        symbolPopover.contentSize = SymbolPicker.size
        applyLayout()

        let center = NotificationCenter.default
        center.addObserver(forName: NSPopover.willCloseNotification, object: popover, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                model.flush()
                self?.settingsPopover.performClose(nil)
                self?.symbolPopover.performClose(nil)
                self?.updateClickMonitors()
            }
        }
        for pop in [settingsPopover, symbolPopover] {
            center.addObserver(forName: NSPopover.willCloseNotification, object: pop, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateClickMonitors() }
            }
        }
        center.addObserver(forName: .toggleSymbols, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggleSymbols() }
        }
        center.addObserver(forName: .closeSymbols, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeSymbolsAndRefocus() }
        }
        center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.defaultsChanged() }
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeTransient() }
        }
        center.addObserver(forName: .closePopover, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAll() }
        }
        center.addObserver(forName: .toggleSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggleSettings() }
        }
        center.addObserver(forName: .toggleDetach, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggleDetach() }
        }

        applyPolicy(initial: true)
        // The icon follows the current pad's colour (Settings > General can turn that off).
        padObserver = model.$pad.sink { [weak self] _ in self?.updateStatusImage() }
        installKeyMonitor()

        let hotKeys = HotKeyManager.shared
        hotKeys.action = { [weak self] in self?.toggle(fromHotkey: true) }
        hotKeys.start()

        // With no menu bar icon there is nothing to click, so start with the window open.
        if !policy.showsStatusItem { windowController.show() }
    }

    /// Clicking the Dock icon brings the editor back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Settings that change how scrap shows up

    private func defaultsChanged() {
        if DisplayPolicy.current() != policy { applyPolicy(initial: false) }
        applyLayout()
        updateStatusImage()
    }

    /// Applies the icon setting (menu bar, Dock, both) and moves the editor between popover and window when that changed.
    private func applyPolicy(initial: Bool) {
        let old = policy
        let new = DisplayPolicy.current()
        policy = new
        let applied = NSApp.setActivationPolicy(new.showsDockIcon ? .regular : .accessory)
        if !applied { NSLog("scrap: couldn't switch the activation policy (dock icon: \(new.showsDockIcon))") }
        if new.showsStatusItem { ensureStatusItem() } else { removeStatusItem() }
        guard !initial, new.usesWindow != old.usesWindow else { return }
        if new.usesWindow, popover.isShown {
            closeTransient()
            windowController.show()
        } else if !new.usesWindow, windowController.isVisible {
            windowController.hide()
            showPopover()
        }
    }

    private func toggleDetach() {
        guard policy.canAttach else { return } // with only a Dock icon the editor is always a window
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "detached"), forKey: "detached")
    }

    /// Applies the saved window size and light/dark choice.
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
        symbolPopover.appearance = appearance
        windowController.applySettings()
    }

    // MARK: Menu bar icon

    private func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusImage()
    }

    private func removeStatusItem() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    /// The menu bar icon: the logo tinted with the current pad's colour, or the plain template image.
    private func updateStatusImage() {
        let tint = UserDefaults.standard.object(forKey: "tintMenuBar") as? Bool ?? true
        let base = Self.menuBarImage()
        statusItem?.button?.image = tint && base.isTemplate ? StatusIcon.tinted(base, with: PadColors.nsColor(for: EditorModel.shared.pad.number)) : base
    }

    /// The scrap logo as a template image (macOS tints it). Falls back to a symbol outside an app bundle.
    private static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for name in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
                  let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        if image.representations.isEmpty {
            return NSImage(systemSymbolName: "note.text", accessibilityDescription: "scrap") ?? image
        }
        image.isTemplate = true
        image.accessibilityDescription = "scrap"
        return image
    }

    private func hosting<V: View>(_ view: V) -> NSHostingController<V> {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [] // the popover's contentSize decides, not the SwiftUI ideal size
        return controller
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    private func showMenu() {
        closeTransient()
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit scrap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Attach the menu only for this click so left-clicks keep toggling the editor.
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openSettings() {
        if !settingsPopover.isShown { toggleSettings() }
    }

    // MARK: Show and hide

    private var editorVisible: Bool { policy.usesWindow ? windowController.isVisible : popover.isShown }

    private func toggle(fromHotkey: Bool = false) {
        if policy.usesWindow {
            // A visible window that isn't in front comes forward; one that is in front goes away.
            if windowController.isVisible && NSApp.isActive {
                closeAll()
            } else if fromHotkey && UserDefaults.standard.bool(forKey: "windowFollowsPointer") {
                windowController.show(near: NSEvent.mouseLocation)   // "Open the window at the pointer"
            } else {
                show()
            }
        } else if popover.isShown {
            closeAll()
        } else {
            show()
        }
    }

    private func show() {
        if policy.usesWindow || statusItem?.button == nil { windowController.show() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return windowController.show() }
        applyLayout()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        updateClickMonitors()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard !EditorModel.shared.showSayHi else { return }
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    /// Closes the things that are dismissed by clicking away: the settings popover and the editor popover.
    private func closeTransient() {
        settingsPopover.performClose(nil)
        symbolPopover.performClose(nil)
        popover.performClose(nil)
    }

    /// Closes everything, the editor window included.
    private func closeAll() {
        closeTransient()
        if windowController.isVisible { windowController.hide() }
    }

    private func toggleSettings() {
        if settingsPopover.isShown {
            settingsPopover.performClose(nil)
            return
        }
        symbolPopover.performClose(nil)
        guard editorVisible else {
            show()
            // Let the editor lay out so the gear exists before the settings attach to it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.presentSettings() }
            return
        }
        presentSettings()
    }

    private func presentSettings() {
        guard !settingsPopover.isShown else { return }
        let gear = SettingsAnchor.view.flatMap { $0.window?.isVisible == true ? $0 : nil }
        guard let anchor = gear ?? windowController.window?.contentView ?? statusItem?.button else { return }
        let rect = gear == nil && anchor === windowController.window?.contentView
            ? NSRect(x: anchor.bounds.maxX - 40, y: anchor.isFlipped ? 4 : anchor.bounds.maxY - 28, width: 24, height: 24)
            : anchor.bounds
        settingsPopover.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
        updateClickMonitors()
    }

    // MARK: Symbol picker

    /// The `*` button opens the picker below the editor (so it doesn't cover the note), and closes it again.
    private func toggleSymbols() {
        if symbolPopover.isShown {
            symbolPopover.performClose(nil)
            return
        }
        settingsPopover.performClose(nil)
        guard editorVisible else {
            show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.presentSymbols() }
            return
        }
        presentSymbols()
    }

    private func presentSymbols() {
        guard !symbolPopover.isShown else { return }
        let button = SymbolAnchor.view.flatMap { $0.window?.isVisible == true ? $0 : nil }
        guard let anchor = button ?? windowController.window?.contentView ?? popover.contentViewController?.view else { return }
        let rect = button == nil
            ? NSRect(x: anchor.bounds.maxX - 90, y: anchor.isFlipped ? anchor.bounds.maxY - 28 : 4, width: 24, height: 24)
            : anchor.bounds
        // Below the button, which is at the bottom of the editor: the picker hangs off the bottom edge, clear of the text.
        symbolPopover.show(relativeTo: rect, of: anchor, preferredEdge: .minY)
        updateClickMonitors()
    }

    /// A choice was made: close the picker and give the editor the keyboard back.
    private func closeSymbolsAndRefocus() {
        symbolPopover.performClose(nil)
        (policy.usesWindow ? windowController.window : popover.contentViewController?.view.window)?.makeKey()
        DispatchQueue.main.async { NotificationCenter.default.post(name: .focusEditor, object: nil) }
    }

    // MARK: Dismissal

    /// Esc: closes settings first, then the editor, unless an overlay (palette, clear, say hi) is using the key.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard event.keyCode == 53, !HotKeyManager.shared.isRecording, let self else { return event }
                let model = EditorModel.shared
                if self.symbolPopover.isShown { self.symbolPopover.performClose(nil); return nil }
                if model.showPalette || model.showClear || model.showSayHi { return event }
                if self.settingsPopover.isShown { self.settingsPopover.performClose(nil); return nil }
                let editorKey = self.policy.usesWindow ? self.windowController.isKey : self.popover.isShown
                guard editorKey else { return event }
                // "Escape closes the window" can be turned off in Settings > General.
                guard UserDefaults.standard.object(forKey: "escCloses") as? Bool ?? true else { return event }
                self.closeAll()
                return nil
            }
        }
    }

    /// Click monitors run only while a popover is open: a click in another app closes the popovers, and a click in the
    /// editor closes settings (but not on the gear, which toggles it).
    private func updateClickMonitors() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wanted = self.popover.isShown || self.settingsPopover.isShown || self.symbolPopover.isShown
            if wanted, self.clickMonitors.isEmpty { self.installClickMonitors() }
            if !wanted { self.clickMonitors.forEach(NSEvent.removeMonitor); self.clickMonitors = [] }
        }
    }

    private func installClickMonitors() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeTransient() }
        }) { clickMonitors.append(global) }
        if let click = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.settingsPopover.isShown || self.symbolPopover.isShown else { return event }
                let editorWindows = [self.popover.contentViewController?.view.window, self.windowController.window]
                guard editorWindows.contains(where: { $0 != nil && $0 === event.window }) else { return event }
                // A click in the editor closes the pane that is open, except on its own button, which toggles it.
                for (pane, anchor) in [(self.settingsPopover, SettingsAnchor.view), (self.symbolPopover, SymbolAnchor.view)] where pane.isShown {
                    if let anchor, anchor.bounds.insetBy(dx: -6, dy: -6).contains(anchor.convert(event.locationInWindow, from: nil)) { continue }
                    pane.performClose(nil)
                }
                return event
            }
        }) { clickMonitors.append(click) }
    }
}
