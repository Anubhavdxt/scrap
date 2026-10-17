import AppKit

// Plain AppKit entry point: a menu-bar-only app has no SwiftUI scene, so nothing opens at launch.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
