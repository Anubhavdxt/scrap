import AppKit
import ScrapCore
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Each pad has its own colour, repeating after seven.
enum PadColors {
    static let palette: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple, .systemPink]
    static func nsColor(for number: Int) -> NSColor { palette[(max(number, 1) - 1) % palette.count] }
    static func color(for number: Int) -> Color { Color(nsColor: nsColor(for: number)) }
}

func resolveTheme(family: String, appearance: Appearance, colorScheme: ColorScheme) -> Theme {
    let dark = appearance == .auto ? colorScheme == .dark : appearance == .dark
    return Themes.theme(family: family, dark: dark)
}

struct ContentView: View {
    @ObservedObject var model: EditorModel
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto
    @AppStorage("fontSize") private var fontSize = EditorFont.defaultSize
    @AppStorage("fontFamily") private var fontFamily = EditorFont.systemFamily
    @AppStorage("rendered") private var rendered = true
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("colorHighlights") private var colorHighlights = true
    @AppStorage("markers") private var markers = "hide"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scrapWindowed) private var windowed

    private var theme: Theme { resolveTheme(family: family, appearance: appearance, colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .background(Color(nsColor: NSColor(hex: theme.background)))
            Divider()
            EditorView(text: $model.text, theme: theme, fontSize: fontSize, fontFamily: fontFamily, wrap: wrapLines,
                       colorHighlights: colorHighlights, markers: markers, rendered: rendered,
                       selectionColor: PadColors.nsColor(for: model.pad.number), selection: $model.selection)
            Divider()
            StatusLine(model: model)
                .background(Color(nsColor: NSColor(hex: theme.background)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // In a window the content runs under the (empty, transparent) title strip, so the top bar is the only bar.
        .ignoresSafeArea(.container, edges: windowed ? .top : [])
        .background { shortcuts }
        .overlay { overlays }
        .onChange(of: model.showPalette) { _, open in if !open { refocus() } }
        .onChange(of: model.showClear) { _, open in if !open { refocus() } }
        .onChange(of: model.showSayHi) { _, open in if !open { refocus() } }
    }

    private func refocus() {
        DispatchQueue.main.async {
            guard !model.showSayHi else { return }
            NotificationCenter.default.post(name: .focusEditor, object: nil)
        }
    }

    /// Hidden buttons carry the keyboard shortcuts; the popover has no menu bar of its own.
    private var shortcuts: some View {
        Group {
            Button("Quick Switch") { model.showPalette = true }.keyboardShortcut("k")
            ForEach(1...min(model.padCount, 9), id: \.self) { n in
                Button("Pad \(n)") { model.open(number: n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("Increase Font Size") { MainMenu.Actions.shared.biggerFont() }.keyboardShortcut("=")
            Button("Clear Pad") { model.showClear = true }.keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var overlays: some View {
        if model.showSymbols {
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.001).onTapGesture { model.showSymbols = false }
                SymbolPicker(model: model).padding(.trailing, 10).padding(.bottom, 32)
            }
        }
        if model.showSayHi { SayHiView(model: model, theme: theme) }
        if model.showPalette {
            ZStack {
                Color.black.opacity(0.3).onTapGesture { model.showPalette = false }
                PaletteView(model: model)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 12)
            }
        }
        if model.showClear {
            ZStack {
                Color.black.opacity(0.3).onTapGesture { model.showClear = false }
                VStack(spacing: 12) {
                    Text("Clear “\(model.pad.name)”?").font(.headline)
                    Text("This can't be undone.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel") { model.showClear = false }.keyboardShortcut(.cancelAction)
                        Button("Clear Pad", role: .destructive) {
                            model.clearCurrent()
                            model.showClear = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 12)
            }
        }
    }
}

struct TopBar: View {
    @ObservedObject var model: EditorModel
    @Environment(\.scrapWindowed) private var windowed
    @AppStorage("iconMode") private var iconMode = IconMode.menuBar

    private var canAttach: Bool { iconMode != .dock }

    var body: some View {
        ZStack {
            PadDots(model: model)
            HStack(spacing: 12) {
                Button { NotificationCenter.default.post(name: .closePopover, object: nil) } label: {
                    Image(systemName: "xmark.circle")
                }
                .help(windowed ? "Hide the window" : "Close")
                Spacer()
                if canAttach {
                    // Detach the popover into a window, or attach the window back to the menu bar icon.
                    Button { NotificationCenter.default.post(name: .toggleDetach, object: nil) } label: {
                        Image(systemName: windowed ? "pin.fill" : "pin")
                    }
                    .help(windowed ? "Attach to the menu bar icon" : "Keep as a window")
                }
                Button { NotificationCenter.default.post(name: .toggleSettings, object: nil) } label: {
                    Image(systemName: "gearshape")
                }
                .background(GearAnchor())
                .help("Settings (⌘,)")
            }
            .buttonStyle(.plain)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background { if windowed { WindowDragHandle() } }
    }
}

/// Lets the empty parts of the top bar drag the window (the window has no title bar of its own to grab).
struct WindowDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

struct PadDots: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 9) {
            ForEach(model.pads) { pad in
                let current = pad.number == model.pad.number
                let color = PadColors.color(for: pad.number)
                Circle()
                    .fill(current ? color : Color.clear)
                    .overlay(Circle().stroke(color, lineWidth: 2.5))
                    .overlay {
                        // A small dot marks a pad that has content.
                        if !pad.isEmpty && !current { Circle().fill(color).frame(width: 4, height: 4) }
                    }
                    .frame(width: 14, height: 14)
                    .contentShape(Circle().inset(by: -4))
                    .help(pad.isEmpty ? "Pad \(pad.number)" : "Pad \(pad.number): \(pad.preview)")
                    .onTapGesture { model.open(pad) }
            }
        }
    }
}

struct StatusLine: View {
    @ObservedObject var model: EditorModel

    private var selectedText: String? {
        let r = model.selection
        let text = model.text as NSString
        guard r.length > 0, r.upperBound <= text.length else { return nil }
        return text.substring(with: r)
    }

    private var stats: String {
        if let selected = selectedText { return TextStats.summary(selected, selection: true) }
        return TextStats.summary(model.text)
    }

    /// When the current pad's file was last written, if it has been.
    private var savedAt: Date? {
        guard let date = model.pads.first(where: { $0.number == model.pad.number })?.modified, date > .distantPast else { return nil }
        return date
    }

    var body: some View {
        let color = PadColors.color(for: model.pad.number)
        HStack(spacing: 8) {
            // The dot is solid for the pad, and a pale ring while text is selected (the counts are then the selection's).
            Circle()
                .fill(selectedText == nil ? color : color.opacity(0.25))
                .overlay(Circle().stroke(color, lineWidth: selectedText == nil ? 0 : 1.5))
                .frame(width: 8, height: 8)
            ViewThatFits(in: .horizontal) {
                message(showSaved: true)
                message(showSaved: false)
            }
            Spacer(minLength: 4)
            FooterButtons(model: model)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    @ViewBuilder private func message(showSaved: Bool) -> some View {
        if let error = model.error {
            Text(error).foregroundStyle(.red).lineLimit(1)
        } else if let notice = model.notice {
            Text(notice).foregroundStyle(.orange).lineLimit(1)
        } else {
            HStack(spacing: 8) {
                Text(stats).lineLimit(1).fixedSize()
                if showSaved, let savedAt {
                    Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 12)
                    // Re-evaluated every 20 seconds so "just now" ages into "1 min ago".
                    TimelineView(.periodic(from: .now, by: 20)) { context in
                        Text(RelativeTime.sentence(for: savedAt, now: context.date)).lineLimit(1).fixedSize()
                    }
                }
            }
        }
    }
}

/// Format menu, task and share buttons at the right of the footer (the same commands as the keyboard shortcuts).
struct FooterButtons: View {
    @ObservedObject var model: EditorModel
    @AppStorage("rendered") private var rendered = true

    var body: some View {
        HStack(spacing: 10) {
            Button { model.showSymbols.toggle() } label: { Image(systemName: "asterisk") }
                .help("Bullets, dividers and symbols")
            Button { rendered.toggle() } label: { Image(systemName: rendered ? "eye" : "eye.slash") }
                .help(rendered ? "Show raw Markdown, with all the marks visible (⌥⌘R)" : "Show rendered text (⌥⌘R)")
            Menu {
                Button("Bold  ⌘B") { run(.bold) }
                Button("Italic  ⌘I") { run(.italic) }
                Button("Strikethrough  ⇧⌘X") { run(.strikethrough) }
                Button("Code  ⌘E") { run(.code) }
                Divider()
                Button("Divider  ⌃−") { run(.divider) }
                Button("Check or uncheck task  ⌘↩") { run(.checkbox) }
            } label: {
                Image(systemName: "textformat")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Format")
            ShareLink(item: model.text) { Image(systemName: "square.and.arrow.up") }
                .disabled(model.text.isEmpty)
                .help("Share this pad")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }

    private func run(_ command: EditorCommand) {
        command.post()
        DispatchQueue.main.async { NotificationCenter.default.post(name: .focusEditor, object: nil) }
    }
}

/// Lets the settings popover attach to the gear button. The view registers itself when it joins a window, so the
/// anchor is always the gear of whichever editor (popover or window) is on screen.
struct GearAnchor: NSViewRepresentable {
    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { SettingsAnchor.view = self }
        }
    }

    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
