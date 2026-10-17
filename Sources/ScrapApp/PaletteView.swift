import ScrapCore
import SwiftUI

private enum PaletteItem: Identifiable {
    case pad(Pad)
    case create(String)

    var id: String {
        switch self {
        case .pad(let p): "pad:\(p.id)"
        case .create(let n): "create:\(n)"
        }
    }
}

struct PaletteView: View {
    @ObservedObject var model: EditorModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var items: [PaletteItem] {
        let matches = Fuzzy.rank(query, model.pads, by: \.name).map(PaletteItem.pad)
        let name = PadStore.sanitize(query)
        let exact = model.pads.contains { $0.name.lowercased() == name.lowercased() }
        return name.isEmpty || exact ? matches : matches + [.create(name)]
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Switch to a pad, or type a name to create one", text: $query)
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
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, selected: index == selection)
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

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack {
            switch item {
            case .pad(let p): Text(p.name)
            case .create(let n): Text("Create “\(n)”").foregroundStyle(.secondary)
            }
            Spacer()
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
        switch list[selection] {
        case .pad(let p): model.open(p)
        case .create(let n): model.newPad(named: n)
        }
    }
}

struct RenameView: View {
    @ObservedObject var model: EditorModel
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename pad").font(.headline)
            TextField("Name", text: $name)
                .font(.system(.body, design: .monospaced))
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { model.showRename = false }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: commit).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { name = model.pad.name }
    }

    private func commit() {
        model.showRename = false
        model.rename(to: name)
    }
}
