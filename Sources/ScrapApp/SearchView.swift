import ScrapCore
import SwiftUI

/// ⌘K / ⌘F: search the text of every pad.
struct SearchView: View {
    @ObservedObject var model: EditorModel
    @State private var query = ""
    @State private var result = SearchResult.empty
    @State private var selection = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                SearchField(text: $query, placeholder: "Search all pads",
                            onMove: move, onSubmit: activate, onCancel: { model.showSearch = false })
                    .frame(height: 22)
            }
            .padding(12)
            Divider()
            content
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: query) { _, _ in search() }
    }

    @ViewBuilder private var content: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            note("Type to search every pad")
        } else if result.hits.isEmpty {
            note("No matches")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if result.isClosest {
                            Text("Closest matches").font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
                        }
                        ForEach(Array(result.hits.enumerated()), id: \.element.id) { index, hit in
                            row(hit, selected: index == selection)
                                .id(index)
                                .onTapGesture { selection = index; activate() }
                        }
                    }
                }
                .onChange(of: selection) { _, new in proxy.scrollTo(new) }
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

    private func move(_ delta: Int) {
        guard !result.hits.isEmpty else { return }
        selection = min(max(selection + delta, 0), result.hits.count - 1)
    }

    private func activate() {
        guard result.hits.indices.contains(selection) else { return }
        model.openResult(result.hits[selection])
    }

    /// Searches off the main thread, dropping a search that has been overtaken by more typing.
    private func search() {
        task?.cancel()
        let q = query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { result = .empty; selection = 0; return }
        let pads = model.padTexts()
        task = Task {
            let found = await Task.detached(priority: .userInitiated) { PadSearch.search(q, in: pads) }.value
            if Task.isCancelled { return }
            result = found
            selection = 0
        }
    }
}
