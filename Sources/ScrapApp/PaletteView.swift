import ScrapCore
import SwiftUI

struct PaletteView: View {
    @ObservedObject var model: EditorModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var items: [Pad] {
        Fuzzy.rank(query, model.pads, by: { "\($0.number) \($0.preview)" })
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Switch to a pad", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .monospaced))
                .padding(12)
                .focused($focused)
                .onSubmit(activate)
                .onChange(of: query) { selection = 0 }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, pad in
                            row(pad, selected: index == selection)
                                .id(index)
                                .onTapGesture { selection = index; activate() }
                        }
                    }
                }
                .onChange(of: selection) { proxy.scrollTo(selection) }
            }
        }
        .frame(width: 480, height: 320)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { model.showPalette = false; return .handled }
    }

    private func row(_ pad: Pad, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(pad.number)").foregroundStyle(.secondary).frame(minWidth: 20, alignment: .trailing)
            if pad.isEmpty {
                Text("empty").foregroundStyle(.tertiary)
            } else {
                Text(pad.preview).lineLimit(1)
            }
            Spacer()
            if pad.number == model.pad.number { Text("open").font(.caption).foregroundStyle(.secondary) }
        }
        .font(.system(.body, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    private func activate() {
        let list = items
        guard list.indices.contains(selection) else { return }
        model.showPalette = false
        model.open(list[selection])
    }
}

struct SettingsView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        Form {
            Stepper(
                "Number of pads: \(model.padCount)",
                value: Binding(get: { model.padCount }, set: { model.setPadCount($0) }),
                in: 1...Config.maxPads
            )
            Text("Lowering this hides pads, it never deletes them.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Folder", value: Config.folder().path)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 420)
    }
}
