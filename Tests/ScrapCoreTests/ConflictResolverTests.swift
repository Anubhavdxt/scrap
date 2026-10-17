import XCTest
@testable import ScrapCore

final class ConflictResolverTests: XCTestCase {
    var dir: URL!
    var store: PadStore!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = try PadStore(folder: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func put(_ text: String, _ name: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func archived() -> [String] {
        let url = dir.appendingPathComponent(ConflictResolver.archiveFolderName)
        return ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    func testNameMatching() {
        XCTAssertEqual(ConflictResolver.padNumber(fromConflictName: "3 2.md"), 3)
        XCTAssertEqual(ConflictResolver.padNumber(fromConflictName: "12 4.md"), 12)
        XCTAssertEqual(ConflictResolver.padNumber(fromConflictName: "3 (Conflicted Copy).md"), 3)
        XCTAssertEqual(ConflictResolver.padNumber(fromConflictName: "3 (conflicted copy) 2.md"), 3)
        for name in ["3.md", "3 ideas.md", "idea 2.md", "2024 2.md", "0 2.md", ".3 2.md", "3 2.txt"] {
            XCTAssertNil(ConflictResolver.padNumber(fromConflictName: name), name)
        }
    }

    func testKeepsBothVersions() throws {
        try put("mine", "3.md")
        try put("theirs", "3 2.md")
        XCTAssertEqual(try ConflictResolver.resolve(in: store), [3])
        let merged = try store.read(store.pad(3)!)
        XCTAssertTrue(merged.hasPrefix("mine\n\n--- conflicting version from sync ("))
        XCTAssertTrue(merged.hasSuffix(") ---\n\ntheirs\n"))
        XCTAssertEqual(archived(), ["3 2.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("3 2.md").path))
    }

    func testIdenticalOrEmptyCopyIsJustArchived() throws {
        try put("same\n", "1.md")
        try put("same", "1 2.md")
        try put("keep", "2.md")
        try put("  \n", "2 2.md")
        XCTAssertEqual(try ConflictResolver.resolve(in: store), [])
        XCTAssertEqual(try store.read(store.pad(1)!), "same\n")
        XCTAssertEqual(try store.read(store.pad(2)!), "keep")
        XCTAssertEqual(archived(), ["1 2.md", "2 2.md"])
    }

    func testEmptyPadTakesTheCopy() throws {
        try put("from other mac", "4 2.md")
        XCTAssertEqual(try ConflictResolver.resolve(in: store), [4])
        XCTAssertEqual(try store.read(store.pad(4)!), "from other mac")
    }

    func testIsIdempotentAndLeavesOtherFilesAlone() throws {
        try put("alpha", "5.md")
        try put("beta", "5 2.md")
        try put("old named pad", "ideas.md")
        try put("also", "5 ideas.md")
        XCTAssertEqual(try ConflictResolver.resolve(in: store), [5])
        let once = try store.read(store.pad(5)!)
        XCTAssertEqual(try ConflictResolver.resolve(in: store), [])
        XCTAssertEqual(try store.read(store.pad(5)!), once)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("ideas.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("5 ideas.md").path))
    }

    func testRepeatedConflictsWithSameNameAreBothArchived() throws {
        try put("delta", "6.md")
        try put("omega", "6 2.md")
        try ConflictResolver.resolve(in: store)
        try put("sigma", "6 2.md")
        try ConflictResolver.resolve(in: store)
        XCTAssertEqual(archived(), ["6 2 (2).md", "6 2.md"])
        let merged = try store.read(store.pad(6)!)
        XCTAssertTrue(merged.contains("delta") && merged.contains("omega") && merged.contains("sigma"))
    }
}

extension ConflictResolverTests {
    func testShortCopyIsNotMistakenForDuplicate() throws {
        try put("banana", "7.md")
        try put("an", "7 2.md")
        XCTAssertEqual(try ConflictResolver.resolve(in: store), [7])
        XCTAssertTrue(try store.read(store.pad(7)!).hasSuffix("---\n\nan\n"))
    }
}
