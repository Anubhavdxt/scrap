import Foundation

/// One of the fixed pad slots, stored as `<number>.md` in the pad folder.
public struct Pad: Identifiable, Hashable {
    public var id: Int { number }
    public let number: Int
    public let url: URL
    public var modified: Date
    /// First non-empty line, Markdown markers stripped. Empty when the pad has no content.
    public var preview: String

    public init(number: Int, url: URL, modified: Date = .distantPast, preview: String = "") {
        self.number = number
        self.url = url
        self.modified = modified
        self.preview = preview
    }

    public var name: String { "Pad \(number)" }
    public var isEmpty: Bool { preview.isEmpty }

    public static func preview(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let stripped = line.drop { $0 == "#" || $0 == ">" || $0 == " " }
        return String((stripped.isEmpty ? Substring(line) : stripped).prefix(60))
    }
}
