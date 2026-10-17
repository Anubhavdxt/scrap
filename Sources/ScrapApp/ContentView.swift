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
    static let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    static func color(for number: Int) -> Color { palette[(number - 1) % palette.count] }
}

struct ContentView: View {
    static let size = CGSize(width: 380, height: 440)

    @ObservedObject var model: EditorModel
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme {
        let dark = appearance == .auto ? colorScheme == .dark : appearance == .dark
        return Themes.theme(family: family, dark: dark)
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model, family: $family, appearance: $appearance)
                .background(Color(nsColor: NSColor(hex: theme.background)))
            Divider()
            EditorView(text: $model.text, theme: theme)
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: NSColor(hex: theme.background)))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background { shortcuts }
        .overlay { overlays }
        .onChange(of: model.showPalette) { _, open in if !open { refocus() } }
        .onChange(of: model.showClear) { _, open in if !open { refocus() } }
    }

    private func refocus() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .focusEditor, object: nil) }
    }

    /// Hidden buttons carry the keyboard shortcuts; the popover has no menu bar of its own.
    private var shortcuts: some View {
        Group {
            Button("Quick Switch") { model.showPalette = true }.keyboardShortcut("k")
            ForEach(1...min(model.padCount, 9), id: \.self) { n in
                Button("Pad \(n)") { model.open(number: n) }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }
            Button("Clear Pad") { model.showClear = true }.keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var overlays: some View {
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
    @Binding var family: String
    @Binding var appearance: Appearance

    var body: some View {
        ZStack {
            PadDots(model: model)
            HStack {
                Spacer()
                Menu {
                    Picker("Theme", selection: $family) {
                        ForEach(Themes.families, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.inline)
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Quick Switch…  ⌘K") { model.showPalette = true }
                    Button("Clear Pad…  ⇧⌘⌫") { model.showClear = true }
                    Divider()
                    Button("Settings…") {
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    Button("Quit scrap") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }
}

struct PadDots: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.pads) { pad in
                let current = pad.number == model.pad.number
                let color = PadColors.color(for: pad.number)
                Circle()
                    .fill(pad.isEmpty ? Color.clear : color)
                    .overlay(Circle().stroke(color, lineWidth: current ? 2.5 : 1.5))
                    .frame(width: current ? 14 : 11, height: current ? 14 : 11)
                    .contentShape(Circle().inset(by: -4))
                    .help(pad.isEmpty ? "Pad \(pad.number)" : "Pad \(pad.number): \(pad.preview)")
                    .onTapGesture { model.open(pad) }
            }
        }
    }
}
