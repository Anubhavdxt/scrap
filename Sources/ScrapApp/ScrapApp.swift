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
        }
    }
}
