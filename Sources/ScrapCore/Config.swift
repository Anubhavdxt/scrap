import Foundation

public enum Config {
    /// iCloud Drive/scrap when iCloud Drive is available, else ~/Documents/scrap.
    public static func defaultFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: icloud.path) {
            return icloud.appendingPathComponent("scrap")
        }
        return home.appendingPathComponent("Documents/scrap")
    }
}
