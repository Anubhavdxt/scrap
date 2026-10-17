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

    func testFixedSlots() {
        XCTAssertEqual(store.list().map(\.number), Array(1...7))
        XCTAssertTrue(store.list().allSatisfy(\.isEmpty))
        XCTAssertNil(store.pad(0))
        XCTAssertNil(store.pad(8))
        XCTAssertEqual(store.pad(3)?.url.lastPathComponent, "3.md")
    }

    func testWriteReadClear() throws {
        let pad = store.pad(2)!
        XCTAssertEqual(try store.read(pad), "", "missing file reads as empty")
        try store.write("# Héllo\nbody", to: pad)
        XCTAssertEqual(try store.read(pad), "# Héllo\nbody")
        XCTAssertEqual(store.list()[1].preview, "Héllo")
        try store.clear(pad)
        XCTAssertTrue(store.list()[1].isEmpty)
    }

    func testAddGoesToLastEmptyPadThenAppendsToLast() throws {
        XCTAssertEqual(try store.add("a").number, 7)
        XCTAssertEqual(try store.add("b").number, 6)
        for n in 1...5 { try store.write("x", to: store.pad(n)!) }
        XCTAssertEqual(store.addTarget().number, 7)
        let last = try store.add("c")
        XCTAssertEqual(last.number, 7)
        XCTAssertEqual(try store.read(last), "a\n\nc\n")
    }

    func testAddToExplicitPad() throws {
        try store.add("one", to: 2)
        try store.add("two", to: 2)
        XCTAssertEqual(try store.read(store.pad(2)!), "one\n\ntwo\n")
        XCTAssertThrowsError(try store.add("x", to: 9))
    }

    func testCountIsClamped() throws {
        XCTAssertEqual(try PadStore(folder: dir, count: 0).count, 1)
        XCTAssertEqual(try PadStore(folder: dir, count: 500).count, Config.maxPads)
    }

    func testLoweringCountKeepsFiles() throws {
        try store.write("keep", to: store.pad(7)!)
        let small = try PadStore(folder: dir, count: 3)
        XCTAssertEqual(small.list().count, 3)
        XCTAssertEqual(try store.read(store.pad(7)!), "keep")
        XCTAssertEqual(try PadStore(folder: dir, count: 7).list()[6].preview, "keep")
    }

    func testDefaultFolderUsesICloudWhenPresent() throws {
        let home = dir.appendingPathComponent("home")
        XCTAssertEqual(Config.defaultFolder(home: home).path, home.appendingPathComponent("Documents/scrap").path)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), withIntermediateDirectories: true)
        XCTAssertTrue(Config.defaultFolder(home: home).path.hasSuffix("CloudDocs/scrap"))
    }

    func testConfigFile() throws {
        let home = dir.appendingPathComponent("home")
        XCTAssertEqual(Config.padCount(home: home), 7)
        try Config.setPadCount(12, home: home)
        XCTAssertEqual(Config.padCount(home: home), 12)
        var file = Config.loadFile(home: home)
        file.folder = "~/notes"
        try Config.save(file, home: home)
        XCTAssertEqual(Config.folder(home: home).lastPathComponent, "notes")
        try Config.setPadCount(1000, home: home)
        XCTAssertEqual(Config.padCount(home: home), Config.maxPads)
        XCTAssertEqual(Config.loadFile(home: home).folder, "~/notes", "saving keeps other keys")
        try Config.setFolder(home.appendingPathComponent("elsewhere"), home: home)
        XCTAssertEqual(Config.loadFile(home: home).folder, "~/elsewhere")
        XCTAssertEqual(Config.folder(home: home).lastPathComponent, "elsewhere")
        XCTAssertEqual(Config.padCount(home: home), Config.maxPads, "saving the folder keeps the pad count")
        try Config.setFolder(nil, home: home)
        XCTAssertEqual(Config.folder(home: home), Config.defaultFolder(home: home))
        try "not json".write(to: Config.configURL(home: home), atomically: true, encoding: .utf8)
        XCTAssertEqual(Config.folder(home: home), Config.defaultFolder(home: home))
        XCTAssertEqual(Config.padCount(home: home), 7)
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
