import AppKit
import ScrapCore

@MainActor
final class EditorModel: ObservableObject {
    static let shared = EditorModel()

    @Published var text = "" {
        didSet { if text != lastSaved { scheduleSave() } }
    }
    @Published private(set) var pads: [Pad] = []
    @Published private(set) var pad: Pad
    @Published private(set) var padCount: Int
    @Published private(set) var error: String?
    @Published var showPalette = false
    @Published var showClear = false

    private var store: PadStore
    private var lastSaved = ""
    private var saveTask: Task<Void, Never>?
    private var watcher: FolderWatcher?
    private static let lastPadKey = "lastPad"

    init() {
        var startupError: String?
        let count = Config.padCount()
        var store: PadStore
        do {
            store = try PadStore(folder: Config.folder(), count: count)
        } catch {
            // Fall back to a temp folder so the editor still opens.
            startupError = error.localizedDescription
            store = try! PadStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("scrap"), count: count)
        }
        let pad = store.pad(UserDefaults.standard.integer(forKey: Self.lastPadKey)) ?? store.pad(1)!
        let text = (try? store.read(pad)) ?? ""
        self.store = store
        self.pad = pad
        self.padCount = store.count
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

    func open(number: Int) {
        guard let target = store.pad(number) else { return }
        open(target)
    }

    func open(_ target: Pad) {
        flush()
        guard let content = try? store.read(target) else { return report("Couldn't open \(target.name)") }
        pad = target
        UserDefaults.standard.set(target.number, forKey: Self.lastPadKey)
        lastSaved = content
        text = content
    }

    func clearCurrent() {
        saveTask?.cancel()
        do {
            try store.clear(pad)
            lastSaved = ""
            text = ""
            refreshPads()
        } catch { report("Clear failed: \(error.localizedDescription)") }
    }

    /// Changes how many pads exist. Pads past the new count are hidden, never deleted.
    func setPadCount(_ count: Int) {
        flush()
        do {
            try Config.setPadCount(count)
            store = try PadStore(folder: store.folder, count: Config.padCount())
            padCount = store.count
            refreshPads()
            if pad.number > store.count { open(number: store.count) }
        } catch { report("Couldn't change pad count: \(error.localizedDescription)") }
    }

    private func refreshPads() {
        pads = store.list()
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
            refreshPads()
        } catch {
            self.error = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: External changes

    private func folderChanged() {
        refreshPads()
        // Pick up external edits unless there are unsaved local changes.
        guard text == lastSaved, let disk = try? store.read(pad), disk != lastSaved else { return }
        lastSaved = disk
        text = disk
    }
}
