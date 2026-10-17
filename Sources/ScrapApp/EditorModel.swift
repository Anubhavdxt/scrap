import AppKit
import ScrapCore

@MainActor
final class EditorModel: ObservableObject {
    @Published var text = "" {
        didSet { if text != lastSaved { scheduleSave() } }
    }
    @Published private(set) var pads: [Pad] = []
    @Published private(set) var pad: Pad
    @Published private(set) var error: String?
    @Published var showPalette = false
    @Published var showRename = false
    @Published var showDelete = false

    private let store: PadStore
    private var lastSaved = ""
    private var saveTask: Task<Void, Never>?
    private var watcher: FolderWatcher?

    init() {
        var startupError: String?
        var store: PadStore
        do {
            store = try PadStore(folder: Config.folder())
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
        refreshPads()
        watcher = FolderWatcher(folder: store.folder) { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    // MARK: Pads

    func open(_ target: Pad) {
        flush()
        guard let content = try? store.read(target) else { return report("Couldn't open \(target.name)") }
        pad = target
        lastSaved = content
        text = content
    }

    func newPad(named name: String? = nil) {
        flush()
        do {
            let created = try store.create(name: name.map(PadStore.sanitize).flatMap { $0.isEmpty ? nil : $0 } ?? "untitled")
            refreshPads()
            open(created)
        } catch { report(error.localizedDescription) }
    }

    func rename(to newName: String) {
        flush()
        do {
            pad = try store.rename(pad, to: newName)
            refreshPads()
        } catch { report(error.localizedDescription) }
    }

    func deleteCurrent() {
        saveTask?.cancel()
        do {
            try store.delete(pad)
            refreshPads()
            if let next = pads.first { open(next) } else { newPad() }
        } catch { report("Delete failed: \(error.localizedDescription)") }
    }

    private func refreshPads() {
        pads = (try? store.list()) ?? []
    }

    private func report(_ message: String) { error = message }

    // MARK: Saving

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

    // MARK: External changes

    private func folderChanged() {
        refreshPads()
        guard FileManager.default.fileExists(atPath: pad.url.path) else {
            // Current pad vanished (deleted or moved elsewhere).
            lastSaved = text
            if let next = pads.first { open(next) } else { newPad() }
            return
        }
        // Pick up external edits unless there are unsaved local changes.
        guard text == lastSaved, let disk = try? store.read(pad), disk != lastSaved else { return }
        lastSaved = disk
        text = disk
    }
}
