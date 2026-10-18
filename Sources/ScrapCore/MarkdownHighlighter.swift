import Foundation

/// The bullet, task box or number at the start of a list item, with the layout facts the editor needs to draw it.
public struct ListMarker: Equatable {
    public enum Kind: Equatable { case bullet, taskOpen, taskDone, number }
    public var kind: Kind
    /// Width of the leading indentation in character cells (a tab counts as 4).
    public var indentColumns: Int
    /// Characters in the marker, including the spaces after it (for example `- [ ] ` is 6).
    public var columns: Int
}

public struct Span: Equatable {
    public var range: NSRange
    public var token: Token
    public var bold = false
    public var italic = false
    public var strike = false
    /// Set on links: where ⌘-click goes. `www.` and bare addresses are normalised.
    public var url: String? = nil
    /// Set on the span covering a list item's marker.
    public var marker: ListMarker? = nil
}

/// Line-based Markdown highlighter; fenced code is lexed per language (see `CodeLanguage`). Pure: returns spans only.
public enum MarkdownHighlighter {
    public static func spans(in text: String) -> [Span] {
        var spans: [Span] = []
        let ns = text as NSString
        var fence: String?          // opening fence marker while inside a code block
        var language = CodeLanguage.generic
        var lexState = LexState()

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let line = ns.substring(with: range)
            let trimmed = line.drop { $0 == " " || $0 == "\t" }

            if let marker = fenceMarker(trimmed) {
                if let open = fence {
                    if marker.hasPrefix(open.prefix(1)) && marker.count >= open.count && trimmed.dropFirst(marker.count).allSatisfy({ $0 == " " }) {
                        fence = nil
                        lexState = LexState()
                    }
                } else {
                    fence = marker
                    language = CodeLanguage.forFence(trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
                    lexState = LexState()
                }
                spans.append(Span(range: range, token: .comment))
                return
            }
            if fence != nil {
                CodeLexer.lex(line, at: range.location, language: language, state: &lexState, into: &spans)
                return
            }
            markdownLine(line, at: range.location, into: &spans)
        }
        return spans
    }

    // MARK: Markdown

    private static func fenceMarker(_ s: Substring) -> String? {
        for ch in ["`", "~"] {
            let run = s.prefix { String($0) == ch }
            if run.count >= 3 { return String(run) }
        }
        return nil
    }

    private static let heading = try! NSRegularExpression(pattern: "^ {0,3}#{1,6}(?:\\s|$)")
    private static let quote = try! NSRegularExpression(pattern: "^ {0,3}>")
    private static let listItem = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let rule = try! NSRegularExpression(pattern: "^ {0,3}(?:(?:-\\s*){3,}|(?:\\*\\s*){3,}|(?:_\\s*){3,})$")
    private static let inlineCode = try! NSRegularExpression(pattern: "(`+)(?:(?!\\1).)+?\\1")
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(pattern: "(?<![*\\w])(\\*|_)(?=[^\\s*_])(.+?)(?<=[^\\s*_])\\1(?![*\\w])")
    private static let link = try! NSRegularExpression(pattern: "(!?)\\[([^\\]]*)\\]\\(([^)\\s]*)[^)]*\\)")
    private static let autolink = try! NSRegularExpression(pattern: #"<((?:https?://|mailto:)[^>\s]+)>|(?:https?://|www\.|mailto:)[^\s<>]+"#)

    private static func markdownLine(_ line: String, at base: Int, into spans: inout [Span]) {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + base, length: r.length) }

        if heading.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shift(whole), token: .title, bold: true))
            inline(line, from: 0, base: base, emphasis: false, into: &spans)
            return
        }
        if rule.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shift(whole), token: .comment))
            return
        }
        if quote.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shift(whole), token: .comment, italic: true))
            inline(line, from: 0, base: base, emphasis: false, into: &spans)
            return
        }
        var start = 0
        if let m = listItem.firstMatch(in: line, range: whole) {
            let indent = ns.substring(with: m.range(at: 1))
            let bulletRange = m.range(at: 2)
            let bullet = ns.substring(with: bulletRange)
            let box = m.range(at: 4)
            let kind: ListMarker.Kind
            if box.location != NSNotFound {
                kind = ns.substring(with: NSRange(location: box.location + 1, length: 1)) == " " ? .taskOpen : .taskDone
            } else {
                kind = bullet.first.map { "-*+".contains($0) } == true ? .bullet : .number
            }
            let region = NSRange(location: bulletRange.location, length: m.range.upperBound - bulletRange.location)
            let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            spans.append(Span(range: shift(region), token: .number,
                              marker: ListMarker(kind: kind, indentColumns: columns, columns: region.length)))
            start = m.range.upperBound
            // A finished task reads as done: dim and struck through.
            if kind == .taskDone, start < ns.length {
                spans.append(Span(range: shift(NSRange(location: start, length: ns.length - start)), token: .comment, strike: true))
            }
        }
        inline(line, from: start, base: base, emphasis: true, into: &spans)
    }

    /// Inline code, links, bare URLs and (optionally) bold and italic, from `start` to the end of the line.
    private static func inline(_ line: String, from start: Int, base: Int, emphasis: Bool, into spans: inout [Span]) {
        let ns = line as NSString
        let rest = NSRange(location: start, length: ns.length - start)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + base, length: r.length) }

        // Inline code wins; other inline styles skip anything inside it.
        var taken: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }
        func scan(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for m in re.matches(in: line, range: rest) where free(m.range) { body(m); taken.append(m.range) }
        }
        scan(inlineCode) { spans.append(Span(range: shift($0.range), token: .string)) }
        scan(link) { m in
            let isImage = m.range(at: 1).length > 0
            spans.append(Span(range: shift(m.range), token: .comment))
            spans.append(Span(range: shift(m.range(at: 2)), token: .attr, url: isImage ? nil : normalizedURL(ns.substring(with: m.range(at: 3)))))
        }
        scan(autolink) { m in
            let inner = m.range(at: 1)
            if inner.location != NSNotFound {
                spans.append(Span(range: shift(m.range), token: .comment))
                spans.append(Span(range: shift(inner), token: .attr, url: normalizedURL(ns.substring(with: inner))))
            } else {
                var range = m.range
                var text = ns.substring(with: range)
                // Trailing punctuation belongs to the sentence, not the address.
                while let last = text.last, ".,;:!?'\"]}".contains(last) || (last == ")" && !text.contains("(")) {
                    text.removeLast()
                    range.length -= 1
                }
                if range.length > 0 { spans.append(Span(range: shift(range), token: .attr, url: normalizedURL(text))) }
            }
        }
        guard emphasis else { return }
        scan(bold) { spans.append(Span(range: shift($0.range), token: .keyword, bold: true)) }
        scan(italic) { spans.append(Span(range: shift($0.range), token: .type, italic: true)) }
    }

    /// Adds a scheme to bare `www.` addresses.
    static func normalizedURL(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") { return text }
        if lower.hasPrefix("www.") { return "https://" + text }
        return text.contains("@") && !text.contains("/") ? "mailto:" + text : "https://" + text
    }
}
