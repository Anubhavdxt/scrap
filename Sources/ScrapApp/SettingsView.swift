import AppKit
import ScrapCore
import SwiftUI

/// Settings pane shown in a popover attached to the gear. Uses the selected editor theme.
struct SettingsView: View {
    static let size = CGSize(width: 440, height: 400)

    private enum Tab: String, CaseIterable, Identifiable {
        case pads = "Pads", appearance = "Appearance", window = "Window", shortcuts = "Shortcuts"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .pads: "square.stack"
            case .appearance: "circle.lefthalf.filled"
            case .window: "macwindow"
            case .shortcuts: "command"
            }
        }
    }

    @ObservedObject var model: EditorModel
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto
    @AppStorage("windowCols") private var cols = WindowSize.defaultCols
    @AppStorage("windowRows") private var rows = WindowSize.defaultRows
    @State private var tab = Tab.pads
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { resolveTheme(family: family, appearance: appearance, colorScheme: colorScheme) }
    private var bg: Color { Color(nsColor: NSColor(hex: theme.background)) }
    private var fg: Color { Color(nsColor: NSColor(hex: theme.color(.base))) }
    private var dim: Color { Color(nsColor: NSColor(hex: theme.color(.comment))) }
    private var accent: Color { Color(nsColor: NSColor(hex: theme.accent)) }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .pads: pads
                    case .appearance: look
                    case .window: window
                    case .shortcuts: shortcuts
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(fg)
        .tint(accent)
        .background(bg)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 20))
                        Text(t.rawValue).font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(tab == t ? accent : dim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.black.opacity(theme.isDark ? 0.18 : 0.05))
    }

    // MARK: Pads

    private var pads: some View {
        Group {
            row("Pads") {
                Stepper(value: Binding(get: { model.padCount }, set: { model.setPadCount($0) }), in: 1...Config.maxPads) {
                    Text("\(model.padCount)").monospacedDigit()
                }
            }
            note("Lowering this hides pads. It never deletes them.")
            row("Folder") {
                Text(Config.folder().path).font(.system(size: 11)).lineLimit(2).textSelection(.enabled)
            }
            Divider()
            row("") { Button("Quit scrap") { NSApp.terminate(nil) } }
        }
    }

    // MARK: Appearance

    private var look: some View {
        Group {
            row("Mode") {
                Picker("", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            Text("Theme").font(.system(size: 13, weight: .medium))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(Themes.families, id: \.id) { f in swatch(f.id, f.name) }
            }
        }
    }

    private func swatch(_ id: String, _ name: String) -> some View {
        let t = Themes.theme(family: id, dark: theme.isDark)
        let selected = id == family
        return Button { family = id } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: NSColor(hex: t.background)))
                    .frame(height: 46)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(Color(nsColor: NSColor(hex: t.accent))).frame(width: 26, height: 5)
                            Capsule().fill(Color(nsColor: NSColor(hex: t.color(.string)))).frame(width: 38, height: 4)
                            Capsule().fill(Color(nsColor: NSColor(hex: t.color(.base)))).frame(width: 30, height: 4)
                        }
                        .padding(8)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? accent : dim.opacity(0.4), lineWidth: selected ? 2.5 : 1))
                Text(name).font(.system(size: 11)).foregroundStyle(selected ? accent : dim)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Window

    private var window: some View {
        let size = WindowSize.contentSize(cols: cols, rows: rows)
        return Group {
            row("Columns") {
                Stepper(value: $cols, in: WindowSize.colsRange) { Text("\(cols)").monospacedDigit() }
            }
            row("Rows") {
                Stepper(value: $rows, in: WindowSize.rowsRange) { Text("\(rows)").monospacedDigit() }
            }
            note("Opens at \(cols) × \(rows) characters, about \(Int(size.width)) × \(Int(size.height)) pt. Like a terminal's window size.")
            row("") {
                Button("Reset to \(WindowSize.defaultCols) × \(WindowSize.defaultRows)") {
                    cols = WindowSize.defaultCols
                    rows = WindowSize.defaultRows
                }
            }
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Group {
            row("Show or hide") { key("⌃⌥Space") }
            row("Quick switch") { key("⌘K") }
            row("Go to pad 1–9") { key("⌘1 – ⌘9") }
            row("Clear pad") { key("⇧⌘⌫") }
            row("Settings") { key("⌘,") }
            row("Close") { key("Esc") }
        }
    }

    private func key(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(dim.opacity(0.2)))
    }

    // MARK: Layout helpers

    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label).foregroundStyle(dim).frame(width: 110, alignment: .trailing)
            content()
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(dim)
            .padding(.leading, 124)
    }
}
