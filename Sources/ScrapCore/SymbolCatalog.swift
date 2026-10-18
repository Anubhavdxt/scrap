import Foundation

public struct SymbolItem: Equatable, Identifiable {
    public enum Kind: Equatable {
        /// Smart bullet pair `SmartBullets.pairs[index]`, put at the start of the line.
        case smartBullet(Int)
        /// A Markdown task, `- [ ] `.
        case markdownTask
        /// A line of its own.
        case divider(String)
        /// Typed at the cursor.
        case text(String)
    }

    public let kind: Kind
    /// What the button shows.
    public let label: String
    public let title: String
    public var id: String { "\(kind)" }
}

public struct SymbolGroup: Equatable, Identifiable {
    public let name: String
    public let items: [SymbolItem]
    public var id: String { name }
}

/// Everything the `*` picker offers, in the groups Tot uses.
public enum SymbolCatalog {
    private static func characters(_ s: String, _ title: (String) -> String) -> [SymbolItem] {
        s.map { String($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map {
            SymbolItem(kind: .text($0), label: $0, title: title($0))
        }
    }

    /// The groups with the current custom bullets (`SmartBullets.custom`).
    public static var groups: [SymbolGroup] { groups(custom: SmartBullets.custom) }

    /// The groups with `custom` as your own smart bullets, after the built-in ones.
    public static func groups(custom: [SmartBullets.Pair]) -> [SymbolGroup] {
        let pairs = SmartBullets.builtIn + custom
        return [
        SymbolGroup(name: "Smart Bullets", items:
            [SymbolItem(kind: .markdownTask, label: "[ ]", title: "Markdown task: - [ ]")]
            + pairs.indices.map { i in
                let pair = pairs[i]
                return SymbolItem(kind: .smartBullet(i), label: pair.open + pair.done, title: "Smart bullet \(pair.open) ↔ \(pair.done) (click it to flip)")
            }),
        SymbolGroup(name: "Dividers", items: [
            "────────────", "━━━━━━━━━━━━", "┄┄┄┄┄┄┄┄┄┄┄┄", "╌╌╌╌╌╌╌╌╌╌╌╌",
            "· · · · · · · ·", "— — — — — —", "≡≡≡≡≡≡≡≡≡≡≡≡", "• • • • • • •",
        ].map { SymbolItem(kind: .divider($0), label: String($0.prefix(7)), title: "Divider \($0)") }),
        SymbolGroup(name: "Bullets", items: characters("•·‣◦▪▫◆◇◈❖✲✱✻✼✽❊⁃⦿⊛❧") { "Bullet \($0)" }),
        SymbolGroup(name: "Checkmarks", items: characters("√✓✔☑☒✕✗✘✖☐") { "Checkmark \($0)" }),
        SymbolGroup(name: "Arrows", items: characters("→←↑↓↔↕↗↘↖↙⇒⇐⇨➔➜➤▶◀▲▼▷◁△▽›‹»«") { "Arrow \($0)" }),
        SymbolGroup(name: "Numbers", items: characters("⓪①②③④⑤⑥⑦⑧⑨⓿❶❷❸❹❺❻❼❽❾") { "Number \($0)" }),
        SymbolGroup(name: "Technical", items: characters("⌘⌥⇧⌃⎋⌫⌦⏎↩↵⇥⇤⏏⌧⎈⌤⏻⌨") { "Key symbol \($0)" }),
        SymbolGroup(name: "Symbols", items: characters("¶§†‡‰°©®™∞≈≠≤≥±÷×♠♣♥♦☀☁♪☎✉✂⚑⚠") { "Symbol \($0)" }),
        ]
    }
}
