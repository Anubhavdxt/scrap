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

    /// How heavy bold text is: one step above the system "Bold", so it reads clearly as bold next to regular text.
    static let boldWeight: NSFont.Weight = .heavy

    /// `font` made bold (at `boldWeight`) and/or italic, optionally at another size. Keeps the family, and anything
    /// already applied (a bold font stays bold when italic is added).
    ///
    /// Three kinds of font need three approaches: the system monospaced font ignores a weight set on its descriptor, so
    /// it is rebuilt at the weight; the proportional system font takes the weight on its descriptor; an installed family
    /// (Menlo, ...) only has its regular and bold cuts, so it falls back to the ordinary bold trait.
    static func styled(_ font: NSFont, bold: Bool, italic: Bool, size: CGFloat? = nil) -> NSFont {
        let pt = size ?? font.pointSize
        let wantsItalic = italic || isItalic(font)
        func withItalic(_ f: NSFont) -> NSFont {
            guard wantsItalic, !isItalic(f) else { return f }
            return NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.italic)), size: pt) ?? f
        }

        if font.fontName.hasPrefix(".AppleSystemUIFontMonospaced") {
            let weight = bold ? boldWeight : NSFont.Weight(rawValue: self.weight(of: font))
            return withItalic(.monospacedSystemFont(ofSize: pt, weight: weight))
        }

        var descriptor = font.fontDescriptor
        if wantsItalic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)) }
        if bold {
            // Replace only the weight inside the traits dictionary, so the italic flag set above survives.
            var traits = descriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any] ?? [:]
            traits[.weight] = boldWeight.rawValue
            descriptor = descriptor.addingAttributes([.traits: traits])
        }
        var result = NSFont(descriptor: descriptor, size: pt) ?? font
        if bold, !isBold(result) {
            result = NSFont(descriptor: result.fontDescriptor.withSymbolicTraits(result.fontDescriptor.symbolicTraits.union(.bold)), size: pt) ?? result
        }
        return result
    }

    /// The font's weight on the -1...1 scale NSFont uses (0 regular, about 0.4 bold, about 0.56 heavy).
    static func weight(of font: NSFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? 0
    }

    static func isBold(_ font: NSFont) -> Bool { weight(of: font) >= 0.35 || font.fontDescriptor.symbolicTraits.contains(.bold) }
    static func isItalic(_ font: NSFont) -> Bool { font.fontDescriptor.symbolicTraits.contains(.italic) }

    /// Installed monospaced font families.
    static let families: [String] = NSFontManager.shared.availableFontFamilies.filter {
        NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 12)?.isFixedPitch == true
    }
}
