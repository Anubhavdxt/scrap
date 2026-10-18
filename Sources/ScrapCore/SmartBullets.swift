import Foundation

/// Smart bullets: a real character at the start of a line (`○ buy milk`) that flips between an open and a done form
/// when clicked. Because they are plain characters, text pasted in with these bullets works as is. There are eight
/// built in, and up to eight more of your own.
public enum SmartBullets {
    public struct Pair: Equatable, Codable {
        public let open: String
        public let done: String

        public init(open: String, done: String) {
            self.open = open
            self.done = done
        }
    }

    /// The built-in open and done forms. The two dash pairs use different dashes (an en dash and a minus sign), and the
    /// first one's done form is a heavy plus rather than `+`, which on its own is a Markdown bullet.
    public static let builtIn: [Pair] = [
        Pair(open: "○", done: "●"),
        Pair(open: "□", done: "■"),
        Pair(open: "▷", done: "▶"),
        Pair(open: "☆", done: "★"),
        Pair(open: "–", done: "➕"),
        Pair(open: "−", done: "✓"),
        Pair(open: "❌", done: "✅"),
        Pair(open: "⭕", done: "🔴"),
    ]

    /// How many pairs of your own there can be.
    public static let maxCustom = 8

    // The app sets the custom pairs (from Settings) on the main thread, before the editor reads them; the lock only keeps
    // the pair list and the pattern built from it consistent.
    private static let lock = NSLock()
    private static var storedCustom: [Pair] = []
    private static var cachedRegex: (signature: String, regex: NSRegularExpression)?

    /// Your own pairs. Setting invalid ones is the caller's mistake: `CustomBullets.decode` and `validate` keep them sane.
    public static var custom: [Pair] {
        get { lock.lock(); defer { lock.unlock() }; return storedCustom }
        set { lock.lock(); storedCustom = newValue; lock.unlock() }
    }

    /// Built-in pairs followed by your own. The index into this list is a bullet's identity everywhere (the picker, inserting).
    public static var pairs: [Pair] { builtIn + custom }

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

    private static func regex(for pairs: [Pair]) -> NSRegularExpression {
        let signature = pairs.map { $0.open + "|" + $0.done }.joined(separator: ",")
        lock.lock(); defer { lock.unlock() }
        if let cached = cachedRegex, cached.signature == signature { return cached.regex }
        let glyphs = pairs.flatMap { [$0.open, $0.done] }.sorted { $0.utf16.count > $1.utf16.count }
        let alternatives = glyphs.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: "^([ \\t]*)(\(alternatives))([ \\t]+|$)")
        cachedRegex = (signature, regex)
        return regex
    }

    /// The smart bullet at the start of `line`, if there is one (a bullet needs a space after it, or to end the line).
    public static func marker(in line: String) -> Marker? {
        let ns = line as NSString
        let all = pairs
        guard let m = regex(for: all).firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let glyph = ns.substring(with: m.range(at: 2))
        for (index, pair) in all.enumerated() {
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
