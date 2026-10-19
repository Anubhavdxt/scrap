import Foundation
import ScrapCore

/// The state behind the search panel. Typing starts a search after a short pause, off the main thread; only the answer
/// to the latest query is ever shown, however the searches finish.
@MainActor
final class SearchModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { start() } }
    }
    @Published private(set) var result = SearchResult.empty
    @Published var selection = 0

    private let pads: () -> [(number: Int, text: String)]
    private let debounce: Duration
    /// The pads are read once, at the first search, not on every keystroke.
    private var snapshot: [(number: Int, text: String)]?
    /// How many searches have actually run (for tests).
    private(set) var searches = 0
    private var generation = 0
    private var task: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(120), pads: @escaping () -> [(number: Int, text: String)]) {
        self.debounce = debounce
        self.pads = pads
    }

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
        task = Task { [weak self] in
            // Wait for a pause in the typing; the pads are read, and the search run, only then.
            if let wait = self?.debounce, wait > .zero { try? await Task.sleep(for: wait) }
            guard let self, !Task.isCancelled, mine == self.generation else { return }
            let texts = self.snapshot ?? self.pads()
            self.snapshot = texts
            self.searches += 1
            let found = await Task.detached(priority: .userInitiated) { PadSearch.search(q, in: texts) }.value
            guard !Task.isCancelled, mine == self.generation else { return }
            self.result = found
            self.selection = 0
        }
    }
}
