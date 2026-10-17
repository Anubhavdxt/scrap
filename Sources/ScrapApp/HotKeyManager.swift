import AppKit
import Foundation

/// Owns the global show/hide hotkey and its saved setting.
@MainActor
final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    static let defaultCode = 49 // Space
    static let defaultMods = 0x1000 | 0x0800 // Control + Option (Carbon masks)
    static let defaultLabel = "⌃⌥Space"

    @Published private(set) var label: String
    @Published private(set) var error: String?
    /// True while the recorder is capturing keys, so Esc cancels recording instead of closing the popover.
    @Published var isRecording = false

    var action: (() -> Void)?
    private var hotKey: HotKey?
    private let defaults = UserDefaults.standard

    private var code: Int { defaults.object(forKey: "hotkeyCode") as? Int ?? Self.defaultCode }
    private var mods: Int { defaults.object(forKey: "hotkeyMods") as? Int ?? Self.defaultMods }

    private init() {
        label = UserDefaults.standard.string(forKey: "hotkeyLabel") ?? Self.defaultLabel
    }

    var isDefault: Bool { code == Self.defaultCode && mods == Self.defaultMods }

    /// Registers the saved shortcut (call once at launch).
    func start() {
        if !register(code: code, mods: mods) {
            error = "\(label) is already used by another app. Pick a different shortcut."
        }
    }

    /// Switches to a new shortcut. On failure the previous one stays active.
    @discardableResult
    func set(code newCode: Int, mods newMods: Int, label newLabel: String) -> Bool {
        let (oldCode, oldMods) = (code, mods)
        hotKey = nil // unregister first so the same combination can be re-registered
        if register(code: newCode, mods: newMods) {
            defaults.set(newCode, forKey: "hotkeyCode")
            defaults.set(newMods, forKey: "hotkeyMods")
            defaults.set(newLabel, forKey: "hotkeyLabel")
            label = newLabel
            error = nil
            return true
        }
        _ = register(code: oldCode, mods: oldMods)
        error = "\(newLabel) is already used by another app. Kept \(label)."
        return false
    }

    func reset() {
        set(code: Self.defaultCode, mods: Self.defaultMods, label: Self.defaultLabel)
    }

    private func register(code: Int, mods: Int) -> Bool {
        hotKey = HotKey(keyCode: code, modifiers: mods) { [weak self] in
            MainActor.assumeIsolated { self?.action?() }
        }
        return hotKey != nil
    }

    // MARK: Labels

    static func carbonMods(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.control) { m |= 0x1000 }
        if flags.contains(.option) { m |= 0x0800 }
        if flags.contains(.shift) { m |= 0x0200 }
        if flags.contains(.command) { m |= 0x0100 }
        return m
    }

    static func label(for event: NSEvent) -> String {
        var s = ""
        let f = event.modifierFlags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option) { s += "⌥" }
        if f.contains(.shift) { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        let special: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "⌫", 117: "⌦", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        s += special[event.keyCode] ?? (event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)")
        return s
    }
}
