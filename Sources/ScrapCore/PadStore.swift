import Foundation

public enum PadStoreError: LocalizedError {
    case noSuchPad(Int, max: Int)

    public var errorDescription: String? {
        switch self {
        case .noSuchPad(let n, let max): "There is no pad \(n). Pads are numbered 1 to \(max)."
        }
    }
}

/// A fixed set of numbered pads (1...count) backed by `<n>.md` files. Files are created on first write.
public final class PadStore {
    public let folder: URL
    public let count: Int
    private let fm = FileManager.default

    public init(folder: URL, count: Int = Config.defaultPadCount) throws {
        self.folder = folder
        self.count = min(max(count, 1), Config.maxPads)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public func pad(_ number: Int) -> Pad? {
        guard (1...count).contains(number) else { return nil }
        return Pad(number: number, url: folder.appendingPathComponent("\(number).md"))
    }

    /// All pads in order, with modification date and preview filled in.
    public func list() -> [Pad] {
        (1...count).map { n in
            var pad = pad(n)!
            if let text = try? read(pad) { pad.preview = Pad.preview(of: text) }
            pad.modified = (try? pad.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return pad
        }
    }

    /// Content of the pad; empty if the file doesn't exist yet.
    public func read(_ pad: Pad) throws -> String {
        guard fm.fileExists(atPath: pad.url.path) else { return "" }
        return try String(contentsOf: pad.url, encoding: .utf8)
    }

    public func write(_ text: String, to pad: Pad) throws {
        try text.write(to: pad.url, atomically: true, encoding: .utf8)
    }

    public func clear(_ pad: Pad) throws {
        try write("", to: pad)
    }

    /// Where `add` goes without an explicit pad: the last empty pad, else the last pad.
    public func addTarget() -> Pad {
        list().last { $0.isEmpty } ?? pad(count)!
    }

    /// Puts `text` in the pad: replaces an empty pad, appends (after a blank line) otherwise.
    @discardableResult
    public func add(_ text: String, to number: Int? = nil) throws -> Pad {
        let target: Pad
        if let number {
            guard let p = pad(number) else { throw PadStoreError.noSuchPad(number, max: count) }
            target = p
        } else {
            target = addTarget()
        }
        let body = text.trimmingCharacters(in: .newlines) + "\n"
        let existing = try read(target)
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try write(body, to: target)
        } else {
            try write(existing.trimmingCharacters(in: .newlines) + "\n\n" + body, to: target)
        }
        return target
    }
}
