import SwiftUI

@main
struct ScrapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { SettingsView(model: EditorModel.shared) }
    }
}
