import Foundation

/// The footer's counts.
public enum TextStats {
    /// "12 lines · 45 words · 425 characters". With `selection` true it ends with "selected".
    public static func summary(_ text: String, selection: Bool = false) -> String {
        let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        let words = text.split(whereSeparator: \.isWhitespace).count
        let characters = text.count
        let base = "\(lines) \(lines == 1 ? "line" : "lines") · \(words) \(words == 1 ? "word" : "words") · \(characters) \(characters == 1 ? "character" : "characters")"
        return selection ? base + " selected" : base
    }
}
