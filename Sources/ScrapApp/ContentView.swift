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
    @AppStorage("fontFamily") private var fontFamily = ""
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("colorHighlights") private var colorHighlights = true
    @AppStorage("markers") private var markers = "hide"
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { resolveTheme(family: family, appearance: appearance, colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .background(Color(nsColor: NSColor(hex: theme.background)))
            Divider()
            EditorView(text: $model.text, theme: theme, fontSize: fontSize, fontFamily: fontFamily, wrap: wrapLines,
                       colorHighlights: colorHighlights, markers: markers)
            Divider()
            StatusLine(model: model)
                .background(Color(nsColor: NSColor(hex: theme.background)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                if windowed {
                    // Room for the window's traffic lights, which sit over this bar.
                    Color.clear.frame(width: 62, height: 1)
                } else {
                    Button { NotificationCenter.default.post(name: .closePopover, object: nil) } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help("Close")
                }
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
    }
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

    private var stats: String {
        let text = model.text
        let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        let words = text.split(whereSeparator: \.isWhitespace).count
        return "\(lines) \(lines == 1 ? "line" : "lines") · \(words) \(words == 1 ? "word" : "words") · \(text.count) characters"
    }

    /// When the current pad's file was last written, if it has been.
    private var savedAt: Date? {
        guard let date = model.pads.first(where: { $0.number == model.pad.number })?.modified, date > .distantPast else { return nil }
        return date
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(PadColors.color(for: model.pad.number)).frame(width: 8, height: 8)
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
                    // Re-evaluated every 20 seconds so "just now" ages into "1 min ago".
                    TimelineView(.periodic(from: .now, by: 20)) { context in
                        Text("Saved \(RelativeTime.text(for: savedAt, now: context.date))").lineLimit(1).fixedSize()
                    }
                }
            }
        }
    }
}

/// Format menu, task and share buttons at the right of the footer (the same commands as the keyboard shortcuts).
struct FooterButtons: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 10) {
            Button { run(.task) } label: { Image(systemName: "checklist") }
                .help("Make this line a task (⌃8)")
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
