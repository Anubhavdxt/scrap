import Foundation

/// The smart bullets you add yourself: rules, storage and a suggestion for the next one.
public enum CustomBullets {
    public enum Problem: Equatable, LocalizedError {
        case notOneCharacter(String)
        case notASymbol(String)
        case same(String)
        case taken(String)
        case tooMany

        public var errorDescription: String? {
            switch self {
            case .notOneCharacter(let s): "“\(s)”: each side is one character."
            case .notASymbol(let s): "“\(s)”: use a symbol or emoji, not a letter, a digit or a plain keyboard character."
            case .same(let s): "“\(s)” is both the open and the done form."
            case .taken(let s): "“\(s)” is already used by another bullet."
            case .tooMany: "At most \(SmartBullets.maxCustom) of your own."
            }
        }
    }

    /// Checks one side of a pair on its own: exactly one character, and a symbol or emoji. Letters, digits and ASCII
    /// punctuation are refused because any line starting with one would suddenly become a bullet.
    public static func problem(withGlyph glyph: String) -> Problem? {
        guard glyph.count == 1, let ch = glyph.first else { return .notOneCharacter(glyph) }
        if ch.isLetter || ch.isNumber || ch.isASCII || ch.isWhitespace || ch.isNewline { return .notASymbol(glyph) }
        return nil
    }

    /// The first problem in a list of your own pairs, or nil if it is fine. Every glyph must be unique across the built-in
    /// pairs and yours.
    public static func validate(_ pairs: [SmartBullets.Pair]) -> Problem? {
        if pairs.count > SmartBullets.maxCustom { return .tooMany }
        var seen = Set(SmartBullets.builtIn.flatMap { [$0.open, $0.done] })
        for pair in pairs {
            for glyph in [pair.open, pair.done] {
                if let problem = problem(withGlyph: glyph) { return problem }
            }
            if pair.open == pair.done { return .same(pair.open) }
            for glyph in [pair.open, pair.done] {
                if !seen.insert(glyph).inserted { return .taken(glyph) }
            }
        }
        return nil
    }

    // MARK: The Settings form

    public struct FormResult: Equatable {
        /// What to store, or nil to leave what is stored alone (something is wrong, or nothing changed).
        public var store: [SmartBullets.Pair]?
        /// What to tell the user, if anything.
        public var message: String?
    }

    /// Decides what to do with the rows in the Settings form (as typed so far). Rows with an empty side are still being
    /// typed and are skipped; a bad glyph or a clash is reported and nothing is stored until it is fixed.
    public static func evaluate(_ rows: [(open: String, done: String)]) -> FormResult {
        for row in rows {
            for glyph in [row.open, row.done] where !glyph.isEmpty {
                if let problem = problem(withGlyph: glyph) { return FormResult(store: nil, message: problem.errorDescription) }
            }
        }
        let complete = rows.filter { !$0.open.isEmpty && !$0.done.isEmpty }.map { SmartBullets.Pair(open: $0.open, done: $0.done) }
        if let problem = validate(complete) { return FormResult(store: nil, message: problem.errorDescription) }
        let incomplete = rows.count - complete.count
        return FormResult(store: complete, message: incomplete > 0 ? "Fill in both sides to use a bullet." : nil)
    }

    // MARK: Storage (a JSON string, as kept in the app's settings)

    public static func encode(_ pairs: [SmartBullets.Pair]) -> String {
        guard let data = try? JSONEncoder().encode(pairs), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// Reads the stored pairs, keeping only the ones that are valid (in order), so damaged or hand-edited settings can
    /// never put a bad bullet in play.
    public static func decode(_ json: String) -> [SmartBullets.Pair] {
        guard let data = json.data(using: .utf8), let all = try? JSONDecoder().decode([SmartBullets.Pair].self, from: data) else { return [] }
        var kept: [SmartBullets.Pair] = []
        for pair in all where validate(kept + [pair]) == nil { kept.append(pair) }
        return kept
    }

    // MARK: Suggestions

    private static let suggestions: [SmartBullets.Pair] = [
        ("◇", "◆"), ("△", "▲"), ("♡", "♥"), ("☐", "☑"), ("✧", "✦"), ("⬜", "⬛"), ("⚪", "⚫"), ("🔹", "🔷"),
        ("🟡", "🟢"), ("▫", "▪"), ("◌", "◍"), ("⬡", "⬢"),
    ].map { SmartBullets.Pair(open: $0.0, done: $0.1) }

    /// A ready-made pair that fits next to `existing`, for the "add" button, or nil when all eight are taken.
    public static func nextSuggestion(after existing: [SmartBullets.Pair]) -> SmartBullets.Pair? {
        guard existing.count < SmartBullets.maxCustom else { return nil }
        return suggestions.first { validate(existing + [$0]) == nil }
    }
}
