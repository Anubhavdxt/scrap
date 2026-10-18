import XCTest
@testable import ScrapApp
import ScrapCore

/// Drives `EditorModel` against a throwaway HOME so nothing touches the real pads or settings.
@MainActor
final class EditorModelTests: XCTestCase {
    private var home: URL!
    private var padsDir: URL!
    private var oldHome: String?
    private let fm = FileManager.default

    override func setUpWithError() throws {
        home = fm.temporaryDirectory.appendingPathComponent("scrap-tests-\(UUID().uuidString)")
        padsDir = home.appendingPathComponent("pads")
        try fm.createDirectory(at: padsDir, withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        for key in ["lastPad", "sayHiDone"] { UserDefaults.standard.removeObject(forKey: key) }
        try writeConfig(folder: padsDir.path, pads: 7)
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in ["lastPad", "sayHiDone"] { UserDefaults.standard.removeObject(forKey: key) }
        try? fm.removeItem(at: home)
    }

    // MARK: Helpers

    private func writeConfig(folder: String, pads: Int) throws {
        try Config.save(Config.File(folder: folder, pads: pads), home: home)
    }

    private func pad(_ n: Int, in dir: URL? = nil) -> URL { (dir ?? padsDir).appendingPathComponent("\(n).md") }

    private func put(_ text: String, _ n: Int, in dir: URL? = nil) throws {
        try text.write(to: pad(n, in: dir), atomically: true, encoding: .utf8)
    }

    private func read(_ n: Int, in dir: URL? = nil) -> String? { try? String(contentsOf: pad(n, in: dir), encoding: .utf8) }

    /// Spins the main run loop until `condition` holds (file events arrive on it).
    private func wait(timeout: TimeInterval = 5, _ condition: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    }

    // MARK: Starting up

    func testStartsOnPadOneAndRestoresTheLastPad() throws {
        try put("first", 1)
        try put("third", 3)
        XCTAssertEqual(EditorModel().pad.number, 1)
        XCTAssertEqual(EditorModel().text, "first")

        let model = EditorModel()
        model.open(number: 3)
        let again = EditorModel()
        XCTAssertEqual(again.pad.number, 3)
        XCTAssertEqual(again.text, "third")
    }

    func testPadCountComesFromTheConfig() throws {
        try writeConfig(folder: padsDir.path, pads: 4)
        let model = EditorModel()
        XCTAssertEqual(model.padCount, 4)
        XCTAssertEqual(model.pads.map(\.number), [1, 2, 3, 4])
    }

    func testFallsBackWhenTheFolderCannotBeCreated() throws {
        let blocker = home.appendingPathComponent("file")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        try writeConfig(folder: blocker.appendingPathComponent("inside").path, pads: 7)
        let model = EditorModel()
        XCTAssertNotNil(model.error, "the user is told why their folder isn't used")
        XCTAssertEqual(model.pad.number, 1, "the editor still opens")
    }

    // MARK: Editing and saving

    func testFlushWritesTheTextToThePadFile() {
        let model = EditorModel()
        model.text = "hello"
        XCTAssertNil(read(1), "autosave is debounced, nothing yet")
        model.flush()
        XCTAssertEqual(read(1), "hello")
        XCTAssertEqual(model.pads[0].preview, "hello")
    }

    func testAutosaveFiresAfterTheDebounce() {
        let model = EditorModel()
        model.text = "typed"
        wait { read(1) == "typed" }
        XCTAssertEqual(read(1), "typed")
    }

    func testSwitchingPadsSavesTheOldOneAndLoadsTheNewOne() throws {
        try put("two", 2)
        let model = EditorModel()
        model.text = "one, unsaved"
        model.open(number: 2)
        XCTAssertEqual(read(1), "one, unsaved")
        XCTAssertEqual(model.text, "two")
        XCTAssertEqual(model.pad.number, 2)
        model.text = "two edited"
        model.open(number: 1)
        XCTAssertEqual(read(2), "two edited")
        XCTAssertEqual(model.text, "one, unsaved")
    }

    func testOpeningAPadThatDoesNotExistIsIgnored() {
        let model = EditorModel()
        model.open(number: 99)
        XCTAssertEqual(model.pad.number, 1)
    }

    func testClearEmptiesTheFileAndTheEditor() throws {
        try put("keep me?", 1)
        let model = EditorModel()
        model.clearCurrent()
        XCTAssertEqual(model.text, "")
        XCTAssertEqual(read(1), "")
        XCTAssertTrue(model.pads[0].isEmpty)
    }

    // MARK: Settings that change the model

    func testLoweringThePadCountHidesPadsButKeepsTheirFiles() throws {
        try put("seven", 7)
        let model = EditorModel()
        model.open(number: 7)
        model.setPadCount(3)
        XCTAssertEqual(model.padCount, 3)
        XCTAssertEqual(model.pad.number, 3, "moves off a pad that no longer exists")
        XCTAssertEqual(read(7), "seven", "nothing is deleted")
        XCTAssertEqual(Config.padCount(home: home), 3, "and it's saved for the CLI")
        model.setPadCount(7)
        XCTAssertEqual(model.pads[6].preview, "seven")
    }

    func testChangingTheFolderSwitchesPadsAndSavesTheConfig() throws {
        try put("old", 1)
        let other = home.appendingPathComponent("elsewhere")
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        try put("new", 1, in: other)
        let model = EditorModel()
        XCTAssertEqual(model.text, "old")
        model.text = "old edited"
        model.setFolder(other)
        XCTAssertEqual(read(1), "old edited", "unsaved work goes to the old folder first")
        XCTAssertEqual(model.text, "new")
        XCTAssertEqual(model.folder.standardizedFileURL.path, other.standardizedFileURL.path)
        XCTAssertEqual(Config.loadFile(home: home).folder, "~/elsewhere")
        model.setFolder(nil)
        XCTAssertEqual(model.folder.standardizedFileURL.path, Config.defaultFolder(home: home).standardizedFileURL.path)
    }

    // MARK: Files changing underneath

    func testExternalEditsReloadWhenThereAreNoLocalChanges() throws {
        try put("before", 1)
        let model = EditorModel()
        try put("after", 1)
        wait { model.text == "after" }
        XCTAssertEqual(model.text, "after")
    }

    func testExternalEditsNeverClobberUnsavedTyping() throws {
        try put("before", 1)
        let model = EditorModel()
        model.text = "my typing"
        try put("someone else", 2) // any change in the folder triggers a refresh
        wait { model.pads[1].preview == "someone else" }
        XCTAssertEqual(model.pads[1].preview, "someone else")
        XCTAssertEqual(model.text, "my typing")
    }

    func testSyncConflictsAreMergedAtLaunchWithANotice() throws {
        try put("mine", 3)
        try "from the other mac".write(to: padsDir.appendingPathComponent("3 2.md"), atomically: true, encoding: .utf8)
        let model = EditorModel()
        XCTAssertNotNil(model.notice)
        XCTAssertTrue(model.notice?.contains("pad 3") == true)
        let merged = read(3) ?? ""
        XCTAssertTrue(merged.contains("mine") && merged.contains("from the other mac"))
        XCTAssertFalse(fm.fileExists(atPath: padsDir.appendingPathComponent("3 2.md").path))
    }

    // MARK: Say hi

    func testSayHiShowsOnceAndSavesLocallyOnly() throws {
        let model = EditorModel()
        XCTAssertTrue(model.showSayHi)
        model.finishSayHi(HelloEntry(name: "A", email: "a@b.co", message: "hi"))
        XCTAssertFalse(model.showSayHi)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "sayHiDone"))
        let saved = HelloStore().load()
        XCTAssertEqual(saved.map(\.email), ["a@b.co"])
        XCTAssertTrue(saved.allSatisfy { !$0.sentToServer })
        XCTAssertFalse(EditorModel().showSayHi, "not shown again")
    }

    func testSkippingSayHiSavesNothing() {
        let model = EditorModel()
        model.finishSayHi(nil)
        XCTAssertFalse(model.showSayHi)
        XCTAssertEqual(HelloStore().load(), [])
    }
}
