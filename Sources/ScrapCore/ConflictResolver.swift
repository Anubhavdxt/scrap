import Foundation

/// Keeps both versions when sync leaves a conflicting copy of a pad next to it.
///
/// iCloud Drive names the losing copy `3 2.md` (pad 3), other tools use `3 (conflicted copy).md`.
/// The copy's text is appended to the pad under a marker line, and the copy itself is moved to
/// `.conflicts/` so nothing is ever lost or deleted.
public enum ConflictResolver {
    public static let archiveFolderName = ".conflicts"

    private static let patterns = [
        try! NSRegularExpression(pattern: #"^(\d{1,2}) (\d+)\.md$"#),
        try! NSRegularExpression(pattern: #"^(\d{1,2}) \(.*conflict.*\)(?: \d+)?\.md$"#, options: .caseInsensitive),
    ]

    /// Resolves every conflict copy in the store's folder. Returns the numbers of pads whose content changed.
    @discardableResult
    public static func resolve(in store: PadStore) throws -> [Int] {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: store.folder.path).filter { !$0.hasPrefix(".") }
        var changed = Set<Int>()

        for name in names.sorted() {
            guard let number = padNumber(fromConflictName: name) else { continue }
            let copy = store.folder.appendingPathComponent(name)
            let pad = store.folder.appendingPathComponent("\(number).md")

            let theirs = try String(contentsOf: copy, encoding: .utf8)
            let mine = fm.fileExists(atPath: pad.path) ? try String(contentsOf: pad, encoding: .utf8) : ""
            let t = theirs.trimmingCharacters(in: .whitespacesAndNewlines)
            let m = mine.trimmingCharacters(in: .whitespacesAndNewlines)

            if t.isEmpty || sections(of: m).contains(t) {
                // Nothing new in the copy.
            } else if m.isEmpty {
                try theirs.write(to: pad, atomically: true, encoding: .utf8)
                changed.insert(number)
            } else {
                let modified = (try? copy.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                let marker = "--- conflicting version from sync (\(format(modified))) ---"
                let merged = m + "\n\n" + marker + "\n\n" + t + "\n"
                try merged.write(to: pad, atomically: true, encoding: .utf8)
                changed.insert(number)
            }
            try archive(copy, in: store.folder)
        }
        return changed.sorted()
    }

    private static let markerLine = try! NSRegularExpression(pattern: #"^--- conflicting version from sync \(.*\) ---$"#)

    /// The pad's text split at our own marker lines, each section trimmed. A copy equal to any section is already kept.
    static func sections(of text: String) -> [String] {
        var sections: [String] = []
        var current: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let ns = String(line) as NSString
            if markerLine.firstMatch(in: String(line), range: NSRange(location: 0, length: ns.length)) != nil {
                sections.append(current.joined(separator: "\n"))
                current = []
            } else {
                current.append(line)
            }
        }
        sections.append(current.joined(separator: "\n"))
        return sections.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func padNumber(fromConflictName name: String) -> Int? {
        let range = NSRange(location: 0, length: (name as NSString).length)
        for re in patterns {
            if let m = re.firstMatch(in: name, range: range),
               let n = Int((name as NSString).substring(with: m.range(at: 1))), (1...Config.maxPads).contains(n) {
                return n
            }
        }
        return nil
    }

    private static func archive(_ url: URL, in folder: URL) throws {
        let fm = FileManager.default
        let dir = folder.appendingPathComponent(archiveFolderName)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var dest = dir.appendingPathComponent(url.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) (\(n)).md")
            n += 1
        }
        try fm.moveItem(at: url, to: dest)
    }

    private static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}
