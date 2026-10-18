import Foundation

/// Where scrap shows its icon.
enum IconMode: String, CaseIterable, Identifiable {
    case menuBar, dock, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .menuBar: "Menu bar"
        case .dock: "Dock"
        case .both: "Both"
        }
    }
}

/// What the icon setting and the "detached" preference add up to.
///
/// The popover hangs from the menu bar icon, so it only exists when that icon does. With only a Dock icon the editor
/// is always a normal window; with a menu bar icon it is a popover unless the user detached it into a window.
struct DisplayPolicy: Equatable {
    var showsStatusItem: Bool
    var showsDockIcon: Bool
    /// The editor is a window rather than a popover.
    var usesWindow: Bool
    /// The user could choose between popover and window (false when a window is the only option).
    var canAttach: Bool

    static func resolve(icon: IconMode, detached: Bool) -> DisplayPolicy {
        let status = icon != .dock
        return DisplayPolicy(showsStatusItem: status, showsDockIcon: icon != .menuBar, usesWindow: detached || !status, canAttach: status)
    }

    static func current(_ defaults: UserDefaults = .standard) -> DisplayPolicy {
        resolve(icon: IconMode(rawValue: defaults.string(forKey: "iconMode") ?? "") ?? .menuBar,
                detached: defaults.bool(forKey: "detached"))
    }
}
