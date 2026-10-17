import XCTest
@testable import ScrapCore

final class PadStoreTests: XCTestCase {
    var dir: URL!
    var store: PadStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try PadStore(folder: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testCreateUniqueNames() throws {
        let a = try store.create()
        let b = try store.create()
        XCTAssertEqual(a.name, "untitled")
        XCTAssertEqual(b.name, "untitled 2")
    }

    func testWriteReadRoundTrip() throws {
        let pad = try store.create()
        try store.write("héllo\n```swift\nlet x = 1\n```", to: pad)
        XCTAssertEqual(try store.read(pad), "héllo\n```swift\nlet x = 1\n```")
    }

    func testListOnlyMarkdownNewestFirst() throws {
        let old = try store.create(name: "old")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: old.url.path)
        _ = try store.create(name: "new")
        try "x".write(to: dir.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.list().map(\.name), ["new", "old"])
    }

    func testDefaultFolderUsesICloudWhenPresent() throws {
        let home = dir.appendingPathComponent("home")
        XCTAssertEqual(Config.defaultFolder(home: home).path, home.appendingPathComponent("Documents/scrap").path)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), withIntermediateDirectories: true)
        XCTAssertTrue(Config.defaultFolder(home: home).path.hasSuffix("CloudDocs/scrap"))
    }
}

extension PadStoreTests {
    func testRenameAndCollision() throws {
        let a = try store.create(name: "a")
        _ = try store.create(name: "b")
        let renamed = try store.rename(a, to: " c/d ")
        XCTAssertEqual(renamed.name, "c-d")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.url.path))
        XCTAssertThrowsError(try store.rename(renamed, to: "b"))
        XCTAssertThrowsError(try store.rename(renamed, to: "  "))
    }

    func testDeleteRemovesFromList() throws {
        let a = try store.create(name: "gone")
        try store.delete(a)
        XCTAssertTrue(try store.list().isEmpty)
    }
}

final class FuzzyTests: XCTestCase {
    func testMatchingAndRanking() {
        XCTAssertNil(Fuzzy.score("xyz", in: "meeting notes"))
        XCTAssertNotNil(Fuzzy.score("mn", in: "meeting notes"))
        XCTAssertEqual(Fuzzy.rank("note", ["random n o t e", "notes", "my notes"], by: { $0 }).first, "notes")
        XCTAssertEqual(Fuzzy.rank("", ["b", "a"], by: { $0 }), ["b", "a"])
    }
}

extension PadStoreTests {
    func testSuggestedName() {
        XCTAssertEqual(PadStore.suggestedName(for: "# Buy milk\nand eggs"), "Buy milk")
        XCTAssertEqual(PadStore.suggestedName(for: "\n\n  a/b: c"), "a-b- c")
        XCTAssertEqual(PadStore.suggestedName(for: "   \n"), "untitled")
        XCTAssertEqual(PadStore.suggestedName(for: String(repeating: "x", count: 100)).count, 40)
        XCTAssertEqual(PadStore.suggestedName(for: "..hidden"), "hidden")
    }

    func testAddWritesTextAndAvoidsCollisions() throws {
        let a = try store.add("hello")
        let b = try store.add("hello")
        XCTAssertEqual(a.name, "hello")
        XCTAssertEqual(b.name, "hello 2")
        XCTAssertEqual(try store.read(a), "hello\n")
        XCTAssertEqual(try store.add("x", name: "custom").name, "custom")
    }

    func testConfigFileFolder() throws {
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: Config.configURL(home: home).deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{ "folder": "~/notes" }"#.write(to: Config.configURL(home: home), atomically: true, encoding: .utf8)
        XCTAssertEqual(Config.folder(home: home).lastPathComponent, "notes")
        try "not json".write(to: Config.configURL(home: home), atomically: true, encoding: .utf8)
        XCTAssertEqual(Config.folder(home: home), Config.defaultFolder(home: home))
    }
}
