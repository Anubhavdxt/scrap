import ScrapCore
import SwiftUI

/// Settings > Appearance: your own smart bullets (up to eight open/done pairs).
struct CustomBulletsEditor: View {
    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var open: String
        var done: String
    }

    @AppStorage("customBullets") private var stored = ""
    @Local private var rows: [Row] = []
    @Local private var message: String?
    @Local private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart bullets").font(.system(size: 13, weight: .medium))
            Text("Built in: " + SmartBullets.builtIn.map { $0.open + $0.done }.joined(separator: "  "))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    glyphField($row.open)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    glyphField($row.done)
                    Button { rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help("Remove this bullet")
                }
            }
            if let message { Text(message).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Add a bullet") { add() }.controlSize(.small).disabled(rows.count >= SmartBullets.maxCustom)
                Text("open → done. A symbol or emoji each; click a bullet in the text to flip it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard !loaded else { return }
            rows = CustomBullets.decode(stored).map { Row(open: $0.open, done: $0.done) }
            loaded = true
        }
        .onChange(of: rows) { save() }
    }

    /// One character per field: typing a new one replaces the old.
    private func glyphField(_ text: Binding<String>) -> some View {
        TextField("", text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = $0.count > 1 ? String($0.suffix(1)) : $0 }))
            .multilineTextAlignment(.center)
            .font(.system(size: 16))
            .frame(width: 48)
            .textFieldStyle(.roundedBorder)
    }

    private func add() {
        let current = CustomBullets.evaluate(rows.map { ($0.open, $0.done) }).store ?? []
        guard let next = CustomBullets.nextSuggestion(after: current) else { return }
        rows.append(Row(open: next.open, done: next.done))
    }

    private func save() {
        let result = CustomBullets.evaluate(rows.map { ($0.open, $0.done) })
        message = result.message
        if let pairs = result.store, CustomBullets.encode(pairs) != stored { stored = CustomBullets.encode(pairs) }
    }
}
