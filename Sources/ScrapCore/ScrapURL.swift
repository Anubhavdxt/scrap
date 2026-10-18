import Foundation

/// The `scrap://` links the app understands:
///
///     scrap://open?pad=3                 show scrap, on pad 3 if given
///     scrap://add?text=hello%20world&pad=3   put text in a pad, like `scrap add` (the pad is optional)
///
/// Anything can open such a link (a web page too), so there is deliberately no action that reads a pad back, and `add`
/// is capped in size. Text is percent-encoded (spaces as `%20`); a `+` is a literal plus.
public enum ScrapURL {
    public enum Action: Equatable {
        case open(pad: Int?)
        case add(text: String, pad: Int?)
    }

    public enum Problem: Equatable, LocalizedError {
        case notScrap
        case unknownAction(String)
        case missingText
        case tooLong(Int)
        case badPad(String)

        public var errorDescription: String? {
            switch self {
            case .notScrap: "not a scrap:// link"
            case .unknownAction(let a): "unknown action “\(a)”"
            case .missingText: "nothing to add"
            case .tooLong(let n): "text is too long (\(n) bytes; the limit is \(ScrapURL.maxTextBytes))"
            case .badPad(let p): "“\(p)” is not a pad number"
            }
        }
    }

    /// The most text one link may add.
    public static let maxTextBytes = 20_000

    public static func parse(_ url: URL) -> Result<Action, Problem> {
        guard url.scheme?.lowercased() == "scrap", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .failure(.notScrap) }
        let action = (components.host ?? "").lowercased()
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name.lowercased() == name }?.value }

        var pad: Int?
        if let raw = value("pad") {
            guard let n = Int(raw.trimmingCharacters(in: .whitespaces)), n >= 1 else { return .failure(.badPad(raw)) }
            pad = n
        }
        switch action {
        case "open":
            return .success(.open(pad: pad))
        case "add":
            let text = value("text") ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .failure(.missingText) }
            let size = text.utf8.count
            if size > maxTextBytes { return .failure(.tooLong(size)) }
            return .success(.add(text: text, pad: pad))
        default:
            return .failure(.unknownAction(action))
        }
    }
}
