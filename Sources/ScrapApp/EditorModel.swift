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
    /// The editor's current selection, for the footer's counts.
    @Published var selection = NSRange(location: 0, length: 0)
    @Published private(set) var folder: URL
    @Published private(set) var error: String?
    /// A short, non-error message (for example after merging a sync conflict).
    @Published private(set) var notice: String?
    @Published var showPalette = false
    @Published var showClear = false
    /// The `*` symbol picker is open.
    @Published var showSymbols = false
    @Published var showSayHi: Bool

    private var store: PadStore
    private var lastSaved = ""
    private var saveTask: Task<Void, Never>?
    private var watcher: FolderWatcher?
    private var noticeTask: Task<Void, Never>?
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
        self.folder = store.folder
        self.text = text
        self.lastSaved = text
        self.error = startupError
        self.showSayHi = !UserDefaults.standard.bool(forKey: "sayHiDone")
        resolveConflicts()
        refreshPads()
        startWatching()
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

    /// Switches to another pad folder (nil = the default). Files in the old folder are left where they are.
    func setFolder(_ url: URL?) {
        flush()
        do {
            try Config.setFolder(url)
            store = try PadStore(folder: Config.folder(), count: Config.padCount())
            folder = store.folder
            startWatching()
            resolveConflicts()
            refreshPads()
            let current = store.pad(pad.number) ?? store.pad(1)!
            pad = current
            let content = (try? store.read(current)) ?? ""
            lastSaved = content
            text = content
            error = nil
        } catch { report("Couldn't change folder: \(error.localizedDescription)") }
    }

    private func startWatching() {
        watcher = FolderWatcher(folder: store.folder) { [weak self] in
            MainActor.assumeIsolated { self?.folderChanged() }
        }
    }

    /// Closes the say-hi screen for good. A nil entry means the user skipped.
    func finishSayHi(_ entry: HelloEntry?) {
        if let entry {
            do { try HelloStore().save(entry) } catch { report("Couldn't save your note: \(error.localizedDescription)") }
        }
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        showSayHi = false
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
        resolveConflicts()
        refreshPads()
        // Pick up external edits unless there are unsaved local changes.
        guard text == lastSaved, let disk = try? store.read(pad), disk != lastSaved else { return }
        lastSaved = disk
        text = disk
    }

    /// Merges sync conflict copies into their pads, keeping both versions.
    private func resolveConflicts() {
        flush() // never merge into a pad that has unsaved edits
        guard let changed = try? ConflictResolver.resolve(in: store), !changed.isEmpty else { return }
        let names = changed.map(String.init).joined(separator: ", ")
        show(notice: changed.count == 1 ? "Sync conflict in pad \(names): kept both versions" : "Sync conflicts in pads \(names): kept both versions")
    }

    private func show(notice message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}
