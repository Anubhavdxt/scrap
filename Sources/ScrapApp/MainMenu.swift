import AppKit

/// The app's main menu. It isn't visible for a menu-bar-only app, but macOS routes keyboard shortcuts
/// like ⌘C, ⌘V, ⌘A and ⌘Z through it, so without it the editor can't copy, paste or select all.
@MainActor
enum MainMenu {
    static func install() {
        let main = NSMenu()

        // scrap
        let app = submenu(of: main, title: "scrap")
        item(app, "Settings…", #selector(Actions.openSettings), ",", target: Actions.shared)
        app.addItem(.separator())
        item(app, "Hide scrap", #selector(NSApplication.hide(_:)), "h")
        app.addItem(.separator())
        item(app, "Quit scrap", #selector(NSApplication.terminate(_:)), "q")

        // File
        let file = submenu(of: main, title: "File")
        item(file, "Close", #selector(Actions.close), "w", target: Actions.shared)

        // Edit
        let edit = submenu(of: main, title: "Edit")
        item(edit, "Undo", Selector(("undo:")), "z")
        let redo = item(edit, "Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        item(edit, "Cut", #selector(NSText.cut(_:)), "x")
        item(edit, "Copy", #selector(NSText.copy(_:)), "c")
        item(edit, "Paste", #selector(NSText.paste(_:)), "v")
        item(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        // Format
        let format = submenu(of: main, title: "Format")
        item(format, "Bold", #selector(Actions.bold), "b", target: Actions.shared)
        item(format, "Italic", #selector(Actions.italic), "i", target: Actions.shared)
        item(format, "Strikethrough", #selector(Actions.strikethrough), "x", target: Actions.shared).keyEquivalentModifierMask = [.command, .shift]
        item(format, "Code", #selector(Actions.code), "e", target: Actions.shared)
        format.addItem(.separator())
        item(format, "Toggle Task", #selector(Actions.task), "8", target: Actions.shared).keyEquivalentModifierMask = [.control]
        item(format, "Check or Uncheck Task", #selector(Actions.checkbox), "\r", target: Actions.shared)
        item(format, "Insert Divider", #selector(Actions.divider), "-", target: Actions.shared).keyEquivalentModifierMask = [.control]

        // View
        let view = submenu(of: main, title: "View")
        item(view, "Increase Font Size", #selector(Actions.biggerFont), "+", target: Actions.shared)
        item(view, "Decrease Font Size", #selector(Actions.smallerFont), "-", target: Actions.shared)
        item(view, "Actual Size", #selector(Actions.resetFont), "0", target: Actions.shared)
        view.addItem(.separator())
        item(view, "Wrap Lines", #selector(Actions.toggleWrap), "", target: Actions.shared)

        NSApp.mainMenu = main
    }

    private static func submenu(of main: NSMenu, title: String) -> NSMenu {
        let holder = NSMenuItem()
        let menu = NSMenu(title: title)
        holder.submenu = menu
        main.addItem(holder)
        return menu
    }

    @discardableResult
    private static func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target // nil sends the action down the responder chain (the text view)
        menu.addItem(item)
        return item
    }

    @MainActor
    final class Actions: NSObject, NSMenuItemValidation {
        static let shared = Actions()
        private var defaults: UserDefaults { .standard }
        private var fontSize: Double { defaults.object(forKey: "fontSize") as? Double ?? EditorFont.defaultSize }

        @objc func bold() { EditorCommand.bold.post() }
        @objc func italic() { EditorCommand.italic.post() }
        @objc func strikethrough() { EditorCommand.strikethrough.post() }
        @objc func code() { EditorCommand.code.post() }
        @objc func task() { EditorCommand.task.post() }
        @objc func checkbox() { EditorCommand.checkbox.post() }
        @objc func divider() { EditorCommand.divider.post() }

        @objc func biggerFont() { defaults.set(min(fontSize + 1, EditorFont.sizeRange.upperBound), forKey: "fontSize") }
        @objc func smallerFont() { defaults.set(max(fontSize - 1, EditorFont.sizeRange.lowerBound), forKey: "fontSize") }
        @objc func resetFont() { defaults.set(EditorFont.defaultSize, forKey: "fontSize") }
        @objc func toggleWrap() { defaults.set(!(defaults.object(forKey: "wrapLines") as? Bool ?? true), forKey: "wrapLines") }

        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(toggleWrap) {
                item.state = (defaults.object(forKey: "wrapLines") as? Bool ?? true) ? .on : .off
            }
            return true
        }

        @objc func openSettings() { NotificationCenter.default.post(name: .toggleSettings, object: nil) }
        @objc func close() { NotificationCenter.default.post(name: .closePopover, object: nil) }
    }
}
