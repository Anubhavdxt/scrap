import AppKit

/// How one pad's dot looks, by state. Three states read at a glance:
/// - the open pad: a solid disc with a soft halo, a little larger
/// - a pad with text: a ring with a bold dot in the middle (a filled bullseye)
/// - an empty pad: a thin, faint ring that recedes
struct PadDotStyle: Equatable {
    var diameter: CGFloat
    var ringWidth: CGFloat
    var ringOpacity: Double
    /// Faint colour inside the ring.
    var fillOpacity: Double
    /// Diameter of the dot in the middle; 0 for none.
    var innerDot: CGFloat
    /// Width of the soft glow around the disc; 0 for none.
    var halo: CGFloat

    /// The room each dot takes in the row, whatever its state, so nothing shifts when you switch pads.
    static let slot: CGFloat = 22

    static func make(current: Bool, empty: Bool) -> PadDotStyle {
        if current { return PadDotStyle(diameter: 15, ringWidth: 0, ringOpacity: 0, fillOpacity: 1, innerDot: 0, halo: 3.5) }
        if empty { return PadDotStyle(diameter: 14, ringWidth: 1.5, ringOpacity: 0.5, fillOpacity: 0, innerDot: 0, halo: 0) }
        return PadDotStyle(diameter: 14, ringWidth: 2, ringOpacity: 1, fillOpacity: 0.16, innerDot: 6, halo: 0)
    }
}

extension PadDotStyle {
    /// Black or white, whichever reads better on the open pad's solid disc.
    static func numberColor(on fill: NSColor) -> NSColor {
        guard let c = fill.usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luminance > 0.6 ? NSColor.black.withAlphaComponent(0.75) : .white
    }
}

/// The footer's background: the theme's own, with a little of the open pad's colour in it.
enum FooterTint {
    /// A straight mix in sRGB: `strength` 0 is the background, 1 is the pad colour.
    static func color(background: NSColor, pad: NSColor, strength: CGFloat) -> NSColor {
        guard let base = background.usingColorSpace(.sRGB), let tint = pad.usingColorSpace(.sRGB) else { return background }
        let t = min(max(strength, 0), 1)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return NSColor(srgbRed: mix(base.redComponent, tint.redComponent), green: mix(base.greenComponent, tint.greenComponent),
                       blue: mix(base.blueComponent, tint.blueComponent), alpha: base.alphaComponent)
    }
}
