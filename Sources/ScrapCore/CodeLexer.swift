import Foundation

/// Lexer state carried from one line of a fenced code block to the next.
struct LexState {
    enum Mode: Equatable {
        case none
        case blockComment(end: String)
        case string(end: String, escapes: Bool)
    }
    var mode = Mode.none
    var cssBlocks: [Bool] = []        // CSS: open blocks, true for containers like @media, false for declaration blocks
    var cssPendingContainer = false   // CSS: an @media-style prelude is waiting for its `{`
    var inTag = false    // HTML: inside `<tag ...`, possibly across lines
}

enum CodeLexer {
    static func lex(_ line: String, at base: Int, language: CodeLanguage, state: inout LexState, into spans: inout [Span]) {
        var lexer = LineLexer(chars: Array(line.utf16), base: base, lang: language, state: state)
        lexer.run()
        state = lexer.state
        spans += lexer.spans
    }
}

private struct LineLexer {
    enum Step { case none, advanced, finished }

    let chars: [UInt16]
    let base: Int
    let lang: CodeLanguage
    var state: LexState
    var spans: [Span] = []

    init(chars: [UInt16], base: Int, lang: CodeLanguage, state: LexState) {
        self.chars = chars
        self.base = base
        self.lang = lang
        self.state = state
    }

    private var n: Int { chars.count }

    // MARK: Helpers

    mutating func add(_ start: Int, _ end: Int, _ token: Token) {
        if end > start { spans.append(Span(range: NSRange(location: base + start, length: end - start), token: token)) }
    }

    func has(_ needle: String, at i: Int) -> Bool {
        guard i >= 0 else { return false }
        var k = 0
        for unit in needle.utf16 {
            guard i + k < n, chars[i + k] == unit else { return false }
            k += 1
        }
        return true
    }

    func find(_ needle: String, from i: Int) -> Int? {
        var j = i
        while j < n { if has(needle, at: j) { return j }; j += 1 }
        return nil
    }

    func at(_ i: Int) -> UInt16 { i >= 0 && i < n ? chars[i] : 0 }
    func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
    func isSpace(_ c: UInt16) -> Bool { c == 32 || c == 9 }
    func isLetter(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
    func isIdentStart(_ c: UInt16) -> Bool { isLetter(c) || c == 95 || c > 127 }
    func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || isDigit(c) }
    func isHex(_ c: UInt16) -> Bool { isDigit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102) }
    func text(_ s: Int, _ e: Int) -> String { String(utf16CodeUnits: Array(chars[s..<e]), count: e - s) }

    /// Skips spaces; returns the index of the next non-space.
    func skipSpaces(_ i: Int) -> Int {
        var j = i
        while j < n && isSpace(chars[j]) { j += 1 }
        return j
    }

    // MARK: Entry

    mutating func run() {
        if lang.kind == .diff { return lexDiff() }
        guard let start = resumeMode() else { return }
        switch lang.kind {
        case .code, .json: lexCode(from: start)
        case .html: lexHTML(from: start)
        case .css: lexCSS(from: start)
        case .yaml: lexKeyed(from: start, yaml: true)
        case .toml: lexKeyed(from: start, yaml: false)
        case .diff: break
        }
    }

    /// Continues a block comment or multi-line string from the previous line. nil when this whole line is inside it.
    mutating func resumeMode() -> Int? {
        switch state.mode {
        case .none:
            return 0
        case .blockComment(let end):
            if let e = find(end, from: 0) {
                let stop = e + end.utf16.count
                add(0, stop, .comment)
                state.mode = .none
                return stop
            }
            add(0, n, .comment)
            return nil
        case .string(let end, let escapes):
            var j = 0
            while j < n {
                if escapes && chars[j] == 92 { j += 2; continue }
                if has(end, at: j) {
                    let stop = j + end.utf16.count
                    add(0, stop, .string)
                    state.mode = .none
                    return stop
                }
                j += 1
            }
            add(0, n, .string)
            return nil
        }
    }

    // MARK: Comments and strings (shared)

    /// Handles a comment or string starting at `i`. `.finished` means the rest of the line is consumed.
    mutating func commentOrString(_ i: inout Int) -> Step {
        for comment in lang.lineComments where has(comment, at: i) {
            if lang.commentNeedsBoundary && i > 0 && !isSpace(chars[i - 1]) { continue }
            add(i, n, .comment)
            return .finished
        }
        if let block = lang.blockComment, has(block.start, at: i) {
            let from = i + block.start.utf16.count
            if let e = find(block.end, from: from) {
                let stop = e + block.end.utf16.count
                add(i, stop, .comment)
                i = stop
                return .advanced
            }
            add(i, n, .comment)
            state.mode = .blockComment(end: block.end)
            return .finished
        }
        for rule in lang.strings where has(rule.open, at: i) {
            var j = i + rule.open.utf16.count
            var closed = false
            while j < n {
                if rule.escapes && chars[j] == 92 { j += 2; continue }
                if has(rule.close, at: j) { closed = true; break }
                j += 1
            }
            if closed {
                let stop = j + rule.close.utf16.count
                // JSON: a string followed by a colon is a key.
                let isKey = lang.kind == .json && at(skipSpaces(stop)) == 58
                add(i, stop, isKey ? .attr : .string)
                i = stop
                return .advanced
            }
            add(i, n, .string)
            if rule.multiline { state.mode = .string(end: rule.close, escapes: rule.escapes) }
            return .finished
        }
        return .none
    }

    // MARK: General code

    mutating func lexCode(from start: Int) {
        var i = start
        while i < n {
            // Rust lifetimes: 'a (but not the char literal 'a'). Checked before strings, which would claim the quote.
            if lang.lifetimes && chars[i] == 39 && isIdentStart(at(i + 1)) {
                var k = i + 1
                while k < n && isIdent(chars[k]) { k += 1 }
                if at(k) != 39 { add(i, k, .attr); i = k; continue }
            }
            switch commentOrString(&i) {
            case .finished: return
            case .advanced: continue
            case .none: break
            }
            let c = chars[i]

            // C preprocessor: `#include` at the start of a line.
            if lang.directives && c == 35 && skipSpaces(0) == i {
                var j = i + 1
                while j < n && isIdent(chars[j]) { j += 1 }
                add(i, j, .attr)
                i = j
                continue
            }

            // Numbers.
            if isDigit(c) && (i == 0 || !isIdent(chars[i - 1])) {
                var j = i + 1
                while j < n && (isIdent(chars[j]) || (chars[j] == 46 && at(j + 1) != 46)) { j += 1 }
                add(i, j, .number)
                i = j
                continue
            }

            // Shell flags: -x, --long.
            if lang.flags && c == 45 && (i == 0 || isSpace(chars[i - 1])) && (isLetter(at(i + 1)) || at(i + 1) == 45) {
                var j = i + 1
                while j < n && (isIdent(chars[j]) || chars[j] == 45) { j += 1 }
                add(i, j, .attr)
                i = j
                continue
            }

            // Sigils: @attr, $var, #[derive], :symbol, &anchor.
            if c < 128, let token = lang.sigils[Character(UnicodeScalar(UInt8(c)))], sigil(c, token, at: &i) { continue }

            // Words.
            if isIdentStart(c) {
                var j = i + 1
                while j < n && isIdent(chars[j]) { j += 1 }
                if lang.macros && at(j) == 33 && [40, 91, 123].contains(at(j + 1)) {
                    add(i, j + 1, .title)
                    i = j + 1
                    continue
                }
                if let token = classify(text(i, j), followedByCall: at(j) == 40) { add(i, j, token) }
                i = j
                continue
            }
            i += 1
        }
    }

    private mutating func sigil(_ c: UInt16, _ token: Token, at i: inout Int) -> Bool {
        let boundary = i == 0 || isSpace(chars[i - 1])
        let next = at(i + 1)
        switch c {
        case 35 where next == 91: // #[attribute]
            let end = find("]", from: i).map { $0 + 1 } ?? n
            add(i, end, token); i = end; return true
        case 36 where next == 123: // ${var}
            let end = find("}", from: i).map { $0 + 1 } ?? n
            add(i, end, token); i = end; return true
        case 36 where isDigit(next) || [64, 42, 63, 33, 36].contains(next): // $1 $@ $* $? $! $$
            add(i, i + 2, token); i += 2; return true
        case 58, 38, 42: // : & * need to start a word
            guard boundary, isIdentStart(next) else { return false }
        default:
            guard isIdentStart(next) else { return false }
        }
        var j = i + 1
        while j < n && isIdent(chars[j]) { j += 1 }
        add(i, j, token)
        i = j
        return true
    }

    private func classify(_ word: String, followedByCall: Bool) -> Token? {
        let key = lang.caseInsensitive ? word.lowercased() : word
        if lang.literals.contains(key) { return .number }
        if lang.keywords.contains(key) { return .keyword }
        if lang.types.contains(key) { return .type }
        if lang.builtins.contains(key) { return .builtin }
        if lang.callsAreTitles && followedByCall { return .title }
        if lang.capitalizedAreTypes, let first = word.unicodeScalars.first, first.properties.isUppercase,
           word.unicodeScalars.contains(where: { $0.properties.isLowercase }) {
            return .type
        }
        return nil
    }

    // MARK: Diff

    mutating func lexDiff() {
        guard n > 0 else { return }
        let token: Token?
        if has("+++", at: 0) || has("---", at: 0) || has("diff ", at: 0) || has("index ", at: 0) { token = .comment }
        else if has("@@", at: 0) { token = .keyword }
        else if chars[0] == 43 { token = .string }
        else if chars[0] == 45 { token = .deletion }
        else { token = nil }
        if let token { add(0, n, token) }
    }

    // MARK: HTML and XML

    mutating func lexHTML(from start: Int) {
        var i = start
        while i < n {
            let c = chars[i]
            if state.inTag {
                if c == 62 { add(i, i + 1, .keyword); state.inTag = false; i += 1; continue }
                if c == 47 && at(i + 1) == 62 { add(i, i + 2, .keyword); state.inTag = false; i += 2; continue }
                if c == 34 || c == 39 {
                    var j = i + 1
                    while j < n && chars[j] != c { j += 1 }
                    let end = min(j + 1, n)
                    add(i, end, .string)
                    i = end
                    continue
                }
                if isIdentStart(c) || c == 64 || c == 58 {
                    var j = i + 1
                    while j < n && (isIdent(chars[j]) || [45, 58, 46, 64].contains(chars[j])) { j += 1 }
                    add(i, j, .attr)
                    i = j
                    continue
                }
                i += 1
                continue
            }
            if has("<!--", at: i) {
                if let e = find("-->", from: i + 4) { add(i, e + 3, .comment); i = e + 3; continue }
                add(i, n, .comment)
                state.mode = .blockComment(end: "-->")
                return
            }
            if c == 60 {
                var j = i + 1
                if at(j) == 47 || at(j) == 33 || at(j) == 63 { j += 1 }
                if isIdentStart(at(j)) {
                    while j < n && (isIdent(chars[j]) || chars[j] == 45 || chars[j] == 58) { j += 1 }
                    add(i, j, .keyword)
                    state.inTag = true
                    i = j
                    continue
                }
            }
            i += 1
        }
    }

    // MARK: CSS, SCSS

    mutating func lexCSS(from start: Int) {
        var i = start
        var parens = 0
        let containers: Set<String> = ["media", "supports", "layer", "container", "keyframes", "-webkit-keyframes", "document", "-moz-document", "scope", "starting-style"]
        while i < n {
            switch commentOrString(&i) {
            case .finished: return
            case .advanced: continue
            case .none: break
            }
            let c = chars[i]
            let inRule = state.cssBlocks.last == false
            let wantsProperty = inRule || parens > 0

            if c == 123 { state.cssBlocks.append(state.cssPendingContainer); state.cssPendingContainer = false; i += 1; continue }
            if c == 125 { _ = state.cssBlocks.popLast(); i += 1; continue }
            if c == 59 { state.cssPendingContainer = false; i += 1; continue }
            if c == 40 { parens += 1 }
            if c == 41 { parens = max(0, parens - 1) }

            if c == 64 && isIdentStart(at(i + 1)) { // @media, @include
                var j = i + 1
                while j < n && (isIdent(chars[j]) || chars[j] == 45) { j += 1 }
                add(i, j, .keyword)
                if containers.contains(text(i + 1, j)) { state.cssPendingContainer = true }
                i = j
                continue
            }
            if c == 33 && isLetter(at(i + 1)) { // !important
                var j = i + 1
                while j < n && isLetter(chars[j]) { j += 1 }
                add(i, j, .keyword)
                i = j
                continue
            }
            if c == 35 { // #fff colour inside a rule, #id selector outside
                var j = i + 1
                if inRule {
                    while j < n && isHex(chars[j]) && j - i <= 8 { j += 1 }
                    if j > i + 1 { add(i, j, .number) }
                } else {
                    while j < n && (isIdent(chars[j]) || chars[j] == 45) { j += 1 }
                    add(i, j, .title)
                }
                i = max(j, i + 1)
                continue
            }
            if c == 46 && isIdentStart(at(i + 1)) && !inRule { // .class selector
                var j = i + 1
                while j < n && (isIdent(chars[j]) || chars[j] == 45) { j += 1 }
                add(i, j, .title)
                i = j
                continue
            }
            if c == 58 && !inRule && isIdentStart(at(i + 1 + (at(i + 1) == 58 ? 1 : 0))) { // :hover, ::before
                var j = i + 1
                while j < n && (isIdent(chars[j]) || chars[j] == 45 || chars[j] == 58) { j += 1 }
                add(i, j, .attr)
                i = j
                continue
            }
            if isDigit(c) || (c == 46 && isDigit(at(i + 1))) || (c == 45 && isDigit(at(i + 1)) && inRule) {
                var j = i + 1
                while j < n && (isDigit(chars[j]) || chars[j] == 46) { j += 1 }
                while j < n && (isLetter(chars[j]) || chars[j] == 37) { j += 1 } // units: px, em, %
                add(i, j, .number)
                i = j
                continue
            }
            if isIdentStart(c) || (c == 45 && (isIdentStart(at(i + 1)) || at(i + 1) == 45)) {
                var j = i + 1
                while j < n && (isIdent(chars[j]) || chars[j] == 45) { j += 1 }
                let word = text(i, j)
                let after = skipSpaces(j)
                if word.hasPrefix("--") { add(i, j, .variable) }
                else if wantsProperty && at(after) == 58 && at(after + 1) != 58 {
                    add(i, j, .attr) // property name
                } else if at(j) == 40 { add(i, j, .title) }
                i = j
                continue
            }
            i += 1
        }
    }

    // MARK: YAML and TOML (a key, then ordinary values)

    mutating func lexKeyed(from start: Int, yaml: Bool) {
        guard start == 0 else { return lexCode(from: start) }
        var p = skipSpaces(0)
        if yaml {
            if has("---", at: p) || has("...", at: p) { add(p, n, .comment); return }
            while has("- ", at: p) { p = skipSpaces(p + 1) } // list markers
            if let colon = yamlKeyEnd(from: p) {
                add(p, colon, .attr)
                return lexCode(from: colon + 1)
            }
        } else {
            if at(p) == 91 { // [table] and [[array of tables]]
                let end = find("]", from: p).map { $0 + 1 + (at($0 + 1) == 93 ? 1 : 0) } ?? n
                add(p, end, .title)
                return lexCode(from: end)
            }
            if let eq = find("=", from: p), eq > p {
                var e = eq
                while e > p && isSpace(chars[e - 1]) { e -= 1 }
                let key = chars[p..<e]
                if !key.contains(where: { isSpace($0) && !(key.first == 34 || key.first == 39) }) && ![35, 59].contains(at(p)) {
                    add(p, e, .attr)
                    return lexCode(from: eq + 1)
                }
            }
        }
        lexCode(from: start)
    }

    /// Index of the colon ending a YAML key that starts at `p`, if the text there is a key.
    private func yamlKeyEnd(from p: Int) -> Int? {
        guard p < n, chars[p] != 35 else { return nil }
        if chars[p] == 34 || chars[p] == 39 {
            var j = p + 1
            while j < n && chars[j] != chars[p] { j += 1 }
            return at(j + 1) == 58 && (j + 2 >= n || isSpace(at(j + 2))) ? j + 1 : nil
        }
        var j = p
        while j < n {
            let c = chars[j]
            if c == 58 && (j + 1 >= n || isSpace(chars[j + 1])) { return j > p ? j : nil }
            if c == 35 && j > p && isSpace(chars[j - 1]) { return nil }
            if [123, 91, 34, 39].contains(c) && j == p { return nil }
            j += 1
        }
        return nil
    }
}
