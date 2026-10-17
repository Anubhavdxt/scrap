import Foundation

public struct Span: Equatable {
    public var range: NSRange
    public var token: Token
    public var bold = false
    public var italic = false
}

/// Line-based Markdown highlighter with a generic lexer for fenced code. Pure: returns spans only.
public enum MarkdownHighlighter {
    public static func spans(in text: String) -> [Span] {
        var spans: [Span] = []
        let ns = text as NSString
        var fence: String?          // opening fence marker while inside a code block
        var lang = ""
        var inBlockComment = false

        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let line = ns.substring(with: range)
            let trimmed = line.drop { $0 == " " || $0 == "\t" }

            if let marker = fenceMarker(trimmed) {
                if let open = fence {
                    if marker.hasPrefix(open.prefix(1)) && marker.count >= open.count && trimmed.dropFirst(marker.count).allSatisfy({ $0 == " " }) {
                        fence = nil
                        inBlockComment = false
                    }
                } else {
                    fence = marker
                    lang = trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).lowercased()
                    inBlockComment = false
                }
                spans.append(Span(range: range, token: .comment))
                return
            }
            if fence != nil {
                lexCode(line, at: range.location, lang: lang, inBlockComment: &inBlockComment, into: &spans)
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

    // MARK: Fenced code (generic lexer)

    private static let hashComment: Set<String> = ["python", "py", "sh", "bash", "zsh", "shell", "yaml", "yml", "toml", "ruby", "rb", "ini", "conf", "make", "makefile", "dockerfile", "r", "perl", "pl", "elixir", "ex"]
    private static let dashComment: Set<String> = ["sql", "lua", "haskell", "hs"]
    private static let noSlashComment: Set<String> = ["python", "py", "sh", "bash", "zsh", "shell", "yaml", "yml", "toml", "ini", "conf", "make", "makefile", "dockerfile", "ruby", "rb", "r", "perl", "pl", "sql", "lua", "haskell", "hs", "json", "markdown", "md", "text", "txt"]

    private static let keywords: Set<String> = [
        "func", "function", "fn", "def", "let", "var", "const", "val", "if", "else", "elif", "for", "foreach", "while", "do", "loop",
        "return", "class", "struct", "enum", "protocol", "extension", "interface", "type", "trait", "impl", "import", "from", "export",
        "package", "use", "using", "module", "namespace", "in", "of", "is", "as", "not", "and", "or", "switch", "case", "default",
        "match", "when", "where", "break", "continue", "try", "catch", "except", "finally", "throw", "throws", "raise", "guard",
        "public", "private", "protected", "internal", "static", "final", "override", "async", "await", "yield", "new", "delete",
        "extends", "implements", "with", "lambda", "pub", "mut", "ref", "mod", "init", "self", "this", "super", "select", "insert",
        "update", "create", "table", "join", "group", "order", "by", "limit", "then", "end", "begin", "fi", "esac", "done", "echo",
    ]
    private static let literals: Set<String> = ["true", "false", "nil", "null", "none", "undefined", "nan"]

    private static func lexCode(_ line: String, at base: Int, lang: String, inBlockComment: inout Bool, into spans: inout [Span]) {
        let chars = Array(line.utf16)
        let n = chars.count
        let hash = hashComment.contains(lang)
        let dash = dashComment.contains(lang)
        let slash = !noSlashComment.contains(lang)
        let unknownLang = lang.isEmpty
        func add(_ s: Int, _ e: Int, _ t: Token) { spans.append(Span(range: NSRange(location: base + s, length: e - s), token: t)) }
        func at(_ i: Int) -> UInt16 { i < n ? chars[i] : 0 }
        func isIdent(_ c: UInt16) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 }

        var i = 0
        if inBlockComment {
            var j = 0
            while j < n - 1 && !(chars[j] == 42 && chars[j + 1] == 47) { j += 1 }
            if j < n - 1 { add(0, j + 2, .comment); inBlockComment = false; i = j + 2 } else { add(0, n, .comment); return }
        }
        while i < n {
            let c = chars[i]
            if (slash && c == 47 && at(i + 1) == 47) || ((hash || unknownLang && at(i + 1) == 32) && c == 35) || (dash && c == 45 && at(i + 1) == 45) {
                add(i, n, .comment); return
            }
            if slash && c == 47 && at(i + 1) == 42 {
                var j = i + 2
                while j < n - 1 && !(chars[j] == 42 && chars[j + 1] == 47) { j += 1 }
                if j < n - 1 { add(i, j + 2, .comment); i = j + 2; continue }
                add(i, n, .comment); inBlockComment = true; return
            }
            if c == 34 || c == 39 || c == 96 {
                var j = i + 1
                while j < n && chars[j] != c { j += chars[j] == 92 ? 2 : 1 }
                let end = min(j + 1, n)
                add(i, end, .string); i = end; continue
            }
            if c >= 48 && c <= 57 {
                var j = i + 1
                while j < n && (isIdent(chars[j]) || chars[j] == 46) { j += 1 }
                add(i, j, .number); i = j; continue
            }
            if isIdent(c) {
                var j = i + 1
                while j < n && isIdent(chars[j]) { j += 1 }
                let word = String(utf16CodeUnits: Array(chars[i..<j]), count: j - i)
                let lower = word.lowercased()
                if literals.contains(lower) { add(i, j, .number) }
                else if keywords.contains(word) || keywords.contains(lower) && lang == "sql" { add(i, j, .keyword) }
                else if at(j) == 40 { add(i, j, .title) }
                else if let f = word.unicodeScalars.first, f.properties.isUppercase { add(i, j, .type) }
                i = j; continue
            }
            i += 1
        }
    }
}
