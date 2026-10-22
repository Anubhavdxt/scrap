import Foundation

/// The bullet, task box or number at the start of a list item, with the layout facts the editor needs to draw it.
public struct ListMarker: Equatable {
    public enum Kind: Equatable { case bullet, taskOpen, taskDone, number, smartOpen, smartDone }
    public var kind: Kind
    /// Width of the leading indentation in character cells (a tab counts as 4).
    public var indentColumns: Int
    /// Characters in the marker, including the spaces after it (for example `- [ ] ` is 6).
    public var columns: Int
    /// For smart bullets: the length of the bullet character itself (an emoji is two UTF-16 units).
    public var glyphLength = 1
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
    /// Markdown punctuation (`**`, `#`, backticks, link brackets, fences): dimmed, or hidden away from the cursor.
    public var syntax = false
    /// 1 to 6 on a heading's line.
    public var heading = 0
    /// On a block quote's line.
    public var quote = false
    /// On a line of a fenced code block, fence lines included (the editor draws one panel behind them).
    public var block = false
    /// Produced by the code lexer, so it keeps its syntax colours whatever the colour-highlight setting is.
    public var code = false
    /// A `` `code` `` run.
    public var inlineCode = false
    /// On a colour code such as `#0352BF`: the colour as 0xRRGGBBAA, drawn as a chip behind the text.
    public var chip: UInt32? = nil
    /// On the opening fence of a code block: the language written after the backticks (`swift` in "```swift").
    public var blockLabel: String? = nil
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
                    // Inside a block only a matching, bare fence ends it; any other fence-looking line is just code.
                    if marker.hasPrefix(open.prefix(1)) && marker.count >= open.count && trimmed.dropFirst(marker.count).allSatisfy({ $0 == " " }) {
                        fence = nil
                        lexState = LexState()
                        spans.append(Span(range: range, token: .comment, syntax: true, block: true))
                        return
                    }
                } else {
                    fence = marker
                    let info = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
                    language = CodeLanguage.forFence(info)
                    let label = info.split(whereSeparator: { $0 == " " || $0 == "{" || $0 == "\t" }).first.map(String.init)
                    lexState = LexState()
                    spans.append(Span(range: range, token: .comment, syntax: true, block: true, blockLabel: label))
                    return
                }
            }
            if fence != nil {
                spans.append(Span(range: range, token: .base, block: true))
                let before = spans.count
                CodeLexer.lex(line, at: range.location, language: language, state: &lexState, into: &spans)
                for i in before..<spans.count { spans[i].code = true }
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
    // A space before the closing `**` still counts ("**title **"): people type it, and the result is what they meant.
    // (`__` keeps the strict rule.)
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*)(?=\\S)(.+?)(?<=\\S)[ \\t]*\\*\\*|(__)(?=\\S)(.+?)(?<=\\S)__")
    private static let boldItalic = try! NSRegularExpression(pattern: "(\\*\\*\\*|___)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicStar = try! NSRegularExpression(pattern: "(?<!\\*)\\*(?=[^\\s*])(.+?)(?<=[^\\s*])[ \\t]*\\*(?!\\*)")
    private static let italicUnderscore = try! NSRegularExpression(pattern: "(?<!\\w)_(?=[^\\s_])(.+?)(?<=[^\\s_])_(?!\\w)")
    /// `#RRGGBB` and `#RRGGBBAA` anywhere; `#RGB` and `#RGBA` too, but only inside backticks (bare `#123` is usually an issue number).
    private static let longColor = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&#/])#([0-9A-Fa-f]{8}|[0-9A-Fa-f]{6})(?![\p{L}\p{N}_])"#)
    private static let shortColor = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}_&#/])#([0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})(?![\p{L}\p{N}_])"#)
    private static let link = try! NSRegularExpression(pattern: "(!?)\\[([^\\]]*)\\]\\(([^)\\s]*)[^)]*\\)")
    private static let strike = try! NSRegularExpression(pattern: "(~~)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let autolink = try! NSRegularExpression(pattern: #"<((?:https?://|mailto:)[^>\s]+)>|(?:https?://|www\.|mailto:)[^\s<>]+"#)

    private static func markdownLine(_ line: String, at base: Int, into spans: inout [Span]) {
        let ns = line as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func shift(_ r: NSRange) -> NSRange { NSRange(location: r.location + base, length: r.length) }

        if let h = heading.firstMatch(in: line, range: whole) {
            let level = ns.substring(with: h.range).filter { $0 == "#" }.count
            spans.append(Span(range: shift(whole), token: .title, bold: true, heading: level))
            inline(line, from: 0, base: base, emphasis: false, into: &spans)
            spans.append(Span(range: shift(NSRange(location: 0, length: h.range.length)), token: .comment, syntax: true))
            return
        }
        if rule.firstMatch(in: line, range: whole) != nil {
            spans.append(Span(range: shift(whole), token: .comment))
            return
        }
        if let q = quote.firstMatch(in: line, range: whole) {
            spans.append(Span(range: shift(whole), token: .comment, italic: true, quote: true))
            inline(line, from: 0, base: base, emphasis: false, into: &spans)
            // The `>` and one following space.
            let markerLength = q.range.length + (q.range.upperBound < ns.length && ns.character(at: q.range.upperBound) == 32 ? 1 : 0)
            spans.append(Span(range: shift(NSRange(location: 0, length: markerLength)), token: .comment, syntax: true))
            return
        }
        var start = 0
        if let smart = SmartBullets.marker(in: line) {
            // A Tot-style smart bullet: a real character, clickable, with a done form.
            let indent = ns.substring(to: smart.indentLength)
            let region = NSRange(location: smart.indentLength, length: smart.length)
            let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            spans.append(Span(range: shift(region), token: .number,
                              marker: ListMarker(kind: smart.isDone ? .smartDone : .smartOpen, indentColumns: columns,
                                                 columns: region.length, glyphLength: smart.glyphLength)))
            start = region.upperBound
            if smart.isDone, start < ns.length {
                spans.append(Span(range: shift(NSRange(location: start, length: ns.length - start)), token: .comment, strike: true))
            }
            inline(line, from: start, base: base, emphasis: true, into: &spans)
            return
        }
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
        func syntaxSpans(_ range: NSRange, open: Int, close: Int) {
            spans.append(Span(range: shift(NSRange(location: range.location, length: open)), token: .comment, syntax: true))
            spans.append(Span(range: shift(NSRange(location: range.upperBound - close, length: close)), token: .comment, syntax: true))
        }
        var codeRanges: [NSRange] = []
        scan(inlineCode) { m in
            codeRanges.append(m.range)
            spans.append(Span(range: shift(m.range), token: .string, inlineCode: true))
            syntaxSpans(m.range, open: m.range(at: 1).length, close: m.range(at: 1).length)
        }
        scan(link) { m in
            let isImage = m.range(at: 1).length > 0
            spans.append(Span(range: shift(m.range), token: .comment))
            let text = m.range(at: 2)
            spans.append(Span(range: shift(text), token: .attr, url: isImage ? nil : normalizedURL(ns.substring(with: m.range(at: 3)))))
            if !isImage {
                // `[` before the text, and `](address)` after it.
                spans.append(Span(range: shift(NSRange(location: m.range.location, length: 1)), token: .comment, syntax: true))
                spans.append(Span(range: shift(NSRange(location: text.upperBound, length: m.range.upperBound - text.upperBound)), token: .comment, syntax: true))
            }
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

        // Colour codes become chips. In code, any form; elsewhere only the long forms, and never inside a link or address.
        for (re, inCodeOnly) in [(longColor, false), (shortColor, true)] {
            for m in re.matches(in: line, range: rest) {
                let inCode = codeRanges.contains { NSIntersectionRange($0, m.range).length == m.range.length }
                guard inCode || (!inCodeOnly && free(m.range)) else { continue }
                let digits = ns.substring(with: m.range(at: 1))
                if let value = colorValue(digits) { spans.append(Span(range: shift(m.range), token: .base, chip: value)) }
            }
        }
        guard emphasis else { return }

        // `***both***` first, so the shorter forms don't take part of it.
        for m in boldItalic.matches(in: line, range: rest) where free(m.range) {
            spans.append(Span(range: shift(m.range), token: .keyword, bold: true, italic: true))
            syntaxSpans(m.range, open: 3, close: 3)
            taken.append(m.range)
        }
        // Emphasis can nest (`**bold *both* bold**`, `_**x**_`), so the rest only keep out of code, links and triples,
        // not out of each other.
        let blocked = taken
        func styled(_ re: NSRegularExpression, token: Token, bold: Bool = false, italic: Bool = false, strike: Bool = false, markerLength: Int) {
            for m in re.matches(in: line, range: rest) where !blocked.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                spans.append(Span(range: shift(m.range), token: token, bold: bold, italic: italic, strike: strike))
                syntaxSpans(m.range, open: markerLength, close: markerLength)
            }
        }
        // Italic before bold, so where they overlap the bold colour wins.
        styled(italicStar, token: .type, italic: true, markerLength: 1)
        styled(italicUnderscore, token: .type, italic: true, markerLength: 1)
        styled(bold, token: .keyword, bold: true, markerLength: 2)
        styled(strike, token: .comment, strike: true, markerLength: 2)
    }

    /// 0xRRGGBBAA from 3, 4, 6 or 8 hex digits.
    static func colorValue(_ digits: String) -> UInt32? {
        var full = digits
        if digits.count == 3 || digits.count == 4 { full = digits.map { "\($0)\($0)" }.joined() }
        guard full.count == 6 || full.count == 8, let value = UInt32(full, radix: 16) else { return nil }
        return full.count == 6 ? (value << 8) | 0xFF : value
    }

    /// Adds a scheme to bare `www.` addresses.
    static func normalizedURL(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") { return text }
        if lower.hasPrefix("www.") { return "https://" + text }
        return text.contains("@") && !text.contains("/") ? "mailto:" + text : "https://" + text
    }
}
