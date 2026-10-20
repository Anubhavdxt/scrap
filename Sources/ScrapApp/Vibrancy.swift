import AppKit
import SwiftUI

/// "Vibrant background": the theme's colours are drawn partly see-through over a blurred view of what is behind the
/// window, so the desktop shows through softly. Text stays fully opaque.
enum Vibrancy {
    /// How much of the theme's background colour is kept when vibrant.
    static let backgroundAlpha: CGFloat = 0.6

    static func background(_ color: NSColor, vibrant: Bool) -> NSColor {
        vibrant ? color.withAlphaComponent(backgroundAlpha) : color
    }
}

/// The blurred backdrop (behind the window, not just behind this view).
struct VibrantBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow   // keeps more of what is behind than .underWindowBackground, which washes it out
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
