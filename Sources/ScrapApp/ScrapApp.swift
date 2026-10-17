import SwiftUI
import ScrapCore

@main
struct ScrapApp: App {
    @State private var text = ""

    var body: some Scene {
        WindowGroup("scrap") {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
