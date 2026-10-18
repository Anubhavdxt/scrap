import AppKit

/// Alternate Dock icons. The bundle's own icon (Finder, Applications) can't change at runtime, so the choice
/// applies to the running app's Dock icon and its windows.
enum AppIcons {
    struct Choice: Identifiable, Equatable {
        let id: String
        let name: String
    }

    static let `default` = "cobalt"
    static let all: [Choice] = [
        Choice(id: "cobalt", name: "Cobalt"), Choice(id: "graphite", name: "Graphite"), Choice(id: "midnight", name: "Midnight"),
        Choice(id: "forest", name: "Forest"), Choice(id: "violet", name: "Violet"), Choice(id: "sunset", name: "Sunset"),
        Choice(id: "rose", name: "Rose"),
    ]

    /// A stored id that no longer exists falls back to the default.
    static func resolve(_ id: String) -> String { all.contains { $0.id == id } ? id : Self.default }

    static func image(_ id: String, bundle: Bundle = .main) -> NSImage? {
        bundle.url(forResource: resolve(id), withExtension: "png", subdirectory: "Icons").flatMap(NSImage.init(contentsOf:))
    }

    /// Sets the Dock icon. The default goes back to the bundle's own icon.
    @MainActor static func apply(_ id: String) {
        let id = resolve(id)
        NSApp.applicationIconImage = id == Self.default ? nil : image(id)
    }
}
