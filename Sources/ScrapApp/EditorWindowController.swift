import AppKit
import Combine
import SwiftUI

private struct WindowedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when the editor is shown in its own window rather than the popover.
    var scrapWindowed: Bool {
        get { self[WindowedKey.self] }
        set { self[WindowedKey.self] = newValue }
    }
}

/// The detached editor: a normal, resizable window. Closing only hides it, so the hotkey, the menu bar icon and the Dock
/// icon can always bring it back with the same size and position.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let model: EditorModel
    private(set) var window: NSWindow?
    private var titleObserver: AnyCancellable?

    init(model: EditorModel) {
        self.model = model
    }

    var isVisible: Bool { window?.isVisible == true }
    var isKey: Bool { window?.isKeyWindow == true }

    /// Shows the window; with `pointer` (the global mouse location) it is moved so the pointer is in its top bar.
    func show(near pointer: NSPoint? = nil, screens: [PointerPlacement.Screen] = PointerPlacement.currentScreens) {
        let window = ensureWindow()
        applySettings(to: window)
        if let pointer {
            window.setFrame(PointerPlacement.frame(size: window.frame.size, pointer: pointer, screens: screens), display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard !EditorModel.shared.showSayHi else { return }
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    func hide() {
        model.flush()
        window?.orderOut(nil)
    }

    /// Re-reads the always-on-top and light/dark settings.
    func applySettings() {
        if let window { applySettings(to: window) }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    // MARK: Building

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let size = WindowSize.current()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        // A frameless look like Tot's: no title and no red/yellow/green buttons (the top bar has its own ×). It stays a
        // real titled window underneath, so it keeps the system shadow, rounded corners and edge resizing.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        let host = NSHostingController(rootView: ContentView(model: model).environment(\.scrapWindowed, true))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(size)
        window.minSize = NSSize(width: 300, height: 200)
        window.center()
        window.setFrameAutosaveName("ScrapEditorWindow") // restores the last size and place when there is one
        window.delegate = self
        window.title = model.pad.name
        titleObserver = model.$pad.sink { [weak window] pad in window?.title = pad.name }
        self.window = window
        return window
    }

    private func applySettings(to window: NSWindow) {
        window.level = UserDefaults.standard.bool(forKey: "windowFloating") ? .floating : .normal
        window.appearance = switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
    }
}
