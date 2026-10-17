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
    final class Actions: NSObject {
        static let shared = Actions()
        @objc func openSettings() { NotificationCenter.default.post(name: .toggleSettings, object: nil) }
        @objc func close() { NotificationCenter.default.post(name: .closePopover, object: nil) }
    }
}
