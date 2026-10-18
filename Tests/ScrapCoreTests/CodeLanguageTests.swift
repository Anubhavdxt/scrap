import XCTest
@testable import ScrapCore

final class CodeLanguageTests: XCTestCase {
    /// The (text, token) pairs for the code inside a fenced block of `lang`.
    private func tokens(_ lang: String, _ code: String) -> [(String, Token)] {
        let text = "```\(lang)\n\(code)\n```"
        let ns = text as NSString
        return MarkdownHighlighter.spans(in: text)
            .map { (ns.substring(with: $0.range), $0.token) }
            .filter { !$0.0.hasPrefix("```") }
    }

    private func has(_ t: [(String, Token)], _ text: String, _ token: Token, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(t.contains { $0.0 == text && $0.1 == token }, "expected \(text) as \(token) in \(t.map { "\($0.0):\($0.1)" })", file: file, line: line)
    }

    private func lacks(_ t: [(String, Token)], _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(t.contains { $0.0 == text }, "did not expect \(text) in \(t.map { "\($0.0):\($0.1)" })", file: file, line: line)
    }

    func testLanguageLookup() {
        XCTAssertEqual(CodeLanguage.forFence("swift").names.first, "swift")
        XCTAssertEqual(CodeLanguage.forFence("TS").names.first, "javascript")
        XCTAssertEqual(CodeLanguage.forFence("python {linenos}").names.first, "python")
        XCTAssertEqual(CodeLanguage.forFence("").names, [], "no language: generic")
        XCTAssertEqual(CodeLanguage.forFence("klingon").names, [])
    }

    func testSwift() {
        let t = tokens("swift", "@MainActor func go(_ x: Int) -> String { return \"hi\\(x)\" } // done")
        has(t, "@MainActor", .attr); has(t, "func", .keyword); has(t, "go", .title); has(t, "Int", .builtin)
        has(t, "String", .builtin); has(t, "return", .keyword); has(t, "\"hi\\(x)\"", .string); has(t, "// done", .comment)
        has(tokens("swift", "#if DEBUG"), "#if", .attr)
        has(tokens("swift", "let s = \"\"\"\nline\n\"\"\""), "line", .string)
    }

    func testJavaScriptAndTypeScript() {
        let t = tokens("ts", "export async function load(id: string): Promise<User> { return fetch(`/u/${id}`) } /* c */")
        has(t, "export", .keyword); has(t, "async", .keyword); has(t, "function", .keyword); has(t, "load", .title)
        has(t, "string", .builtin); has(t, "Promise", .builtin); has(t, "User", .type); has(t, "`/u/${id}`", .string); has(t, "/* c */", .comment)
        has(tokens("js", "const x = undefined; // n"), "undefined", .number)
        has(tokens("js", "const a = `one\ntwo`"), "two`", .string)
    }

    func testPython() {
        let t = tokens("python", "@app.route('/')\ndef f(self, n=3):  # why\n    return None if n else True")
        has(t, "@app", .attr); has(t, "def", .keyword); has(t, "f", .title); has(t, "3", .number); has(t, "# why", .comment)
        has(t, "return", .keyword); has(t, "None", .number); has(t, "if", .keyword); has(t, "True", .number); has(t, "'/'", .string)
        let doc = tokens("py", "\"\"\"doc\nstring\"\"\"\nx = 1")
        has(doc, "string\"\"\"", .string); has(doc, "1", .number)
    }

    func testShell() {
        let t = tokens("bash", "if [ -f \"$HOME/x\" ]; then echo ${NAME} --verbose -n $1 # note; fi")
        has(t, "if", .keyword); has(t, "-f", .attr); has(t, "then", .keyword); has(t, "echo", .builtin); has(t, "${NAME}", .variable)
        has(t, "--verbose", .attr); has(t, "-n", .attr); has(t, "$1", .variable); has(t, "# note; fi", .comment); has(t, "\"$HOME/x\"", .string)
        lacks(tokens("sh", "echo a#b $#"), "#b $#")
    }

    func testJSON() {
        let t = tokens("json", "{ \"name\": \"scrap\", \"n\": -12.5, \"ok\": true, \"none\": null }")
        has(t, "\"name\"", .attr); has(t, "\"scrap\"", .string); has(t, "12.5", .number); has(t, "true", .number); has(t, "null", .number)
        has(t, "\"ok\"", .attr)
    }

    func testSQLIsCaseInsensitive() {
        let t = tokens("sql", "SELECT id, name FROM users WHERE age > 21 AND active = TRUE -- adults")
        has(t, "SELECT", .keyword); has(t, "FROM", .keyword); has(t, "WHERE", .keyword); has(t, "AND", .keyword); has(t, "21", .number)
        has(t, "TRUE", .number); has(t, "-- adults", .comment)
        has(tokens("sql", "create table t (id int primary key, name varchar(20));"), "int", .type)
        has(tokens("sql", "select 'it''s'"), "'it'", .string)
    }

    func testGo() {
        let t = tokens("go", "func (s *Server) Run() error { return nil } // ok")
        has(t, "func", .keyword); has(t, "Run", .title); has(t, "error", .builtin); has(t, "return", .keyword); has(t, "nil", .number)
        has(tokens("go", "x := `raw\nmore`"), "more`", .string)
    }

    func testRust() {
        let t = tokens("rust", "#[derive(Debug)]\nfn first<'a>(v: &'a Vec<u8>) -> Option<&'a u8> { println!(\"{}\", 'x'); v.get(0) }")
        has(t, "#[derive(Debug)]", .attr); has(t, "fn", .keyword); has(t, "'a", .attr); has(t, "Vec", .builtin); has(t, "u8", .builtin)
        has(t, "println!", .title); has(t, "'x'", .string); has(t, "get", .title)
    }

    func testCAndCpp() {
        let t = tokens("c", "#include <stdio.h>\nint main(void) { printf(\"hi\\n\"); return 0; } /* end */")
        has(t, "#include", .attr); has(t, "int", .builtin); has(t, "main", .title); has(t, "void", .keyword); has(t, "printf", .title)
        has(t, "\"hi\\n\"", .string); has(t, "return", .keyword); has(t, "0", .number); has(t, "/* end */", .comment)
    }

    func testJavaAndKotlin() {
        let t = tokens("java", "@Override public static void main(String[] args) { new Thread().start(); }")
        has(t, "@Override", .attr); has(t, "public", .keyword); has(t, "static", .keyword); has(t, "String", .builtin); has(t, "new", .keyword)
        has(tokens("kotlin", "fun add(a: Int) = a + 1"), "fun", .keyword)
    }

    func testRuby() {
        let t = tokens("ruby", "class Foo < Bar\n  def hi(name) puts :sym, @var end\nend # done")
        has(t, "class", .keyword); has(t, "Foo", .type); has(t, "def", .keyword); has(t, ":sym", .attr); has(t, "@var", .variable); has(t, "# done", .comment)
    }

    func testHTML() {
        let t = tokens("html", "<div class=\"box\" data-id='7'><a href=\"/x\">hi</a><!-- note --><br/></div>")
        has(t, "<div", .keyword); has(t, "class", .attr); has(t, "\"box\"", .string); has(t, "data-id", .attr); has(t, "<a", .keyword)
        has(t, "</a", .keyword); has(t, "<!-- note -->", .comment); has(t, "/>", .keyword)
        lacks(t, "hi")
    }

    func testHTMLMultilineTagAndComment() {
        let t = tokens("xml", "<item\n  id=\"1\"\n>\n<!-- a\nb -->")
        has(t, "<item", .keyword); has(t, "id", .attr); has(t, "\"1\"", .string); has(t, ">", .keyword); has(t, "b -->", .comment)
    }

    func testCSS() {
        let t = tokens("css", "@media (min-width: 40em) {\n.card:hover { color: #1f4663; margin: 0 -4px; --gap: 1rem; background: url(x.png) !important; }\n}")
        has(t, "@media", .keyword); has(t, "min-width", .attr); has(t, "40em", .number); has(t, ".card", .title); has(t, ":hover", .attr)
        has(t, "color", .attr); has(t, "#1f4663", .number); has(t, "margin", .attr); has(t, "-4px", .number); has(t, "--gap", .variable)
        has(t, "1rem", .number); has(t, "url", .title); has(t, "!important", .keyword) // `!important` is one token
    }

    func testMinifiedCSSAndKeyframes() {
        let t = tokens("css", "a{color:red;margin:0}\n@keyframes spin { from { opacity:0 } to { opacity:1 } }\nb::before { content: \"x\" }")
        has(t, "color", .attr); has(t, "margin", .attr); has(t, "opacity", .attr); has(t, "::before", .attr); has(t, "content", .attr)
        has(t, "\"x\"", .string)
    }

    func testYAML() {
        let t = tokens("yaml", "name: scrap  # app\nitems:\n  - id: 1\n    ok: true\n  - \"quoted key\": 'x'\nref: *base")
        has(t, "name", .attr); has(t, "# app", .comment); has(t, "items", .attr); has(t, "id", .attr); has(t, "1", .number)
        has(t, "ok", .attr); has(t, "true", .number); has(t, "\"quoted key\"", .attr); has(t, "'x'", .string); has(t, "*base", .variable)
        has(tokens("yml", "---"), "---", .comment)
        lacks(tokens("yaml", "url: http://x.y/z"), "url:")
    }

    func testTOMLAndINI() {
        let t = tokens("toml", "[package]\nname = \"scrap\"\nversion = '1.0'\nenabled = true\n# c")
        has(t, "[package]", .title); has(t, "name", .attr); has(t, "\"scrap\"", .string); has(t, "version", .attr); has(t, "true", .number); has(t, "# c", .comment)
        has(tokens("ini", "; note\nkey=value"), "; note", .comment)
    }

    func testDiff() {
        let t = tokens("diff", "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n-old\n+new\n context")
        has(t, "diff --git a/x b/x", .comment); has(t, "--- a/x", .comment); has(t, "@@ -1,2 +1,2 @@", .keyword)
        has(t, "-old", .deletion); has(t, "+new", .string); lacks(t, " context")
    }

    func testDockerfileAndMakefile() {
        let t = tokens("dockerfile", "FROM swift:6 AS build\nRUN make $TARGET # build")
        has(t, "FROM", .keyword); has(t, "AS", .keyword); has(t, "RUN", .keyword); has(t, "$TARGET", .variable); has(t, "# build", .comment)
    }

    func testUnknownLanguageUsesTheGenericLexer() {
        let t = tokens("klingon", "func x() { return \"a\" } // c")
        has(t, "func", .keyword); has(t, "x", .title); has(t, "\"a\"", .string); has(t, "// c", .comment)
        let none = tokens("", "let n = 42 # not a comment")
        has(none, "42", .number); has(none, "# not a comment", .comment)
    }

    func testStateDoesNotLeakOutOfAFence() {
        let text = "```c\n/* open\n```\nafter **bold**\n```py\nx = 1\n```"
        let ns = text as NSString
        let t = MarkdownHighlighter.spans(in: text).map { (ns.substring(with: $0.range), $0.token) }
        has(t, "**bold**", .keyword)
        has(t, "1", .number)
    }

    func testUnicodeAndLongLinesDoNotCrash() {
        let long = String(repeating: "x = \"héllo ☕\" # ✓ ", count: 2000)
        _ = tokens("python", long)
        _ = tokens("css", "é { ☕: 1px }")
        _ = tokens("html", "<é attr='☕'>")
        _ = tokens("yaml", "ключ: значение")
        XCTAssertTrue(true)
    }
}
