import Foundation

/// Markdown formatting commands for the editor (bold, italic, strikethrough, code, divider).
/// Pure functions over UTF-16 offsets that return a `TextEdit`, like `ListEditing`.
public enum Formatting {
    public enum Style: CaseIterable {
        case bold, italic, strikethrough, code

        var marker: String {
            switch self {
            case .bold: "**"
            case .italic: "*"
            case .strikethrough: "~~"
            case .code: "`"
            }
        }
        private var markerChar: unichar { marker.utf16.first! }
        var length: Int { marker.utf16.count }

        /// Whether `run` consecutive marker characters on both sides mean this style is already applied.
        func present(runs run: Int) -> Bool {
            switch self {
            case .italic: run % 2 == 1          // `*x*` yes, `**x**` no, `***x***` yes
            case .bold, .strikethrough: run >= 2
            case .code: run >= 1
            }
        }

        func countRun(in ns: NSString, from index: Int, step: Int, limit: Range<Int>) -> Int {
            var count = 0, i = index
            while limit.contains(i), ns.character(at: i) == markerChar { count += 1; i += step }
            return count
        }
    }

    // MARK: Toggle a style

    /// Wraps the selection (or the word at the cursor) in the style's markers, or removes them if already there.
    /// Multi-line selections are styled line by line. With nothing to wrap, inserts an empty pair and puts the cursor inside.
    public static func toggle(_ style: Style, in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard selection.location >= 0, selection.upperBound <= ns.length else { return nil }

        if selection.length > 0, ns.substring(with: selection).contains(where: \.isNewline) {
            return toggleLines(style, in: ns, selection: selection)
        }
        guard let target = target(in: ns, selection: selection) else {
            // Nothing to wrap: an empty pair with the caret inside.
            let pair = style.marker + style.marker
            return TextEdit(range: selection, replacement: pair, selection: NSRange(location: selection.location + style.length, length: 0))
        }
        return toggle(style, ns, target: target)
    }

    private static func toggle(_ style: Style, _ ns: NSString, target: NSRange) -> TextEdit {
        let m = style.length
        // Markers just outside the target.
        let before = style.countRun(in: ns, from: target.location - 1, step: -1, limit: 0..<ns.length)
        let after = style.countRun(in: ns, from: target.upperBound, step: 1, limit: 0..<ns.length)
        if style.present(runs: min(before, after)) {
            let range = NSRange(location: target.location - m, length: target.length + 2 * m)
            return TextEdit(range: range, replacement: ns.substring(with: target), selection: NSRange(location: target.location - m, length: target.length))
        }
        // Markers inside a selection that includes them, such as a selected `**bold**`.
        let inner = ns.substring(with: target) as NSString
        let leading = style.countRun(in: inner, from: 0, step: 1, limit: 0..<inner.length)
        let trailing = style.countRun(in: inner, from: inner.length - 1, step: -1, limit: 0..<inner.length)
        let k = min(leading, trailing)
        if inner.length > 2 * k, style.present(runs: k) {
            let stripped = inner.substring(with: NSRange(location: m, length: inner.length - 2 * m))
            return TextEdit(range: target, replacement: stripped, selection: NSRange(location: target.location, length: (stripped as NSString).length))
        }
        let wrapped = style.marker + (inner as String) + style.marker
        return TextEdit(range: target, replacement: wrapped, selection: NSRange(location: target.location + m, length: target.length))
    }

    private static func toggleLines(_ style: Style, in ns: NSString, selection: NSRange) -> TextEdit? {
        var edits: [TextEdit] = []   // one per non-blank selected line
        ns.enumerateSubstrings(in: ns.lineRange(for: selection), options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            if let piece = trim(NSIntersectionRange(lineRange, selection), in: ns) { edits.append(toggle(style, ns, target: piece)) }
        }
        guard !edits.isEmpty else { return nil }
        // If every line is already styled, unwrap them all; otherwise style only the lines that aren't yet.
        func isUnwrap(_ e: TextEdit) -> Bool { e.replacement.utf16.count < e.range.length }
        let chosen = edits.allSatisfy(isUnwrap) ? edits : edits.filter { !isUnwrap($0) }
        // The region spans every selected line, so the selection keeps covering them all afterwards.
        let start = edits.map(\.range.location).min()!, end = edits.map { $0.range.upperBound }.max()!
        let region = NSRange(location: start, length: end - start)
        let replacement = rebuild(ns, range: region, edits: chosen)
        return TextEdit(range: region, replacement: replacement, selection: NSRange(location: start, length: (replacement as NSString).length))
    }

    /// Applies non-overlapping edits to the text inside `range`.
    private static func rebuild(_ ns: NSString, range: NSRange, edits: [TextEdit]) -> String {
        var s = ns.substring(with: range) as NSString
        for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
            s = s.replacingCharacters(in: NSRange(location: edit.range.location - range.location, length: edit.range.length), with: edit.replacement) as NSString
        }
        return s as String
    }

    // MARK: Target selection

    /// The selection without surrounding spaces, or the word around the caret. nil when there is nothing to wrap.
    private static func target(in ns: NSString, selection: NSRange) -> NSRange? {
        if selection.length > 0 { return trim(selection, in: ns) }
        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < ns.length, let scalar = UnicodeScalar(ns.character(at: i)) else { return i >= 0 && i < ns.length }
            return wordChars.contains(scalar)
        }
        var start = selection.location, end = selection.location
        while isWord(start - 1) { start -= 1 }
        while isWord(end) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    private static func trim(_ range: NSRange, in ns: NSString) -> NSRange? {
        var start = range.location, end = range.upperBound
        func isSpace(_ i: Int) -> Bool { CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(ns.character(at: i)) ?? "x") }
        while start < end && isSpace(start) { start += 1 }
        while end > start && isSpace(end - 1) { end -= 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    // MARK: Divider

    /// Inserts a `---` rule on its own line below the cursor's line (with a blank line above it, so it
    /// can't turn the line above into a heading), and moves the cursor below it.
    public static func insertDivider(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(selection.location, ns.length), length: 0))
        let line = ns.substring(with: NSRange(location: start, length: contentsEnd - start))
        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            let range = NSRange(location: start, length: contentsEnd - start)
            return TextEdit(range: range, replacement: "---\n", selection: NSRange(location: start + 4, length: 0))
        }
        let insertion = "\n\n---\n"
        return TextEdit(range: NSRange(location: contentsEnd, length: 0), replacement: insertion,
                        selection: NSRange(location: contentsEnd + (insertion as NSString).length, length: 0))
    }
}
