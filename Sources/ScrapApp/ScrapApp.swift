import SwiftUI

@main
struct ScrapApp: App {
    @StateObject private var model = EditorModel()

    var body: some Scene {
        WindowGroup("scrap") {
            VStack(spacing: 0) {
                EditorView(text: $model.text)
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.red).padding(6)
                }
            }
            .frame(minWidth: 480, minHeight: 320)
            .navigationTitle(model.pad.name)
            .sheet(isPresented: $model.showPalette) { PaletteView(model: model) }
            .sheet(isPresented: $model.showRename) { RenameView(model: model) }
            .confirmationDialog("Move “\(model.pad.name)” to the Trash?", isPresented: $model.showDelete) {
                Button("Move to Trash", role: .destructive) { model.deleteCurrent() }
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Pad") { model.newPad() }.keyboardShortcut("n")
                Button("Quick Switch…") { model.showPalette = true }.keyboardShortcut("k")
                Divider()
                Button("Rename Pad…") { model.showRename = true }.keyboardShortcut("r")
                Button("Move Pad to Trash…") { model.showDelete = true }.keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }
    }
}
