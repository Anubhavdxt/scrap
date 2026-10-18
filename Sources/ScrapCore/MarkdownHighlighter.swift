import Foundation

public struct Span: Equatable {
    public var range: NSRange
    public var token: Token
    public var bold = false
    public var italic = false
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
    private static let bullet = try! NSRegularExpression(pattern: "^\\s*(?:[-*+]|\\d+[.)])(?:\\s+\\[[ xX]\\])?\\s")
    private static let rule = try! NSRegularExpression(pattern: "^ {0,3}(?:(?:-\\s*){3,}|(?:\\*\\s*){3,}|(?:_\\s*){3,})$")
    private static let inlineCode = try! NSRegularExpression(pattern: "(`+)(?:(?!\\1).)+?\\1")
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(pattern: "(?<![*\\w])(\\*|_)(?=[^\\s*_])(.+?)(?<=[^\\s*_])\\1(?![*\\w])")
    private static let link = try! NSRegularExpression(pattern: "!?\\[([^\\]]*)\\]\\(([^)\\s]*)[^)]*\\)")
    private static let autolink = try! NSRegularExpression(pattern: "<https?://[^>\\s]+>|https?://[^\\s)>]+")

    private static func markdownLine(_ line: String, at base: Int, into spans: inout [Span]) {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + base, length: r.length) }

        if heading.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shift(whole), token: .title, bold: true))
            return
        }
        if rule.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shift(whole), token: .comment))
            return
        }
        var start = 0
        if quote.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shift(whole), token: .comment, italic: true))
            return
        }
        if let m = bullet.firstMatch(in: line, range: whole) {
            spans.append(Span(range: shift(NSRange(location: m.range.location, length: m.range.length - 1)), token: .number))
            start = m.range.upperBound
        }
        let rest = NSRange(location: start, length: ns.length - start)

        // Inline code wins; other inline styles skip anything inside it.
        var taken: [NSRange] = []
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }
        func scan(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for m in re.matches(in: line, range: rest) where free(m.range) { body(m); taken.append(m.range) }
        }
        scan(inlineCode) { spans.append(Span(range: shift($0.range), token: .string)) }
        scan(link) { m in
            spans.append(Span(range: shift(m.range), token: .comment))
            spans.append(Span(range: shift(m.range(at: 1)), token: .attr))
        }
        scan(autolink) { spans.append(Span(range: shift($0.range), token: .attr)) }
        scan(bold) { spans.append(Span(range: shift($0.range), token: .keyword, bold: true)) }
        scan(italic) { spans.append(Span(range: shift($0.range), token: .type, italic: true)) }
    }
}
