import AppKit

/// The fonts the editor uses. Prose can be the proportional system font (like Tot's rich text) or a monospaced one;
/// code and raw text are always monospaced.
enum EditorFont {
    static let defaultSize: Double = 14
    static let sizeRange: ClosedRange<Double> = 9...32
    /// The `fontFamily` setting that means the proportional system font. An empty value is the system monospaced font.
    static let systemFamily = "system"

    static func clamp(_ size: Double) -> CGFloat { CGFloat(min(max(size, sizeRange.lowerBound), sizeRange.upperBound)) }

    /// The font for prose: "system" is proportional, "" is monospaced, anything else is an installed family.
    static func font(size: Double, family: String) -> NSFont {
        let pt = clamp(size)
        if family == systemFamily { return .systemFont(ofSize: pt) }
        if !family.isEmpty, let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: pt) { return font }
        return .monospacedSystemFont(ofSize: pt, weight: .regular)
    }

    /// Always monospaced: the chosen family when it is a monospaced one, otherwise the system monospaced font.
    static func codeFont(size: Double, family: String) -> NSFont {
        let pt = clamp(size)
        if family != systemFamily, !family.isEmpty,
           let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: pt), font.isFixedPitch { return font }
        return .monospacedSystemFont(ofSize: pt, weight: .regular)
    }

    private static var savedSize: Double { UserDefaults.standard.object(forKey: "fontSize") as? Double ?? defaultSize }
    private static var savedFamily: String { UserDefaults.standard.string(forKey: "fontFamily") ?? systemFamily }

    /// The prose font from the saved settings (used to size the window in columns and rows).
    static var current: NSFont { font(size: savedSize, family: savedFamily) }

    /// The width of one character cell: exactly the advance for monospaced fonts, the width of a "0" otherwise.
    static func cellWidth(_ font: NSFont) -> CGFloat { advance(of: "0", in: font) }

    static func advance(of text: String, in font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Installed monospaced font families.
    static let families: [String] = NSFontManager.shared.availableFontFamilies.filter {
        NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 12)?.isFixedPitch == true
    }
}
