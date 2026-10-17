import ScrapCore
import AppKit
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct ContentView: View {
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
            EditorView(text: $model.text, theme: theme)
            VStack(spacing: 4) {
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                PadDots(model: model, accent: Color(nsColor: NSColor(hex: theme.accent)))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: NSColor(hex: theme.background)))
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowAccessor())
        .navigationTitle(model.pad.name)
        .sheet(isPresented: $model.showPalette) { PaletteView(model: model) }
        .confirmationDialog("Clear “\(model.pad.name)”? This can't be undone.", isPresented: $model.showClear) {
            Button("Clear Pad", role: .destructive) { model.clearCurrent() }
        }
    }
}

struct PadDots: View {
    @ObservedObject var model: EditorModel
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.pads) { pad in
                let current = pad.number == model.pad.number
                Circle()
                    .fill(pad.isEmpty ? Color.clear : accent)
                    .overlay(Circle().stroke(accent.opacity(current ? 1 : 0.5), lineWidth: current ? 2 : 1))
                    .frame(width: current ? 11 : 9, height: current ? 11 : 9)
                    .contentShape(Circle().inset(by: -4))
                    .help(pad.isEmpty ? "Pad \(pad.number)" : "Pad \(pad.number): \(pad.preview)")
                    .onTapGesture { model.open(pad) }
            }
        }
    }
}

@main
struct ScrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = EditorModel()
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto

    var body: some Scene {
        Window("scrap", id: "main") {
            ContentView(model: model)
        }
        MenuBarExtra("scrap", systemImage: "note.text") {
            Button("Show scrap") { WindowController.shared.show() }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit scrap") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings { SettingsView(model: model) }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Quick Switch…") { model.showPalette = true }.keyboardShortcut("k")
                Divider()
                ForEach(1...min(model.padCount, 9), id: \.self) { n in
                    Button("Pad \(n)") { model.open(number: n) }
                        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
                Divider()
                Button("Clear Pad…") { model.showClear = true }.keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
            CommandMenu("Theme") {
                Picker("Theme", selection: $family) {
                    ForEach(Themes.families, id: \.id) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
                Divider()
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
