import AppKit
import ScrapCore
import ServiceManagement
import SwiftUI

/// Settings pane shown in a popover attached to the gear. Uses the selected editor theme.
struct SettingsView: View {
    static let size = CGSize(width: 440, height: 410)

    /// Four tabs, like Tot's: what you will touch most, how it looks, how it edits, and a page about scrap.
    private enum Tab: String, CaseIterable, Identifiable {
        case general = "General", appearance = "Appearance", editor = "Editor", about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .appearance: "paintpalette"
            case .editor: "textformat"
            case .about: "sparkles"
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
    @AppStorage("allowURLAdd") private var allowURLAdd = true
    @AppStorage("escCloses") private var escCloses = true
    @AppStorage("iconMode") private var iconMode = IconMode.menuBar
    @AppStorage("windowFloating") private var windowFloating = false
    @AppStorage("windowFollowsPointer") private var windowFollowsPointer = false
    @AppStorage("windowCols") private var cols = WindowSize.defaultCols
    @AppStorage("windowRows") private var rows = WindowSize.defaultRows
    @AppStorage("settingsTab") private var tabRaw = Tab.general.rawValue
    @Local private var hovered: Tab?
    @Local private var bulletsOpen = false
    @Local private var launchAtLogin = LaunchAtLogin.isEnabled
    @Local private var loginMessage: String?
    @Environment(\.colorScheme) private var colorScheme
    /// In its own window (the editor is detached), the pane has a close button of its own instead of closing on a click away.
    @Environment(\.scrapWindowed) private var windowed

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
                VStack(alignment: .leading, spacing: 11) {
                    switch tab {
                    case .general: general
                    case .appearance: look
                    case .editor: editor
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
        .overlay(alignment: .bottom) {
            // A short confirmation floats above the footer, so it never pushes the settings around.
            if let loginMessage {
                Text(loginMessage)
                    .font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().strokeBorder(dim.opacity(0.25)))
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    .padding(.bottom, 42)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: loginMessage)
        .frame(width: Self.size.width, height: height)
        // In a window the content runs under the transparent title bar, so the pane must not leave room for it.
        .ignoresSafeArea(.container, edges: windowed ? .top : [])
        .foregroundStyle(fg)
        .tint(accent)
        .background(bg)
    }

    // MARK: Tabs

    /// The tabs sit in the middle of the bar; in its own window the pane has a close button in the corner, as Tot's does.
    private var tabBar: some View {
        ZStack(alignment: .topLeading) {
            tabButtons.padding(.horizontal, windowed ? 34 : 0)
            if windowed {
                Button { NotificationCenter.default.post(name: .toggleSettings, object: nil) } label: {
                    Image(systemName: "xmark.circle").font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(dim)
                .help("Close settings")
                .padding(.leading, 10).padding(.top, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(theme.isDark ? 0.18 : 0.05))
    }

    private var tabButtons: some View {
        HStack(spacing: 2) {

            ForEach(Tab.allCases) { t in
                let selected = tab == t
                Button { select(t) } label: {
                    VStack(spacing: 4) {
                        // The same box for every icon, so the tiles don't differ with how tall each glyph is.
                        Image(systemName: t.icon).font(.system(size: 18, weight: .medium)).frame(width: 26, height: 24)
                        Text(t.rawValue).font(.system(size: 11, weight: selected ? .semibold : .medium)).frame(height: 14)
                    }
                    .foregroundStyle(selected ? accent : (hovered == t ? fg : dim))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
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
    }

    /// Version on the left, who made it on the right: the same two things Tot's footer carries, a bit friendlier.
    private var footer: some View {
        HStack {
            Text("SCRAP \(Scrap.version)").font(.system(size: 10, weight: .medium)).tracking(0.8).foregroundStyle(dim)
                .textSelection(.enabled)
            Spacer()
            Button { open("https://github.com/Anubhavdxt") } label: {
                HStack(spacing: 4) {
                    Text("made by Anubhav")
                    Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(PadColors.color(for: 1))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(dim)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("github.com/Anubhavdxt")
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
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

    // MARK: Layout pieces

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(dim).textCase(.uppercase).padding(.top, 2)
    }

    /// Checkboxes two to a line, so a handful of options take a few lines.
    private func checks<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
            content()
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
    }

    // MARK: General

    private var general: some View {
        Group {
            row("Pads") {
                Stepper(value: Binding(get: { model.padCount }, set: { model.setPadCount($0) }), in: 1...Config.maxPads) {
                    Text("\(model.padCount)").monospacedDigit()
                }
                .help("Lowering this hides pads. It never deletes them.")
            }
            row("Folder") {
                Text((model.folder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .help("Pads in an old folder stay there.")
                Button("Choose…") { chooseFolder() }.controlSize(.small)
                if model.folder != Config.defaultFolder() { Button("Default") { model.setFolder(nil) }.controlSize(.small) }
            }
            row("Show in") {
                Picker("", selection: $iconMode) {
                    ForEach(IconMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            row("Show or hide") { ShortcutRecorder(accent: accent, dim: dim) }
            if let error = hotkeys.error { note(error).foregroundStyle(.red) }
            checks {
                Toggle("Keep above other windows", isOn: $windowFloating)
                Toggle("Hotkey opens at the pointer", isOn: $windowFollowsPointer)
                Toggle("Esc closes the window", isOn: $escCloses)
                Toggle("Tint menu bar icon", isOn: $tintMenuBar).help("With the open pad's colour.")
            }
            row("Size") {
                Stepper(value: $cols, in: WindowSize.colsRange) { Text("\(cols)").monospacedDigit() }
                Text("×").foregroundStyle(dim)
                Stepper(value: $rows, in: WindowSize.rowsRange) { Text("\(rows)").monospacedDigit() }
                Text("characters").foregroundStyle(dim).font(.system(size: 11))
                if cols != WindowSize.defaultCols || rows != WindowSize.defaultRows {
                    Button("Reset") { cols = WindowSize.defaultCols; rows = WindowSize.defaultRows }.controlSize(.small)
                }
            }
            Divider().padding(.vertical, 2)
            HStack {
                Toggle("Open scrap at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin(_:)))
                    .toggleStyle(.checkbox).font(.system(size: 12))
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    HStack(spacing: 6) { Text("Quit scrap"); Text("⌘Q").foregroundStyle(dim) }.padding(.horizontal, 4)
                }
                .controlSize(.large)
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginMessage = LaunchAtLogin.message(requested: on, status: SMAppService.mainApp.status)
        } catch {
            loginMessage = "Couldn't change it: \(error.localizedDescription). This only works for the installed Scrap.app."
        }
        launchAtLogin = LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval
        // The note is a confirmation, so it fades after a few seconds (unless it is asking you to approve something).
        let shown = loginMessage
        if !LaunchAtLogin.needsApproval {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if loginMessage == shown { loginMessage = nil } }
        }
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
            heading("Theme")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 6) {
                ForEach(Themes.families, id: \.id) { f in swatch(f.id, f.name) }
            }
            Divider().padding(.vertical, 2)
            checks {
                Toggle("Vibrant (see-through)", isOn: $vibrant).help("Lets the desktop show through, blurred.")
                Toggle("Pad number in its dot", isOn: $showPadNumber)
            }
            row("Dock icon") { iconPicker }.help("Changes the Dock icon while scrap runs; Finder keeps the original.")
        }
    }

    // MARK: Editor

    private var editor: some View {
        Group {
            row("Font") {
                Picker("", selection: $fontFamily) {
                    Text("System").tag(EditorFont.systemFamily)
                    Text("System Mono").tag("")
                    ForEach(EditorFont.families, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)
                .help("Code and raw text are always monospaced.")
                Stepper(value: $fontSize, in: EditorFont.sizeRange, step: 1) { Text("\(Int(fontSize))").monospacedDigit().fixedSize() }
                    .help("Size in points. ⌘+ ⌘− ⌘0 change it from the keyboard.")
                if fontSize != EditorFont.defaultSize {
                    Button { fontSize = EditorFont.defaultSize } label: { Image(systemName: "arrow.counterclockwise") }
                        .controlSize(.small).help("Back to \(Int(EditorFont.defaultSize)) pt")
                }
            }
            row("Markdown marks") {
                Picker("", selection: $markers) {
                    Text("Hide away from cursor").tag("hide")
                    Text("Dim").tag("dim")
                    Text("Show").tag("show")
                }
                .labelsHidden()
                .frame(width: 200)
                .help("The ** # ` around styled text; hidden ones show on the line you're editing.")
            }
            Divider().padding(.vertical, 2)
            checks {
                Toggle("Wrap lines", isOn: $wrapLines)
                Toggle("Colour the styles", isOn: $colorHighlights).help("Bold, italic, links and headings.")
                Toggle("Colour chips for #0352BF", isOn: $colorChips)
                Toggle("Continue lists on Return", isOn: $autoList)
                Toggle("Keep indentation on Return", isOn: $keepIndent)
                Toggle("scrap:// links add text", isOn: $allowURLAdd).help("They can open a pad or add text, never read one. An addition is announced in the footer.")
            }
            keyHints.padding(.top, 2)
            Button { withAnimation(.easeOut(duration: 0.15)) { bulletsOpen.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).rotationEffect(.degrees(bulletsOpen ? 90 : 0))
                    Text("Custom smart bullets").font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if bulletsOpen { CustomBulletsEditor().padding(.top, 2) }
        }
    }

    /// Keys worth knowing.
    private var keyHints: some View {
        HStack(spacing: 6) {
            keyHint("⌘K", "search"); keyHint("⌘[ ⌘]", "prev / next pad"); keyHint("⌘1–9", "go to pad"); keyHint("⌘,", "settings"); keyHint("Esc", "close")
        }
    }

    private func keyHint(_ keys: String, _ what: String) -> some View {
        VStack(spacing: 2) {
            key(keys)
            Text(what).font(.system(size: 10)).foregroundStyle(dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func swatch(_ id: String, _ name: String) -> some View {
        let t = Themes.theme(family: id, dark: theme.isDark)
        let selected = id == family
        return Button { family = id } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: NSColor(hex: t.background)))
                    .frame(height: 30)
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

    private func key(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(dim.opacity(0.2)))
    }

    // MARK: About

    private var about: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [accent.opacity(0.32), accent.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.35), lineWidth: 1)
                HStack(spacing: 16) {
                    logo.frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("scrap").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("A scratchpad that stays out of the way.").font(.system(size: 12)).foregroundStyle(dim)
                        padDots
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .frame(height: 94)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                linkTile("star.fill", "Star on GitHub", "It helps others find it") { open("https://github.com/Anubhavdxt/scrap") }
                linkTile("sparkles", "What's new", "Release notes") { open("https://github.com/Anubhavdxt/scrap/releases/latest") }
                linkTile("bubble.left.and.bubble.right", "Discussions", "Ask, share ideas") { open("https://github.com/Anubhavdxt/scrap/discussions") }
                linkTile("exclamationmark.bubble", "Report an issue", "Something broken?") { open("https://github.com/Anubhavdxt/scrap/issues/new/choose") }
            }

            Button {
                model.showSayHi = true
                NotificationCenter.default.post(name: .toggleSettings, object: nil) // closes this pane
            } label: {
                Label("Say hi", systemImage: "hand.wave").font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
            }
            .controlSize(.regular)

            Text("Open source (MIT). Your pads are plain files; nothing leaves your Mac.").font(.system(size: 11)).foregroundStyle(dim)
                .frame(maxWidth: .infinity)
        }
    }

    /// The icon in use: the chosen Dock icon, else the app's own, else a drawn stand-in (never a generic folder).
    @ViewBuilder private var logo: some View {
        if let image = AppIcons.image(appIcon) ?? AppIcons.image(AppIcons.default) {
            Image(nsImage: image).resizable().shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: [Color(red: 0.14, green: 0.33, blue: 0.48), Color(red: 0.05, green: 0.13, blue: 0.21)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().fill(Color(red: 0.98, green: 0.96, blue: 0.91)).frame(width: 40, height: 46).rotationEffect(.degrees(-5)))
        }
    }

    /// The seven pad colours; click one to jump to that pad.
    private var padDots: some View {
        HStack(spacing: 7) {
            ForEach(1...7, id: \.self) { n in
                Button {
                    model.open(number: n)
                    NotificationCenter.default.post(name: .toggleSettings, object: nil)
                } label: {
                    Circle().fill(PadColors.color(for: n)).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(.white.opacity(n == model.pad.number ? 0.9 : 0), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help("Pad \(n)")
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(theme.isDark ? 0.28 : 0.08)))
    }

    private func linkTile(_ icon: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(accent.opacity(0.16)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(dim)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(fg.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    @Local private var monitor: Any?

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
