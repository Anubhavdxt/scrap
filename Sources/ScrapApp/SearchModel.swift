import Foundation
import ScrapCore

/// The state behind the search panel. Every keystroke starts a search off the main thread; only the answer to the
/// latest query is ever shown, however the searches finish.
@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { start() } }
    }
    @Published private(set) var result = SearchResult.empty
    @Published var selection = 0

    private let pads: () -> [(number: Int, text: String)]
    /// The pads are read once, when the first query is typed, not on every keystroke.
    private var snapshot: [(number: Int, text: String)]?
    private var generation = 0
    private var task: Task<Void, Never>?

    init(pads: @escaping () -> [(number: Int, text: String)]) { self.pads = pads }

    var isBlank: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    func move(_ delta: Int) {
        guard !result.hits.isEmpty else { return }
        selection = min(max(selection + delta, 0), result.hits.count - 1)
    }

    var selected: SearchHit? { result.hits.indices.contains(selection) ? result.hits[selection] : nil }

    /// Waits for the search started by the latest query (for tests).
    func settle() async { await task?.value }

    private func start() {
        task?.cancel()
        generation += 1
        let mine = generation
        let q = query
        guard !isBlank else { result = .empty; selection = 0; return }
        let texts = snapshot ?? pads()
        snapshot = texts
        task = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { PadSearch.search(q, in: texts) }.value
            guard let self, !Task.isCancelled, mine == self.generation else { return }
            self.result = found
            self.selection = 0
        }
    }
}
