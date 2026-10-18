import Foundation

/// How a fenced code block's language is lexed. Data-driven: most languages are a list of comment and string
/// delimiters plus keyword sets; a few (JSON, HTML, CSS, YAML, TOML, diff) have a small special lexer.
struct CodeLanguage {
    enum Kind { case code, json, html, css, yaml, toml, diff }
    struct StringRule {
        var open: String
        var close: String
        var escapes = true
        var multiline = false
    }

    var names: [String]
    var kind = Kind.code
    var lineComments: [String] = []
    /// A `#` comment must start a word (shell: `$#` and `a#b` are not comments).
    var commentNeedsBoundary = false
    var blockComment: (start: String, end: String)?
    /// Longest openers first (for example `"""` before `"`).
    var strings: [StringRule] = []
    var keywords: Set<String> = []
    var types: Set<String> = []
    var builtins: Set<String> = []
    var literals: Set<String> = ["true", "false", "null", "nil"]
    var caseInsensitive = false
    var capitalizedAreTypes = true
    var callsAreTitles = true
    /// A sigil followed by a word styles the whole thing, for example `@available` or `$HOME`.
    var sigils: [Character: Token] = [:]
    var flags = false              // shell: `-x` and `--long`
    var lifetimes = false          // Rust: `'a`
    var macros = false             // Rust: `println!`
    var directives = false         // C: `#include` at the start of a line

    // MARK: Lookup

    static func forFence(_ info: String) -> CodeLanguage {
        let word = info.split(whereSeparator: { $0 == " " || $0 == "{" || $0 == "\t" }).first.map { $0.lowercased() } ?? ""
        return byName[word] ?? generic
    }

    private static let byName: [String: CodeLanguage] = {
        var map: [String: CodeLanguage] = [:]
        for language in all { for name in language.names { map[name] = language } }
        return map
    }()

    private static func words(_ s: String) -> Set<String> { Set(s.split(whereSeparator: \.isWhitespace).map(String.init)) }
    private static let dq = StringRule(open: "\"", close: "\"")
    private static let sq = StringRule(open: "'", close: "'")
    private static let backtick = StringRule(open: "`", close: "`", multiline: true)
    private static let slashes = ["//"]
    private static let cBlock: (start: String, end: String) = ("/*", "*/")

    /// Unknown or missing language: what the old generic lexer did.
    static let generic = CodeLanguage(
        names: [], lineComments: ["//", "# "], blockComment: cBlock, strings: [dq, sq, backtick],
        keywords: words("""
            func function fn def let var const val if else elif for foreach while do loop return class struct enum protocol \
            extension interface type trait impl import from export package use using module namespace in of is as not and or \
            switch case default match when where break continue try catch except finally throw throws raise guard public \
            private protected internal static final override async await yield new delete extends implements with lambda \
            pub mut ref mod init self this super
            """)
    )

    static let all: [CodeLanguage] = [
        CodeLanguage(
            names: ["swift"], lineComments: slashes, blockComment: cBlock,
            strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true), dq],
            keywords: words("""
                associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private \
                precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default \
                defer do else fallthrough for guard if in repeat return throw switch where while as await async actor any some try \
                throws is self Self super nonisolated mutating nonmutating override final lazy weak unowned convenience required \
                optional indirect isolated get set willSet didSet
                """),
            builtins: words("Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Double Float String Bool Character Array Dictionary Set Optional Any AnyObject Void Never Result Data Date URL"),
            sigils: ["@": .attr, "#": .attr]),

        CodeLanguage(
            names: ["javascript", "js", "jsx", "mjs", "cjs", "typescript", "ts", "tsx"],
            lineComments: slashes, blockComment: cBlock, strings: [dq, sq, backtick],
            keywords: words("""
                break case catch class const continue debugger default delete do else export extends finally for function if \
                import in instanceof let new return super switch this throw try typeof var void while with yield async await of \
                static get set interface type enum implements namespace declare abstract readonly public private protected as \
                from satisfies keyof is
                """),
            builtins: words("string number boolean any unknown never object symbol bigint Promise Array Map Set Record console Math JSON Object"),
            literals: ["true", "false", "null", "undefined", "NaN", "Infinity"], sigils: ["@": .attr]),

        CodeLanguage(
            names: ["python", "py", "python3"], lineComments: ["#"],
            strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true), StringRule(open: "'''", close: "'''", multiline: true), dq, sq],
            keywords: words("""
                and as assert async await break class continue def del elif else except finally for from global if import in is \
                lambda nonlocal not or pass raise return try while with yield match case
                """),
            builtins: words("int str float bool list dict set tuple bytes object type print len range open super isinstance enumerate zip map filter sorted"),
            literals: ["True", "False", "None"], sigils: ["@": .attr]),

        CodeLanguage(
            names: ["bash", "sh", "shell", "zsh", "console", "terminal"], lineComments: ["#"], commentNeedsBoundary: true,
            strings: [dq, sq],
            keywords: words("if then else elif fi for while until do done case esac in function select time return exit break continue local export readonly declare unset alias source set shift"),
            builtins: words("echo cd pwd ls cat grep sed awk printf read test eval exec trap kill wait brew git make curl sudo rm cp mv mkdir touch chmod find xargs tar swift"),
            capitalizedAreTypes: false, callsAreTitles: false, sigils: ["$": .variable], flags: true),

        CodeLanguage(names: ["json", "jsonc", "json5"], kind: .json, lineComments: slashes, blockComment: cBlock, strings: [dq]),

        CodeLanguage(
            names: ["sql", "postgresql", "postgres", "mysql", "sqlite", "plsql"], lineComments: ["--"], blockComment: cBlock, strings: [sq],
            keywords: words("""
                select from where join inner left right outer full cross on group by order having limit offset insert into values \
                update set delete create alter drop table index view database schema primary key foreign references unique not default \
                and or in is like ilike between exists union all distinct as case when then else end begin commit rollback with returning \
                cascade add column constraint check if using asc desc over partition rows
                """),
            types: words("int integer bigint smallint text varchar char boolean bool date time timestamp timestamptz numeric decimal float double serial uuid json jsonb"),
            caseInsensitive: true, capitalizedAreTypes: false),

        CodeLanguage(
            names: ["go", "golang"], lineComments: slashes, blockComment: cBlock, strings: [dq, backtick, sq],
            keywords: words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
            builtins: words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 string bool byte rune error any make new len cap append copy panic recover"),
            literals: ["true", "false", "nil", "iota"]),

        CodeLanguage(
            names: ["rust", "rs"], lineComments: slashes, blockComment: cBlock, strings: [dq, sq],
            keywords: words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while"),
            builtins: words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result Box Some None Ok Err"),
            literals: ["true", "false"], sigils: ["#": .attr], lifetimes: true, macros: true),

        CodeLanguage(
            names: ["c", "h", "cpp", "c++", "cc", "cxx", "hpp", "objc", "objective-c", "m", "mm"], lineComments: slashes, blockComment: cBlock, strings: [dq, sq],
            keywords: words("""
                auto break case const continue default do else enum extern for goto if inline register return signed sizeof static \
                struct switch typedef union unsigned volatile while class namespace template typename public private protected virtual \
                new delete using this operator friend explicit constexpr override final try catch throw void
                """),
            builtins: words("int char short long float double bool size_t uint8_t uint16_t uint32_t uint64_t int8_t int16_t int32_t int64_t string vector map"),
            literals: ["true", "false", "NULL", "nullptr"], directives: true),

        CodeLanguage(
            names: ["java", "kotlin", "kt", "scala", "csharp", "cs", "c#", "dart"], lineComments: slashes, blockComment: cBlock, strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true), dq, sq],
            keywords: words("""
                abstract assert break case catch class const continue default do else enum extends final finally for goto if implements \
                import instanceof interface native new package private protected public return static super switch synchronized this \
                throw throws transient try void volatile while var val fun when object companion data sealed override open internal \
                lateinit suspend in is as namespace using readonly sealed record async await get set
                """),
            builtins: words("int long short byte float double boolean char String Integer Long Double Boolean Object List Map Set string bool"),
            literals: ["true", "false", "null"], sigils: ["@": .attr]),

        CodeLanguage(
            names: ["ruby", "rb"], lineComments: ["#"], strings: [dq, sq],
            keywords: words("alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require include extend attr_accessor attr_reader"),
            literals: ["true", "false", "nil"], sigils: ["@": .variable, ":": .attr]),

        CodeLanguage(names: ["html", "xml", "svg", "xhtml", "vue", "xaml", "plist"], kind: .html, strings: [dq, sq]),

        CodeLanguage(names: ["css", "scss", "sass", "less"], kind: .css, lineComments: slashes, blockComment: cBlock, strings: [dq, sq]),

        CodeLanguage(names: ["yaml", "yml"], kind: .yaml, lineComments: ["#"], commentNeedsBoundary: true, strings: [dq, sq],
                     literals: ["true", "false", "null", "yes", "no", "on", "off", "~"], capitalizedAreTypes: false, callsAreTitles: false,
                     sigils: ["&": .variable, "*": .variable]),

        CodeLanguage(names: ["toml", "ini", "conf", "cfg", "properties", "env", "dotenv"], kind: .toml, lineComments: ["#", ";"], commentNeedsBoundary: true,
                     strings: [StringRule(open: "\"\"\"", close: "\"\"\"", multiline: true), StringRule(open: "'''", close: "'''", multiline: true), dq, sq],
                     literals: ["true", "false"], capitalizedAreTypes: false, callsAreTitles: false),

        CodeLanguage(names: ["diff", "patch"], kind: .diff),

        CodeLanguage(
            names: ["make", "makefile", "dockerfile", "docker"], lineComments: ["#"], commentNeedsBoundary: true, strings: [dq, sq],
            keywords: words("FROM RUN CMD LABEL EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS ifeq ifneq ifdef ifndef else endif include .PHONY define endef"),
            capitalizedAreTypes: false, callsAreTitles: false, sigils: ["$": .variable]),
    ]
}
