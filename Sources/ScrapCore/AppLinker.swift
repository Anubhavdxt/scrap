import Foundation

/// Links the Scrap.app that ships next to the CLI (as installed by Homebrew) into /Applications.
public enum AppLinker {
    public enum Outcome: Equatable {
        case linked(URL)
        case alreadyLinked(URL)
        case relinked(URL)
    }

    public enum LinkError: LocalizedError, Equatable {
        case appNotFound
        case realAppInTheWay(String)
        case notALink(String)
        case cantWrite(String)

        public var errorDescription: String? {
            switch self {
            case .appNotFound:
                "couldn't find Scrap.app next to this command. Install with Homebrew, or use `make install`."
            case .realAppInTheWay(let path):
                "\(path) is a real app, not a link, so I won't touch it. Remove it first if you want the Homebrew copy."
            case .notALink(let path):
                "\(path) isn't a link created by `scrap link`, so I left it alone."
            case .cantWrite(let message):
                "couldn't write to the Applications folder (\(message)). Try again with sudo."
            }
        }
    }

    /// Scrap.app next to the CLI: `<prefix>/bin/scrap` -> `<prefix>/Scrap.app`. For a Homebrew install, prefers the
    /// stable `<brew prefix>/opt/scrap/Scrap.app` path so the link survives upgrades.
    public static func locateApp(executable: URL) -> URL? {
        let fm = FileManager.default
        let real = executable.resolvingSymlinksInPath()
        let app = real.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scrap.app")
        guard fm.fileExists(atPath: app.path) else { return nil }
        if let range = real.path.range(of: "/Cellar/scrap/") {
            let opt = URL(fileURLWithPath: String(real.path[..<range.lowerBound]))
                .appendingPathComponent("opt/scrap/Scrap.app")
            if fm.fileExists(atPath: opt.path) { return opt }
        }
        return app
    }

    public static func link(app: URL, into directory: URL) throws -> Outcome {
        let fm = FileManager.default
        let dest = directory.appendingPathComponent("Scrap.app")
        if let existing = try? fm.destinationOfSymbolicLink(atPath: dest.path) {
            if existing == app.path { return .alreadyLinked(dest) }
            try remove(dest)
            try create(dest, to: app)
            return .relinked(dest)
        }
        if fm.fileExists(atPath: dest.path) { throw LinkError.realAppInTheWay(dest.path) }
        try create(dest, to: app)
        return .linked(dest)
    }

    /// Removes the link, never a real app.
    @discardableResult
    public static func unlink(from directory: URL) throws -> Bool {
        let fm = FileManager.default
        let dest = directory.appendingPathComponent("Scrap.app")
        if (try? fm.destinationOfSymbolicLink(atPath: dest.path)) != nil {
            try remove(dest)
            return true
        }
        if fm.fileExists(atPath: dest.path) { throw LinkError.notALink(dest.path) }
        return false
    }

    private static func create(_ dest: URL, to app: URL) throws {
        do { try FileManager.default.createSymbolicLink(at: dest, withDestinationURL: app) } catch {
            throw LinkError.cantWrite((error as NSError).localizedDescription)
        }
    }

    private static func remove(_ dest: URL) throws {
        do { try FileManager.default.removeItem(at: dest) } catch {
            throw LinkError.cantWrite((error as NSError).localizedDescription)
        }
    }
}
