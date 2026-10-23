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

    /// Called when the window is hidden, so a settings window beside it goes too.
    var onHide: (() -> Void)?

    func hide() {
        model.flush()
        window?.orderOut(nil)
        onHide?()
    }

    /// Re-reads the always-on-top and light/dark settings.
    func applySettings() {
        if let window { applySettings(to: window) }
    }

    // MARK: Size

    /// The window is as big as Settings says (columns by rows), like the popover. Changing the steppers or the font moves
    /// it to the new size, with its top-left corner staying put.
    func syncSize() {
        guard let window, !window.inLiveResize else { return }
        let wanted = WindowSize.current()
        let current = window.contentRect(forFrameRect: window.frame).size
        guard abs(current.width - wanted.width) > 0.5 || abs(current.height - wanted.height) > 0.5 else { return }
        resize(window, toContentSize: wanted)
    }

    private func resize(_ window: NSWindow, toContentSize size: CGSize) {
        let top = window.frame.maxY
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: top - frame.height)
        window.setFrame(frame, display: true)
    }

    // MARK: NSWindowDelegate

    /// Dragging an edge steps by whole columns and rows.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let content = sender.contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
        return sender.frameRect(forContentRect: NSRect(origin: .zero, size: WindowSize.snapped(content))).size
    }

    /// Letting go of an edge writes the new columns and rows to Settings, which the popover and the steppers read.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let cells = WindowSize.cells(forContentSize: window.contentRect(forFrameRect: window.frame).size)
        WindowSize.store(cols: cells.cols, rows: cells.rows)
    }

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
        window.contentMinSize = WindowSize.contentSize(cols: WindowSize.colsRange.lowerBound, rows: WindowSize.rowsRange.lowerBound)
        window.center()
        window.setFrameAutosaveName("ScrapEditorWindow") // restores the last place (the size comes from Settings, below)
        resize(window, toContentSize: size)
        window.delegate = self
        window.title = model.pad.name
        titleObserver = model.$pad.sink { [weak window] pad in window?.title = pad.name }
        self.window = window
        return window
    }

    private func applySettings(to window: NSWindow) {
        syncSize()
        window.level = UserDefaults.standard.bool(forKey: "windowFloating") ? .floating : .normal
        let vibrant = UserDefaults.standard.bool(forKey: "vibrant")
        window.isOpaque = !vibrant
        window.backgroundColor = vibrant ? .clear : .windowBackgroundColor
        window.invalidateShadow()
        window.appearance = switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
    }
}
