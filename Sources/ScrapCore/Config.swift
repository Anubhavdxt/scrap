import Foundation

public enum Config {
    public static let defaultPadCount = 7
    public static let maxPads = 99

    /// $HOME when set (so the CLI and tests can be pointed elsewhere), else the user's home directory.
    public static var home: URL {
        ProcessInfo.processInfo.environment["HOME"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// iCloud Drive/scrap when iCloud Drive is available, else ~/Documents/scrap.
    public static func defaultFolder(home: URL = Config.home) -> URL {
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: icloud.path) {
            return icloud.appendingPathComponent("scrap")
        }
        return home.appendingPathComponent("Documents/scrap")
    }

    /// Optional settings shared by the app and the CLI, at ~/.config/scrap/config.json.
    public struct File: Codable, Equatable {
        public var folder: String?
        public var pads: Int?

        public init(folder: String? = nil, pads: Int? = nil) {
            self.folder = folder
            self.pads = pads
        }
    }

    public static func configURL(home: URL = Config.home) -> URL {
        home.appendingPathComponent(".config/scrap/config.json")
    }

    public static func loadFile(home: URL = Config.home) -> File {
        guard let data = try? Data(contentsOf: configURL(home: home)),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return File() }
        return file
    }

    /// The configured pad folder, or the default one.
    public static func folder(home: URL = Config.home) -> URL {
        if let path = loadFile(home: home).folder?.trimmingCharacters(in: .whitespaces), !path.isEmpty {
            if path == "~" { return home.standardizedFileURL }
            if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))).standardizedFileURL }
            return URL(fileURLWithPath: path, relativeTo: home).standardizedFileURL
        }
        return defaultFolder(home: home)
    }

    /// Number of pads, from the config file (clamped to 1...maxPads), default 7.
    public static func padCount(home: URL = Config.home) -> Int {
        min(max(loadFile(home: home).pads ?? defaultPadCount, 1), maxPads)
    }

    /// Writes the config file, creating ~/.config/scrap if needed.
    public static func save(_ file: File, home: URL = Config.home) throws {
        let url = configURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    public static func setPadCount(_ count: Int, home: URL = Config.home) throws {
        var file = loadFile(home: home)
        file.pads = min(max(count, 1), maxPads)
        try save(file, home: home)
    }

    /// Saves the pad folder (shown with ~ when inside the home folder), or clears it to use the default.
    public static func setFolder(_ url: URL?, home: URL = Config.home) throws {
        var file = loadFile(home: home)
        file.folder = url.map { url in
            let path = url.standardizedFileURL.path
            let prefix = home.standardizedFileURL.path + "/"
            return path.hasPrefix(prefix) ? "~/" + path.dropFirst(prefix.count) : path
        }
        try save(file, home: home)
    }
}
