import AppKit
import ScrapCore

extension NSAttributedString.Key {
    /// A paragraph of a fenced code block: the layout manager draws one panel behind a run of these.
    static let scrapBlock = NSAttributedString.Key("scrap.block")
    /// The language of a code block, on its (hidden) opening fence: drawn in the panel's top-right corner.
    static let scrapBlockLabel = NSAttributedString.Key("scrap.blockLabel")
    /// A paragraph of a block quote: the layout manager draws a bar beside a run of these.
    static let scrapQuote = NSAttributedString.Key("scrap.quote")
}

enum MarkerMode: String {
    case hide   // Markdown punctuation is hidden except on the line with the caret
    case dim    // always visible but faint
    case show   // always visible
}

struct MarkdownStyle {
    var theme: Theme
    /// The prose font (proportional or monospaced, per the setting).
    var baseFont: NSFont
    /// Code, code blocks and raw text: always monospaced.
    var codeFont: NSFont
    var colorHighlights: Bool
    var markers: MarkerMode
    /// Raw mode: the same colours, weights, panels and links, but every Markdown mark stays visible (nothing hidden,
    /// no icons) and the text is monospaced.
    var raw = false

    var base: NSColor { NSColor(hex: theme.color(.base)) }
    var accent: NSColor { NSColor(hex: theme.accent) }
    var baseAttributes: [NSAttributedString.Key: Any] { [.font: baseFont, .foregroundColor: base] }
    /// Space reserved at the left of a bullet or task for its drawn icon.
    var iconAdvance: CGFloat { (baseFont.pointSize * 1.4).rounded() }
    /// Width of a space in the prose font: what one column of indentation is worth.
    var space: CGFloat { EditorFont.advance(of: " ", in: baseFont) }

    static let headingScale: [CGFloat] = [1.55, 1.35, 1.2, 1.1, 1.0, 1.0]
}

/// Turns the highlighter's spans into text attributes: weights, sizes, colours, hidden syntax, panels and bars.
/// The text itself is never changed, so the file stays plain Markdown.
enum MarkdownStyler {
    /// Restyles `range` (which must be made of whole paragraphs). `reveal` is the paragraph(s) with the caret,
    /// where hidden syntax is shown so it can be edited.
    static func apply(_ spans: [Span], to storage: NSTextStorage, range: NSRange, reveal: NSRange, style: MarkdownStyle) {
        guard range.length > 0 || storage.length == 0 else { return }
        let ns = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes(style.baseAttributes, range: range)
        for span in spans where intersects(span.range, range) {
            apply(span, to: storage, ns: ns, reveal: reveal, style: style)
        }
        storage.endEditing()
    }

    private static func intersects(_ a: NSRange, _ b: NSRange) -> Bool {
        a.length == 0 ? (a.location >= b.location && a.location <= b.upperBound) : NSIntersectionRange(a, b).length > 0
    }

    private static func apply(_ span: Span, to storage: NSTextStorage, ns: NSString, reveal: NSRange, style: MarkdownStyle) {
        let base = style.base
        if span.syntax {
            // In raw mode the marks keep the colour of the element they belong to (bold's `**` is bold-coloured).
            if style.raw && !span.block { return }
            return applySyntax(span, to: storage, ns: ns, reveal: reveal, style: style)
        }

        var attrs: [NSAttributedString.Key: Any] = [:]
        let themed = span.code || style.colorHighlights || span.token == .comment || span.token == .base
        attrs[.foregroundColor] = themed ? NSColor(hex: style.theme.color(span.token)) : base

        // Fonts: headings are larger and bold; emphasis adds weight and slant. These are merged into the font already
        // there, so overlapping spans stack (`**bold *both* bold**`) instead of the last one winning.
        // Themes italicise some tokens (comments, types); links, struck text and plain base text never are.
        let themeItalic = style.theme.italic.contains(span.token) && !span.strike && span.url == nil && span.token != .base
        let italic = span.italic || (themeItalic && (span.code || style.colorHighlights))
        var traits: NSFontDescriptor.SymbolicTraits = []
        if span.bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let size = span.heading > 0 ? style.baseFont.pointSize * MarkdownStyle.headingScale[min(span.heading, 6) - 1] : nil

        if span.block || span.code || span.inlineCode { attrs[.font] = style.codeFont }
        if span.strike {
            // Finished tasks and ~~struck~~ text: struck through and dimmed, not themed like a comment.
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attrs[.foregroundColor] = base.withAlphaComponent(0.5)
        }
        if span.inlineCode { attrs[.backgroundColor] = base.withAlphaComponent(0.12) }
        if let url = span.url {
            attrs[.font] = style.baseFont   // not the italic of the `[ ](…)` span underneath
            attrs[.foregroundColor] = style.colorHighlights ? style.accent : base
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attrs[.scrapURL] = url
        }
        storage.addAttributes(attrs, range: span.range)
        if !traits.isEmpty || size != nil { addTraits(traits, size: size, to: storage, range: span.range, style: style) }

        if span.block {
            storage.addAttribute(.scrapBlock, value: 1, range: paragraph(span.range, ns))
            let indent = NSMutableParagraphStyle()
            indent.firstLineHeadIndent = 8
            indent.headIndent = 8
            indent.tailIndent = -8
            storage.addAttribute(.paragraphStyle, value: indent, range: paragraph(span.range, ns))
        }
        if span.quote {
            storage.addAttribute(.scrapQuote, value: 1, range: paragraph(span.range, ns))
            let indent = NSMutableParagraphStyle()
            indent.firstLineHeadIndent = 14
            indent.headIndent = 14
            storage.addAttribute(.paragraphStyle, value: indent, range: paragraph(span.range, ns))
        }
        if let marker = span.marker, !style.raw { applyMarker(marker, over: span.range, to: storage, ns: ns, style: style) }
    }

    /// Adds bold/italic (and optionally a size) to whatever font each part of `range` already has.
    private static func addTraits(_ traits: NSFontDescriptor.SymbolicTraits, size: CGFloat?, to storage: NSTextStorage, range: NSRange, style: MarkdownStyle) {
        guard range.length > 0 else { return }
        storage.enumerateAttribute(.font, in: range, options: []) { value, run, _ in
            let current = (value as? NSFont) ?? style.baseFont
            let font = EditorFont.styled(current,
                                         bold: traits.contains(.bold) || EditorFont.isBold(current),
                                         italic: traits.contains(.italic) || EditorFont.isItalic(current),
                                         size: size)
            storage.addAttribute(.font, value: font, range: run)
        }
    }

    /// Markdown punctuation: dimmed, or collapsed to nothing unless the caret is on its line.
    private static func applySyntax(_ span: Span, to storage: NSTextStorage, ns: NSString, reveal: NSRange, style: MarkdownStyle) {
        let paragraphRange = paragraph(span.range, ns)
        let revealed = NSIntersectionRange(paragraphRange, reveal).length > 0 || (reveal.length == 0 && NSLocationInRange(reveal.location, paragraphRange))
        let hidden = style.markers == .hide && !revealed && !span.block
        if span.block {
            if !style.raw && style.markers == .hide && !revealed {
                // The ``` lines disappear (they collapse to a thin strip of padding) and the language moves to the panel's
                // top-right corner. They come back when the caret is on one, so the language can be edited.
                let thin = NSFont.monospacedSystemFont(ofSize: 6, weight: .regular)
                storage.addAttributes([.foregroundColor: NSColor.clear, .font: thin], range: paragraphRange)
                if let label = span.blockLabel, !label.isEmpty {
                    storage.addAttribute(.scrapBlockLabel, value: label, range: NSRange(location: paragraphRange.location, length: 1))
                }
            } else {
                storage.addAttributes([.foregroundColor: style.base.withAlphaComponent(0.4), .font: style.codeFont], range: span.range)
            }
            storage.addAttribute(.scrapBlock, value: 1, range: paragraphRange)
            let indent = NSMutableParagraphStyle()
            indent.firstLineHeadIndent = 8
            indent.headIndent = 8
            indent.tailIndent = -8
            storage.addAttribute(.paragraphStyle, value: indent, range: paragraphRange)
            return
        }
        if hidden {
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: span.range)
            for i in span.range.location..<span.range.upperBound {
                let font = storage.attribute(.font, at: i, effectiveRange: nil) as? NSFont ?? style.baseFont
                let width = EditorFont.advance(of: ns.substring(with: NSRange(location: i, length: 1)), in: font)
                storage.addAttribute(.kern, value: -width, range: NSRange(location: i, length: 1))
            }
        } else {
            let alpha: CGFloat = style.markers == .show ? 0.6 : (revealed ? 0.5 : 0.35)
            storage.addAttribute(.foregroundColor, value: style.base.withAlphaComponent(alpha), range: span.range)
        }
    }

    /// Collapses a bullet or task marker to an icon-sized gap (drawn by `ScrapLayoutManager`) and gives wrapped lines
    /// of the item a hanging indent, so continuation lines align with the item's text.
    private static func applyMarker(_ marker: ListMarker, over range: NSRange, to storage: NSTextStorage, ns: NSString, style: MarkdownStyle) {
        let indent = CGFloat(marker.indentColumns) * style.space
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = 0
        switch marker.kind {
        case .number:
            paragraph.headIndent = indent + EditorFont.advance(of: ns.substring(with: range), in: style.baseFont)
        case .smartOpen, .smartDone:
            // A smart bullet is a real character that stays visible: tint it, make it clickable, and hang wrapped lines under the text.
            paragraph.headIndent = indent + EditorFont.advance(of: ns.substring(with: range), in: style.baseFont)
            let glyph = NSRange(location: range.location, length: min(marker.glyphLength, range.length))
            storage.addAttribute(.foregroundColor, value: style.accent, range: glyph)
            storage.addAttribute(.scrapSmartBullet, value: 1, range: glyph)
        case .bullet, .taskOpen, .taskDone:
            paragraph.headIndent = indent + style.iconAdvance
            // Keep the characters (the file stays plain Markdown) but make them zero-width and invisible.
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            for i in range.location..<range.upperBound {
                let last = i == range.upperBound - 1
                // Cancel each character's own width (they differ in a proportional font), leaving `iconAdvance` in total.
                let width = EditorFont.advance(of: ns.substring(with: NSRange(location: i, length: 1)), in: style.baseFont)
                storage.addAttribute(.kern, value: last ? style.iconAdvance - width : -width, range: NSRange(location: i, length: 1))
            }
            let kind: MarkerKind = marker.kind == .bullet ? .bullet : (marker.kind == .taskOpen ? .taskOpen : .taskDone)
            storage.addAttribute(.scrapMarker, value: kind.rawValue, range: range)
        }
        storage.addAttribute(.paragraphStyle, value: paragraph, range: self.paragraph(range, ns))
    }

    /// The whole paragraph(s) containing `range`.
    private static func paragraph(_ range: NSRange, _ ns: NSString) -> NSRange {
        let location = min(range.location, ns.length)
        return ns.paragraphRange(for: NSRange(location: location, length: min(range.length, ns.length - location)))
    }
}
