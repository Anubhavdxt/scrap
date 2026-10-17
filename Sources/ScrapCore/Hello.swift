import Foundation

/// What a user typed on the optional "say hi" screen. Kept on this Mac only for now.
public struct HelloEntry: Codable, Equatable {
    public var name: String
    public var email: String
    public var message: String
    public var date: Date
    public var appVersion: String
    /// Always false until a backend exists; a future upload must ask for consent again first.
    public var sentToServer: Bool

    public init(name: String, email: String, message: String, date: Date = Date(), appVersion: String = Scrap.version) {
        self.name = name
        self.email = email
        self.message = message
        self.date = date
        self.appVersion = appVersion
        self.sentToServer = false
    }

    public var isEmpty: Bool {
        [name, email, message].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public enum EmailValidator {
    /// A deliberately simple check: something@something.tld with no spaces.
    public static func isValid(_ email: String) -> Bool {
        email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil
    }
}

public final class HelloStore {
    public let fileURL: URL

    public init(directory: URL = HelloStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("hello.json")
    }

    public static var defaultDirectory: URL {
        Config.home.appendingPathComponent("Library/Application Support/scrap")
    }

    public func load() -> [HelloEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HelloEntry].self, from: data)) ?? []
    }

    public func save(_ entry: HelloEntry) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(load() + [entry]).write(to: fileURL, options: .atomic)
    }
}
