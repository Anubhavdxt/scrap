import Foundation

public enum Token: String, CaseIterable, Sendable {
    case base, comment, keyword, title, type, builtin, number, string, subst, attr, variable, `operator`, punctuation, deletion
}

public struct Theme: Identifiable, Sendable {
    public let id: String
    public let family: String
    public let name: String
    public let isDark: Bool
    /// 0xRRGGBB
    public let background: UInt32
    public let accent: UInt32
    public let colors: [Token: UInt32]
    public let italic: Set<Token>

    public func color(_ token: Token) -> UInt32 { colors[token] ?? colors[.base] ?? 0 }
}

public enum Themes {
    public static let all = generated

    public static var families: [(id: String, name: String)] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.family).inserted ? ($0.family, $0.name) : nil }
    }

    public static func theme(family: String, dark: Bool) -> Theme {
        all.first { $0.family == family && $0.isDark == dark }
            ?? all.first { $0.id == "cobalt2-dark" }!
    }
}
