import ScrapCore
import SwiftUI

/// ⌘K / ⌘F: search the text of every pad.
struct SearchView: View {
    @ObservedObject var model: EditorModel
    @StateObject private var search: SearchModel

    init(model: EditorModel) {
        self.model = model
        _search = StateObject(wrappedValue: SearchModel(pads: { model.padTexts() }))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                SearchField(text: $search.query, placeholder: "Search all pads",
                            onMove: search.move, onSubmit: activate, onCancel: { model.showSearch = false })
                    .frame(height: 22)
            }
            .padding(12)
            Divider()
            content
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var content: some View {
        if search.isBlank {
            note("Type to search every pad")
        } else if search.result.hits.isEmpty {
            note("No matches")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if search.result.isClosest {
                            Text("Closest matches").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                        }
                        ForEach(Array(search.result.hits.enumerated()), id: \.element.id) { index, hit in
                            row(hit, selected: index == search.selection)
                                .id(index)
                                .onTapGesture { search.selection = index; activate() }
                        }
                    }
                }
                .onChange(of: search.selection) { _, new in proxy.scrollTo(new) }
            }
            .frame(maxHeight: 240)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 14)
    }

    private func row(_ hit: SearchHit, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(PadColors.color(for: hit.pad)).frame(width: 8, height: 8).padding(.top, 5).help("Pad \(hit.pad)")
            VStack(alignment: .leading, spacing: 2) {
                Text(highlighted(hit)).lineLimit(1)
                if !hit.context.isEmpty {
                    Text(hit.context).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear)
        .contentShape(Rectangle())
    }

    private func highlighted(_ hit: SearchHit) -> AttributedString {
        var text = AttributedString(hit.text)
        let ns = hit.text as NSString
        for range in hit.matches where NSMaxRange(range) <= ns.length {
            guard let r = Range(range, in: hit.text), let a = AttributedString.Index(r.lowerBound, within: text),
                  let b = AttributedString.Index(r.upperBound, within: text) else { continue }
            text[a..<b].font = .system(size: 13, weight: .bold)
            text[a..<b].backgroundColor = Color.accentColor.opacity(0.3)
        }
        return text
    }

    private func activate() {
        if let hit = search.selected { model.openResult(hit) }
    }
}
