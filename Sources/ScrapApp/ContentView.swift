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
    /// Blur radius, in points, of the editor behind an open search panel.
    static let searchBlur: CGFloat = 1.2
    @ObservedObject var model: EditorModel
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto
    @AppStorage("fontSize") private var fontSize = EditorFont.defaultSize
    @AppStorage("fontFamily") private var fontFamily = EditorFont.systemFamily
    @AppStorage("rendered") private var rendered = true
    @AppStorage("wrapLines") private var wrapLines = true
    @AppStorage("colorHighlights") private var colorHighlights = true
    @AppStorage("colorChips") private var colorChips = true
    @AppStorage("markers") private var markers = "hide"
    @AppStorage("vibrant") private var vibrant = false
    @AppStorage("customBullets") private var customBullets = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scrapWindowed) private var windowed

    private var theme: Theme { resolveTheme(family: family, appearance: appearance, colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .background(Color(nsColor: NSColor(hex: theme.background)))   // solid: only the editor is see-through
            Divider()
            EditorView(text: $model.text, theme: theme, fontSize: fontSize, fontFamily: fontFamily, wrap: wrapLines,
                       colorHighlights: colorHighlights, colorChips: colorChips, markers: markers, rendered: rendered,
                       selectionColor: PadColors.nsColor(for: model.pad.number), selection: $model.selection, customBullets: customBullets,
                       vibrant: vibrant, blur: model.showSearch ? Self.searchBlur : 0)
            Divider()
            StatusLine(model: model)
                .background(footerBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A touch of blur on what is behind the search panel, so it reads as the thing in front.
        .blur(radius: model.showSearch ? Self.searchBlur : 0)
        .animation(.easeOut(duration: 0.15), value: model.showSearch)
        // In a window the content runs under the (empty, transparent) title strip, so the top bar is the only bar.
        .ignoresSafeArea(.container, edges: windowed ? .top : [])
        .background { if vibrant { VibrantBackdrop() } }
        .background { shortcuts }
        .overlay { overlays }
        .onChange(of: model.showSearch) { _, open in if !open { refocus() } }
        .onChange(of: model.showClear) { _, open in if !open { refocus() } }
        .onChange(of: model.showSayHi) { _, open in if !open { refocus() } }
    }

    /// The theme's background, with a little of the open pad's colour in it.
    private var footerBackground: Color {
        let base = NSColor(hex: theme.background)
        let tinted = FooterTint.color(background: base, pad: PadColors.nsColor(for: model.pad.number), strength: theme.isDark ? 0.18 : 0.14)
        return Color(nsColor: tinted)   // solid, like the top bar
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
            Button("Search") { model.showSearch = true }.keyboardShortcut("k")
            Button("Find") { model.showSearch = true }.keyboardShortcut("f")
            Button("Next Pad") { model.step(1) }.keyboardShortcut("]")
            Button("Previous Pad") { model.step(-1) }.keyboardShortcut("[")
            Button("Next Pad (Tab)") { model.step(1) }.keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Pad (Tab)") { model.step(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift])
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
        if model.showSearch {
            ZStack {
                Color.black.opacity(0.3).onTapGesture { model.showSearch = false }
                VStack {
                    SearchView(model: model)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 12)
                        .padding(.top, 56)
                    Spacer(minLength: 0)
                }
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
    @AppStorage("windowFloating") private var windowFloating = false

    private var canAttach: Bool { iconMode != .dock }

    var body: some View {
        ZStack {
            PadDots(model: model)
            HStack(spacing: 12) {
                Button { NotificationCenter.default.post(name: .closePopover, object: nil) } label: {
                    Image(systemName: "xmark.circle")
                }
                .help(windowed ? (canAttach ? "Close the window (back to the menu bar dropdown)" : "Hide the window") : "Close")
                Spacer()
                Button { model.showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Search all pads (⌘K)")
                if windowed {
                    // Keeps the window above other windows. (Dragging the popover's top bar is what turns it into a window.)
                    Button { windowFloating.toggle() } label: {
                        Image(systemName: windowFloating ? "pin.fill" : "pin")
                    }
                    .help(windowFloating ? "Stop keeping this window above others" : "Keep this window above other windows")
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
        .background { if windowed { WindowDragHandle() } else if canAttach { DetachDragHandle() } }
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

/// Dragging the popover by its top bar pulls it off the menu bar icon into a window, as Tot's does.
struct DetachDragHandle: NSViewRepresentable {
    final class DragView: NSView {
        private var start: NSPoint?
        private var fired = false
        override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; fired = false }
        override func mouseUp(with event: NSEvent) { start = nil }
        override func mouseDragged(with event: NSEvent) {
            guard !fired, let start, DetachDrag.shouldDetach(from: start, to: NSEvent.mouseLocation) else { return }
            fired = true
            NotificationCenter.default.post(name: .detachDrag, object: event)
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// When a press-and-drag on the popover's top bar has gone far enough to count as pulling it off.
enum DetachDrag {
    static let distance: CGFloat = 8
    static func shouldDetach(from start: NSPoint, to current: NSPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= distance
    }
}

struct PadDots: View {
    @ObservedObject var model: EditorModel
    @State private var hovered: Int?
    @AppStorage("showPadNumber") private var showNumber = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.pads) { pad in dot(pad) }
        }
    }

    private func dot(_ pad: Pad) -> some View {
        let current = pad.number == model.pad.number
        let color = PadColors.color(for: pad.number)
        let style = PadDotStyle.make(current: current, empty: pad.isEmpty)
        return ZStack {
            if style.halo > 0 { Circle().fill(color.opacity(0.22)).frame(width: style.diameter + style.halo * 2, height: style.diameter + style.halo * 2) }
            Circle().fill(color.opacity(style.fillOpacity)).frame(width: style.diameter, height: style.diameter)
            if style.ringWidth > 0 {
                Circle().strokeBorder(color.opacity(style.ringOpacity), lineWidth: style.ringWidth).frame(width: style.diameter, height: style.diameter)
            }
            if showNumber {
                Text("\(pad.number)")
                    .font(.system(size: pad.number > 9 ? 7 : 9, weight: .bold, design: .rounded))
                    .foregroundStyle(current ? Color(nsColor: PadDotStyle.numberColor(on: PadColors.nsColor(for: pad.number))) : color)
            } else if style.innerDot > 0 { Circle().fill(color).frame(width: style.innerDot, height: style.innerDot) }
        }
        .scaleEffect(hovered == pad.number && !current ? 1.15 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .animation(.spring(duration: 0.25), value: current)
        .frame(width: PadDotStyle.slot, height: PadDotStyle.slot)
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? pad.number : (hovered == pad.number ? nil : hovered) }
        .help(pad.isEmpty ? "Pad \(pad.number)" : "Pad \(pad.number): \(pad.preview)")
        .onTapGesture { model.open(pad) }
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

/// Symbols, raw/rendered and share buttons at the right of the footer. Formatting lives in the Format menu and its shortcuts.
struct FooterButtons: View {
    @ObservedObject var model: EditorModel
    @AppStorage("rendered") private var rendered = true

    var body: some View {
        HStack(spacing: 10) {
            Button { NotificationCenter.default.post(name: .toggleSymbols, object: nil) } label: { Image(systemName: "asterisk") }
                .background(SymbolButtonAnchor())
                .help("Bullets, dividers and symbols")
            Button { rendered.toggle() } label: { Image(systemName: rendered ? "eye" : "eye.slash") }
                .help(rendered ? "Show raw markdown (⌥⌘R)" : "Show rendered text (⌥⌘R)")
            ShareLink(item: model.text) { Image(systemName: "square.and.arrow.up") }
                .disabled(model.text.isEmpty)
                .help("Share this pad")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
    }
}

/// Lets the settings popover attach to the gear button. The view registers itself when it joins a window, so the
/// anchor is always the gear of whichever editor (popover or window) is on screen.
struct GearAnchor: NSViewRepresentable {
    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { SettingsAnchor.registry.register(self) }
        }
    }

    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ view: NSView, context: Context) {}
}

/// Lets the symbol picker open below the `*` button (see `GearAnchor`).
struct SymbolButtonAnchor: NSViewRepresentable {
    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil { SymbolAnchor.registry.register(self) }
        }
    }

    func makeNSView(context: Context) -> NSView { AnchorView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
