import Foundation

public enum PadStoreError: LocalizedError {
    case invalidName
    case exists(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Pad name can't be empty."
        case .exists(let name): "A pad named \"\(name)\" already exists."
        }
    }
}

public final class PadStore {
    public let folder: URL
    private let fm = FileManager.default

    public init(folder: URL) throws {
        self.folder = folder
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Pads sorted by most recently modified first.
    public func list() throws -> [Pad] {
        let urls = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "md" }
            .map { Pad(url: $0, modified: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            .sorted { $0.modified > $1.modified }
    }

    @discardableResult
    public func create(name: String = "untitled") throws -> Pad {
        var url = folder.appendingPathComponent("\(name).md")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n).md")
            n += 1
        }
        try Data().write(to: url, options: .atomic)
        return Pad(url: url, modified: Date())
    }

    public func read(_ pad: Pad) throws -> String {
        try String(contentsOf: pad.url, encoding: .utf8)
    }

    public func write(_ text: String, to pad: Pad) throws {
        try text.write(to: pad.url, atomically: true, encoding: .utf8)
    }

    public static func sanitize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    public func rename(_ pad: Pad, to newName: String) throws -> Pad {
        let name = Self.sanitize(newName)
        guard !name.isEmpty, !name.hasPrefix(".") else { throw PadStoreError.invalidName }
        let dest = folder.appendingPathComponent("\(name).md")
        if dest == pad.url { return pad }
        // Case-only renames are the same file on case-insensitive volumes.
        if fm.fileExists(atPath: dest.path), dest.path.lowercased() != pad.url.path.lowercased() {
            throw PadStoreError.exists(name)
        }
        try fm.moveItem(at: pad.url, to: dest)
        return Pad(url: dest, modified: pad.modified)
    }

    /// Moves the pad to the Trash.
    ///
    /// `trashItem` fails with a permission error for files in iCloud Drive when the app has no
    /// Trash access, so fall back to moving the file into ~/.Trash directly.
    public func delete(_ pad: Pad, trash: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")) throws {
        do {
            try fm.trashItem(at: pad.url, resultingItemURL: nil)
        } catch {
            try moveToFolder(pad.url, folder: trash)
        }
    }

    func moveToFolder(_ url: URL, folder: URL) throws {
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var dest = folder.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        try fm.moveItem(at: url, to: dest)
    }
}
