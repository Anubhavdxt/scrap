import AppKit
import ScrapCore
import SwiftUI

/// Settings pane shown in a popover attached to the gear. Uses the selected editor theme.
struct SettingsView: View {
    static let size = CGSize(width: 440, height: 420)

    private enum Tab: String, CaseIterable, Identifiable {
        case appearance = "Appearance", general = "General", window = "Window", shortcuts = "Shortcuts", about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .appearance: "paintpalette"
            case .general: "slider.horizontal.3"
            case .window: "macwindow"
            case .shortcuts: "command"
            case .about: "info.circle"
            }
        }
    }

    @ObservedObject var model: EditorModel
    @ObservedObject private var hotkeys = HotKeyManager.shared
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto
    @AppStorage("fontSize") private var fontSize = EditorFont.defaultSize
    @AppStorage("fontFamily") private var fontFamily = EditorFont.systemFamily
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("colorHighlights") private var colorHighlights = true
    @AppStorage("markers") private var markers = "hide"
    @AppStorage("autoList") private var autoList = true
    @AppStorage("keepIndent") private var keepIndent = true
    @AppStorage("tintMenuBar") private var tintMenuBar = true
    @AppStorage("tintFooter") private var tintFooter = true
    @AppStorage("escCloses") private var escCloses = true
    @AppStorage("iconMode") private var iconMode = IconMode.menuBar
    @AppStorage("detached") private var detached = false
    @AppStorage("windowFloating") private var windowFloating = false
    @AppStorage("windowCols") private var cols = WindowSize.defaultCols
    @AppStorage("windowRows") private var rows = WindowSize.defaultRows
    @AppStorage("settingsTab") private var tabRaw = Tab.appearance.rawValue
    @State private var hovered: Tab?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private var tab: Tab { Tab(rawValue: tabRaw) ?? .appearance }

    private var theme: Theme { resolveTheme(family: family, appearance: appearance, colorScheme: colorScheme) }
    private var bg: Color { Color(nsColor: NSColor(hex: theme.background)) }
    private var fg: Color { Color(nsColor: NSColor(hex: theme.color(.base))) }
    private var dim: Color { Color(nsColor: NSColor(hex: theme.color(.comment))) }
    private var accent: Color { Color(nsColor: NSColor(hex: theme.accent)) }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .appearance: look
                    case .general: general
                    case .window: window
                    case .shortcuts: shortcuts
                    case .about: about
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(tab)
                .transition(.opacity)
            }
            Divider().opacity(0.6)
            footer
        }
        .background { tabShortcuts }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(fg)
        .tint(accent)
        .background(bg)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { t in
                let selected = tab == t
                Button { select(t) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.system(size: 18, weight: .medium))
                        Text(t.rawValue).font(.system(size: 11, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? accent : (hovered == t ? fg : dim))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(selected ? accent.opacity(0.16) : (hovered == t ? fg.opacity(0.07) : .clear))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? t : (hovered == t ? nil : hovered) }
                .help(t.rawValue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(theme.isDark ? 0.18 : 0.05))
    }

    private func select(_ t: Tab) {
        withAnimation(.easeOut(duration: 0.12)) { tabRaw = t.rawValue }
    }

    /// ⌃Tab and ⌃⇧Tab cycle the tabs.
    private var tabShortcuts: some View {
        Group {
            Button("Next tab") { cycle(1) }.keyboardShortcut(.tab, modifiers: .control)
            Button("Previous tab") { cycle(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func cycle(_ delta: Int) {
        let all = Tab.allCases
        let i = all.firstIndex(of: tab) ?? 0
        select(all[(i + delta + all.count) % all.count])
    }

    private var footer: some View {
        HStack {
            Text("scrap \(Scrap.version)").font(.system(size: 11)).foregroundStyle(dim)
            Spacer()
            Button("Quit scrap") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(theme.isDark ? 0.18 : 0.05))
    }

    // MARK: General

    private var general: some View {
        Group {
            row("Pads") {
                Stepper(value: Binding(get: { model.padCount }, set: { model.setPadCount($0) }), in: 1...Config.maxPads) {
                    Text("\(model.padCount)").monospacedDigit()
                }
            }
            note("Lowering this hides pads. It never deletes them.")
            row("Folder") {
                VStack(alignment: .leading, spacing: 6) {
                    Text((model.folder.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11)).lineLimit(2).textSelection(.enabled)
                    HStack {
                        Button("Choose…") { chooseFolder() }.controlSize(.small)
                        if model.folder != Config.defaultFolder() {
                            Button("Use default") { model.setFolder(nil) }.controlSize(.small)
                        }
                    }
                }
            }
            note("Pads already in the old folder stay there. Copy them over if you want them.")
            Divider().padding(.vertical, 2)
            row("Typing") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Continue lists on Return", isOn: $autoList)
                    Toggle("Keep indentation on Return", isOn: $keepIndent)
                }
                .toggleStyle(.checkbox)
            }
            note("Lists: bullets, numbers and tasks. Indentation applies to any line that starts with spaces or tabs.")
            row("Show in") {
                Picker("", selection: $iconMode) {
                    ForEach(IconMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            note(iconMode == .dock ? "With only a Dock icon, scrap opens as a window." : "The menu bar icon opens the editor as a popover.")
            row("Window") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Open as a window instead of a popover", isOn: Binding(get: { detached || iconMode == .dock }, set: { detached = $0 }))
                        .disabled(iconMode == .dock)
                    Toggle("Keep the window above other windows", isOn: $windowFloating)
                    Toggle("Escape closes the window", isOn: $escCloses)
                    Toggle("Tint the menu bar icon with the pad colour", isOn: $tintMenuBar)
                    Toggle("Tint the footer with the pad colour", isOn: $tintFooter)
                }
                .toggleStyle(.checkbox)
            }
            row("Startup") {
                Toggle("Open scrap at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin(_:)))
                    .toggleStyle(.checkbox)
            }
            if let loginMessage { note(loginMessage) }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginMessage = LaunchAtLogin.needsApproval ? "Approve scrap in System Settings → General → Login Items." : nil
        } catch {
            loginMessage = "Couldn't change it: \(error.localizedDescription). This only works for the installed Scrap.app."
        }
        launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where scrap keeps its pads (1.md, 2.md, …)"
        panel.directoryURL = model.folder
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { model.setFolder(url) }
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
            Divider().padding(.vertical, 4)
            Text("Text").font(.system(size: 13, weight: .medium))
            row("Font") {
                Picker("", selection: $fontFamily) {
                    Text("System (proportional)").tag(EditorFont.systemFamily)
                    Text("System Mono").tag("")
                    ForEach(EditorFont.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            note("Code, code blocks and raw text are always monospaced.")
            row("Size") {
                Stepper(value: $fontSize, in: EditorFont.sizeRange, step: 1) { Text("\(Int(fontSize)) pt").monospacedDigit() }
                if fontSize != EditorFont.defaultSize { Button("Reset") { fontSize = EditorFont.defaultSize }.controlSize(.small) }
            }
            row("Wrap lines") { Toggle("", isOn: $wrapLines).labelsHidden().toggleStyle(.switch) }
            row("Colour highlights") { Toggle("", isOn: $colorHighlights).labelsHidden().toggleStyle(.switch) }
            note("Colours bold, italic, links, headings and code. Off keeps the weights and underlines but uses one text colour.")
            row("Markdown marks") {
                Picker("", selection: $markers) {
                    Text("Hide away from cursor").tag("hide")
                    Text("Dim").tag("dim")
                    Text("Show").tag("show")
                }
                .labelsHidden()
                .frame(width: 200)
            }
            note("The ** # ` and [ ] around styled text. Hidden marks appear on the line you're editing.")
            note("⌘+ and ⌘− change the size, ⌘0 resets it. The window grows with the font because its size is in columns and rows.")
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
            row("Show or hide") { ShortcutRecorder(accent: accent, dim: dim) }
            if let error = hotkeys.error { note(error).foregroundStyle(.red) }
            note("Click the shortcut, then press the new keys. Use at least one of ⌃ ⌥ ⌘.")
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

    // MARK: About

    private var about: some View {
        Group {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("scrap").font(.system(size: 20, weight: .bold))
                    Text("Version \(Scrap.version)").font(.system(size: 12)).foregroundStyle(dim)
                    Text("Free and open source (MIT)").font(.system(size: 12)).foregroundStyle(dim)
                }
            }
            HStack(spacing: 8) {
                Button("GitHub") { open("https://github.com/Anubhavdxt/scrap") }
                Button("Discussions") { open("https://github.com/Anubhavdxt/scrap/discussions") }
                Button("Report an issue") { open("https://github.com/Anubhavdxt/scrap/issues/new/choose") }
                Button("Say hi…") {
                    model.showSayHi = true
                    NotificationCenter.default.post(name: .toggleSettings, object: nil) // closes this pane
                }
            }
            note("Pads are plain Markdown files, and nothing leaves your Mac.").padding(.leading, 0)
        }
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
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

/// Click, then press a new global shortcut.
struct ShortcutRecorder: View {
    let accent: Color
    let dim: Color
    @ObservedObject private var manager = HotKeyManager.shared
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button { manager.isRecording ? stop() : start() } label: {
                Text(manager.isRecording ? "Press keys…" : manager.label)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .frame(minWidth: 96)
                    .background(RoundedRectangle(cornerRadius: 6).fill(manager.isRecording ? accent.opacity(0.25) : dim.opacity(0.2)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(manager.isRecording ? accent : .clear, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            if !manager.isDefault && !manager.isRecording {
                Button("Reset") { manager.reset() }.controlSize(.small)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        manager.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 { stop(); return nil } // Esc cancels
                let mods = HotKeyManager.carbonMods(event.modifierFlags)
                guard mods & (0x1000 | 0x0800 | 0x0100) != 0 else { return nil } // needs ⌃, ⌥ or ⌘
                manager.set(code: Int(event.keyCode), mods: mods, label: HotKeyManager.label(for: event))
                stop()
                return nil
            }
        }
    }

    private func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        manager.isRecording = false
    }
}
