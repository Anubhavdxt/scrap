import Foundation

public struct Pad: Identifiable, Hashable {
    public var id: String { url.lastPathComponent }
    public let url: URL
    public let modified: Date

    public init(url: URL, modified: Date) {
        self.url = url
        self.modified = modified
    }

    public var name: String { url.deletingPathExtension().lastPathComponent }
}
