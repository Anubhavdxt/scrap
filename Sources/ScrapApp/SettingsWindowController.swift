import AppKit
import SwiftUI

/// Settings as a window of its own, used when the editor is a window: it stays until its close button is pressed, and
/// doesn't disappear when you click back in the editor, as the popover does.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: EditorModel
    private(set) var window: NSWindow?

    init(model: EditorModel) { self.model = model }

    var isVisible: Bool { window?.isVisible == true }
    var isKey: Bool { window?.isKeyWindow == true }

    /// Shows the window next to the editor window: on its right, or its left when there is no room.
    func show(beside editor: NSWindow?) {
        let window = ensureWindow()
        applySettings()
        if !window.isVisible, let editor { window.setFrameOrigin(Self.origin(for: window.frame.size, beside: editor.frame, screen: editor.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero)) }
        window.makeKeyAndOrderFront(nil)
    }

    func hide() { window?.orderOut(nil) }

    /// Follows the editor window's always-on-top and light/dark settings.
    func applySettings() {
        guard let window else { return }
        window.level = UserDefaults.standard.bool(forKey: "windowFloating") ? .floating : .normal
        window.appearance = switch UserDefaults.standard.string(forKey: "appearance") {
        case "dark": NSAppearance(named: .darkAqua)
        case "light": NSAppearance(named: .aqua)
        default: nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    /// Top-aligned with the editor, 10 points to its right; to its left when that would leave the screen.
    static func origin(for size: NSSize, beside editor: NSRect, screen: NSRect, gap: CGFloat = 10) -> NSPoint {
        var x = editor.maxX + gap
        if x + size.width > screen.maxX { x = editor.minX - size.width - gap }
        x = min(max(x, screen.minX), screen.maxX - size.width)
        let y = min(max(editor.maxY - size.height, screen.minY), screen.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SettingsView.size), styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(button)?.isHidden = true }
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        let host = NSHostingController(rootView: SettingsView(model: model, height: SettingsView.size.height).environment(\.scrapWindowed, true))
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(SettingsView.size)
        window.delegate = self
        window.title = "Settings"
        self.window = window
        return window
    }
}
