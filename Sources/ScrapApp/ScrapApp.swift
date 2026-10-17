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
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color(nsColor: NSColor(hex: theme.background)))
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .background(WindowAccessor())
        .navigationTitle(model.pad.name)
        .sheet(isPresented: $model.showPalette) { PaletteView(model: model) }
        .sheet(isPresented: $model.showRename) { RenameView(model: model) }
        .confirmationDialog("Move “\(model.pad.name)” to the Trash?", isPresented: $model.showDelete) {
            Button("Move to Trash", role: .destructive) { model.deleteCurrent() }
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
            Button("New Pad") {
                model.newPad()
                WindowController.shared.show()
            }
            Divider()
            Button("Quit scrap") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Pad") { model.newPad() }.keyboardShortcut("n")
                Button("Quick Switch…") { model.showPalette = true }.keyboardShortcut("k")
                Divider()
                Button("Rename Pad…") { model.showRename = true }.keyboardShortcut("r")
                Button("Move Pad to Trash…") { model.showDelete = true }.keyboardShortcut(.delete, modifiers: [.command, .shift])
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
