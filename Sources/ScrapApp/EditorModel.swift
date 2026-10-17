import AppKit
import ScrapCore

@MainActor
final class EditorModel: ObservableObject {
    @Published var text = "" {
        didSet { if text != lastSaved { scheduleSave() } }
    }
    @Published private(set) var error: String?

    private let store: PadStore
    private var pad: Pad
    private var lastSaved = ""
    private var saveTask: Task<Void, Never>?
    private var watcher: FolderWatcher?

    init() {
        var startupError: String?
        var store: PadStore
        do {
            store = try PadStore(folder: Config.defaultFolder())
        } catch {
            // Fall back to a temp folder so the editor still opens.
            startupError = error.localizedDescription
            store = try! PadStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("scrap"))
        }
        let pad = (try? store.list().first) ?? (try? store.create()) ?? Pad(url: store.folder.appendingPathComponent("untitled.md"), modified: Date())
        let text = (try? store.read(pad)) ?? ""
        self.store = store
        self.pad = pad
        self.text = text
        self.lastSaved = text
        self.error = startupError
        watcher = FolderWatcher(folder: store.folder) { [weak self] in
            MainActor.assumeIsolated { self?.reloadIfClean() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled { self?.flush() }
        }
    }

    func flush() {
        saveTask?.cancel()
        guard text != lastSaved else { return }
        do {
            try store.write(text, to: pad)
            lastSaved = text
            error = nil
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }

    /// Picks up external edits (iCloud, other editors) unless there are unsaved local changes.
    private func reloadIfClean() {
        guard text == lastSaved, let disk = try? store.read(pad), disk != lastSaved else { return }
        lastSaved = disk
        text = disk
    }
}
