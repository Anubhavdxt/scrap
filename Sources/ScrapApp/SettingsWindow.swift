import AppKit
import ScrapCore
import SwiftUI

/// The settings window, created on first use. Nothing opens at launch.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: .shared)))
            w.title = "scrap Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: EditorModel
    @AppStorage("themeFamily") private var family = "cobalt2"
    @AppStorage("appearance") private var appearance = Appearance.auto

    var body: some View {
        Form {
            Section("Pads") {
                Stepper(
                    "Number of pads: \(model.padCount)",
                    value: Binding(get: { model.padCount }, set: { model.setPadCount($0) }),
                    in: 1...Config.maxPads
                )
                Text("Lowering this hides pads, it never deletes them.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Folder", value: Config.folder().path).textSelection(.enabled)
            }
            Section("Look") {
                Picker("Theme", selection: $family) {
                    ForEach(Themes.families, id: \.id) { Text($0.name).tag($0.id) }
                }
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Shortcuts") {
                LabeledContent("Show or hide scrap", value: "⌃⌥Space")
                LabeledContent("Quick switch", value: "⌘K")
                LabeledContent("Go to pad 1 to 9", value: "⌘1 to ⌘9")
                LabeledContent("Clear pad", value: "⇧⌘⌫")
            }
            Section {
                Button("Quit scrap") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 500)
    }
}
