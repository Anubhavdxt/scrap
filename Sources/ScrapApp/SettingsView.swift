import AppKit
import ScrapCore
import SwiftUI

/// Settings pane shown in a popover attached to the gear. Uses the selected editor theme.
struct SettingsView: View {
    static let size = CGSize(width: 440, height: 500)

    /// Four tabs, so each one fits without much scrolling.
    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General", appearance = "Appearance", editor = "Editor", window = "Window"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .appearance: "paintpalette"
            case .editor: "textformat"
            case .window: "macwindow"
            }
        }
    }

    @ObservedObject var model: EditorModel
    /// The pane's height (taller only in tests, to measure how much room each tab needs).
    var height: CGFloat = SettingsView.size.height
    @ObservedObject private var hotkeys = HotKeyManager.shared
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto
    @AppStorage("fontSize") private var fontSize = EditorFont.defaultSize
    @AppStorage("fontFamily") private var fontFamily = EditorFont.systemFamily
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("colorHighlights") private var colorHighlights = true
    @AppStorage("colorChips") private var colorChips = true
    @AppStorage("markers") private var markers = "hide"
    @AppStorage("autoList") private var autoList = true
    @AppStorage("keepIndent") private var keepIndent = true
    @AppStorage("tintMenuBar") private var tintMenuBar = true
    @AppStorage("showPadNumber") private var showPadNumber = false
    @AppStorage("vibrant") private var vibrant = false
    @AppStorage("appIcon") private var appIcon = AppIcons.default
    @AppStorage("tintFooter") private var tintFooter = true
    @AppStorage("allowURLAdd") private var allowURLAdd = true
    @AppStorage("escCloses") private var escCloses = true
    @AppStorage("iconMode") private var iconMode = IconMode.menuBar
    @AppStorage("detached") private var detached = false
    @AppStorage("windowFloating") private var windowFloating = false
    @AppStorage("windowFollowsPointer") private var windowFollowsPointer = false
    @AppStorage("windowCols") private var cols = WindowSize.defaultCols
    @AppStorage("windowRows") private var rows = WindowSize.defaultRows
    @AppStorage("settingsTab") private var tabRaw = Tab.general.rawValue
    @State private var hovered: Tab?
    @State private var bulletsOpen = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    private var tab: Tab { Tab(rawValue: tabRaw) ?? .general }   // an old "Shortcuts" or "About" lands on General, where they went

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
                    case .general: general
                    case .appearance: look
                    case .editor: editor
                    case .window: window
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
        .frame(width: Self.size.width, height: height)
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
            Text("scrap \(Scrap.version) · free and open source").font(.system(size: 11)).foregroundStyle(dim).lineLimit(1)
            Spacer()
            Menu("Help") {
                Button("GitHub") { open("https://github.com/Anubhavdxt/scrap") }
                Button("Discussions") { open("https://github.com/Anubhavdxt/scrap/discussions") }
                Button("Report an issue") { open("https://github.com/Anubhavdxt/scrap/issues/new/choose") }
                Divider()
                Button("Say hi…") {
                    model.showSayHi = true
                    NotificationCenter.default.post(name: .toggleSettings, object: nil) // closes this pane
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)
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
            note("Lowering hides pads. It never deletes them.")
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
            note("Pads in the old folder stay there.")
            row("Show or hide") { ShortcutRecorder(accent: accent, dim: dim) }
            if let error = hotkeys.error { note(error).foregroundStyle(.red) }
            note("Click it, then press new keys (with ⌃ ⌥ or ⌘).")
            row("Typing") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Continue lists on Return", isOn: $autoList)
                    Toggle("Keep indentation on Return", isOn: $keepIndent)
                }
                .toggleStyle(.checkbox)
            }
            row("Other") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Open scrap at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin(_:)))
                    Toggle("Let scrap:// links add text (never read)", isOn: $allowURLAdd)
                }
                .toggleStyle(.checkbox)
            }
            if let loginMessage { note(loginMessage) }
        }
    }

    /// Keys worth knowing.
    private var keyHints: some View {
        HStack(spacing: 6) {
            keyHint("⌘K", "search"); keyHint("⌘1–9", "pads"); keyHint("⇧⌘⌫", "clear"); keyHint("⌘,", "settings"); keyHint("Esc", "close")
        }
    }

    private func keyHint(_ keys: String, _ what: String) -> some View {
        VStack(spacing: 2) {
            key(keys)
            Text(what).font(.system(size: 10)).foregroundStyle(dim)
        }
        .frame(maxWidth: .infinity)
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

    private var iconPicker: some View {
        HStack(spacing: 6) {
            ForEach(AppIcons.all) { choice in
                Button { appIcon = choice.id } label: {
                    Group {
                        if let image = AppIcons.image(choice.id) { Image(nsImage: image).resizable() } else { Color.gray.opacity(0.3) }
                    }
                    .frame(width: 28, height: 28)
                    .padding(2)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(AppIcons.resolve(appIcon) == choice.id ? Color.accentColor : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .help(choice.name)
            }
        }
    }

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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(Themes.families, id: \.id) { f in swatch(f.id, f.name) }
            }
            Divider().padding(.vertical, 2)
            row("Look") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Vibrant (the desktop shows through)", isOn: $vibrant)
                    Toggle("Tint the footer with the pad colour", isOn: $tintFooter)
                    Toggle("Show the pad number in its dot", isOn: $showPadNumber)
                }
                .toggleStyle(.checkbox)
            }
            row("Dock icon") { iconPicker }.help("Changes the Dock icon while scrap runs; Finder keeps the original.")
        }
    }

    // MARK: Editor

    private var editor: some View {
        Group {
            row("Font") {
                Picker("", selection: $fontFamily) {
                    Text("System (proportional)").tag(EditorFont.systemFamily)
                    Text("System Mono").tag("")
                    ForEach(EditorFont.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            note("Code and raw text are always monospaced.")
            row("Size") {
                Stepper(value: $fontSize, in: EditorFont.sizeRange, step: 1) { Text("\(Int(fontSize)) pt").monospacedDigit() }
                if fontSize != EditorFont.defaultSize { Button("Reset") { fontSize = EditorFont.defaultSize }.controlSize(.small) }
                Text("⌘+ ⌘− ⌘0").font(.system(size: 11)).foregroundStyle(dim)
            }
            row("Text") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Wrap lines", isOn: $wrapLines)
                    Toggle("Colour bold, italic, links and headings", isOn: $colorHighlights)
                    Toggle("Show #0352BF as a colour chip", isOn: $colorChips)
                }
                .toggleStyle(.checkbox)
            }
            row("Markdown marks") {
                Picker("", selection: $markers) {
                    Text("Hide away from cursor").tag("hide")
                    Text("Dim").tag("dim")
                    Text("Show").tag("show")
                }
                .labelsHidden()
                .frame(width: 200)
            }
            note("The ** # ` around styled text; hidden ones show on your line.")
            keyHints.padding(.top, 4)
            DisclosureGroup(isExpanded: $bulletsOpen) {
                CustomBulletsEditor().padding(.top, 6)
            } label: {
                Text("Custom smart bullets").font(.system(size: 13, weight: .medium))
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
                    .frame(height: 36)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(Color(nsColor: NSColor(hex: t.accent))).frame(width: 24, height: 4)
                            Capsule().fill(Color(nsColor: NSColor(hex: t.color(.string)))).frame(width: 34, height: 3)
                            Capsule().fill(Color(nsColor: NSColor(hex: t.color(.base)))).frame(width: 28, height: 3)
                        }
                        .padding(6)
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
            row("Show in") {
                Picker("", selection: $iconMode) {
                    ForEach(IconMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            note(iconMode == .dock ? "With only a Dock icon, scrap opens as a window." : "The menu bar icon opens the editor as a popover.")
            row("Behaviour") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Open as a window instead of a popover", isOn: Binding(get: { detached || iconMode == .dock }, set: { detached = $0 }))
                        .disabled(iconMode == .dock)
                    Toggle("Keep the window above other windows", isOn: $windowFloating)
                    Toggle("The hotkey opens the window at the pointer", isOn: $windowFollowsPointer)
                    Toggle("Escape closes the window", isOn: $escCloses)
                    Toggle("Tint the menu bar icon with the pad colour", isOn: $tintMenuBar)
                }
                .toggleStyle(.checkbox)
            }
            Divider().padding(.vertical, 2)
            row("Size") {
                Stepper(value: $cols, in: WindowSize.colsRange) { Text("\(cols)").monospacedDigit() }
                Text("×").foregroundStyle(dim)
                Stepper(value: $rows, in: WindowSize.rowsRange) { Text("\(rows)").monospacedDigit() }
                Text("characters").foregroundStyle(dim).font(.system(size: 11))
            }
            note("Opens at about \(Int(size.width)) × \(Int(size.height)) pt, like a terminal's window size.")
            row("") {
                Button("Reset to \(WindowSize.defaultCols) × \(WindowSize.defaultRows)") {
                    cols = WindowSize.defaultCols
                    rows = WindowSize.defaultRows
                }
                .controlSize(.small)
            }
        }
    }

    private func key(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(dim.opacity(0.2)))
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
