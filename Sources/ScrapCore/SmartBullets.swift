import Foundation

/// Tot-style smart bullets: a real character at the start of a line (`○ buy milk`) that flips between an open and a done
/// form when clicked. Because they are plain characters, text pasted from Tot works as is.
public enum SmartBullets {
    public struct Pair: Equatable {
        public let open: String
        public let done: String
    }

    /// The open and done forms. The two dash pairs use different dashes (an en dash and a minus sign), and the first
    /// one's done form is a heavy plus rather than `+`, which on its own is a Markdown bullet.
    public static let pairs: [Pair] = [
        Pair(open: "○", done: "●"),
        Pair(open: "□", done: "■"),
        Pair(open: "▷", done: "▶"),
        Pair(open: "☆", done: "★"),
        Pair(open: "–", done: "➕"),
        Pair(open: "−", done: "✓"),
        Pair(open: "❌", done: "✅"),
        Pair(open: "⭕", done: "🔴"),
    ]

    public struct Marker: Equatable {
        public let pair: Int
        public let isDone: Bool
        /// Leading whitespace, in UTF-16 units.
        public let indentLength: Int
        /// The bullet character itself.
        public let glyphLength: Int
        /// Bullet plus the whitespace after it, from the end of the indentation.
        public let length: Int
        public let spacing: String

        public var glyph: String { isDone ? SmartBullets.pairs[pair].done : SmartBullets.pairs[pair].open }
    }

    private static let regex: NSRegularExpression = {
        let glyphs = pairs.flatMap { [$0.open, $0.done] }.sorted { $0.utf16.count > $1.utf16.count }
        let alternatives = glyphs.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "^([ \\t]*)(\(alternatives))([ \\t]+|$)")
    }()

    /// The smart bullet at the start of `line`, if there is one (a bullet needs a space after it, or to end the line).
    public static func marker(in line: String) -> Marker? {
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let glyph = ns.substring(with: m.range(at: 2))
        for (index, pair) in pairs.enumerated() {
            if pair.open == glyph || pair.done == glyph {
                return Marker(pair: index, isDone: pair.done == glyph, indentLength: m.range(at: 1).length,
                              glyphLength: m.range(at: 2).length, length: m.range.length - m.range(at: 1).length,
                              spacing: ns.substring(with: m.range(at: 3)))
            }
        }
        return nil
    }

    /// Flips the smart bullet on the line containing `location` between its open and done form.
    public static func toggle(in text: String, at location: Int) -> TextEdit? {
        let ns = text as NSString
        guard location >= 0, location <= ns.length else { return nil }
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        let line = ns.substring(with: NSRange(location: start, length: contentsEnd - start))
        guard let marker = marker(in: line) else { return nil }
        let pair = pairs[marker.pair]
        let range = NSRange(location: start + marker.indentLength, length: marker.glyphLength)
        let replacement = marker.isDone ? pair.open : pair.done
        return TextEdit(range: range, replacement: replacement, selection: NSRange(location: location, length: 0))
    }
}
