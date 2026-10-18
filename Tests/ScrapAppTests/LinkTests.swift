import XCTest
@testable import ScrapApp
import ScrapCore

/// `scrap://` links, applied by the real model to a throwaway folder.
@MainActor
final class LinkTests: XCTestCase {
    private var home: URL!
    private var pads: URL!
    private var oldHome: String?

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-links-\(UUID().uuidString)")
        pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        for key in ["lastPad", "sayHiDone", "allowURLAdd"] { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: "sayHiDone")
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in ["lastPad", "sayHiDone", "allowURLAdd"] { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    private func read(_ n: Int) -> String? { try? String(contentsOf: pads.appendingPathComponent("\(n).md"), encoding: .utf8) }
    private func url(_ s: String) -> URL { URL(string: s)! }

    // MARK: add

    func testAddWithoutAPadUsesTheSameRuleAsTheCLI() {
        let model = EditorModel()
        XCTAssertEqual(model.handle(url("scrap://add?text=first")), .added(pad: 7), "the last empty pad")
        XCTAssertEqual(model.handle(url("scrap://add?text=second")), .added(pad: 6))
        XCTAssertEqual(read(7), "first\n")
        XCTAssertEqual(read(6), "second\n")
        XCTAssertEqual(model.pads[6].preview, "first", "the pad list is refreshed")
    }

    func testAddToAPadAppendsAfterABlankLine() throws {
        try "existing".write(to: pads.appendingPathComponent("2.md"), atomically: true, encoding: .utf8)
        let model = EditorModel()
        XCTAssertEqual(model.handle(url("scrap://add?text=more%0Alines&pad=2")), .added(pad: 2))
        XCTAssertEqual(read(2), "existing\n\nmore\nlines\n")
    }

    func testAddAnnouncesItselfInTheFooter() {
        let model = EditorModel()
        model.handle(url("scrap://add?text=hello&pad=3"))
        XCTAssertEqual(model.notice, "Added to pad 3 from a link")
    }

    func testAddingToTheOpenPadKeepsWhatYouWereTypingAndShowsTheAddition() {
        let model = EditorModel()
        model.open(number: 1)
        model.text = "typing right now"
        model.handle(url("scrap://add?text=from%20a%20link&pad=1"))
        XCTAssertEqual(read(1), "typing right now\n\nfrom a link\n", "the unsaved text was saved first, then the link's text went after it")
        XCTAssertEqual(model.text, "typing right now\n\nfrom a link\n", "and the editor shows it")
        model.text += "more"
        model.flush()
        XCTAssertEqual(read(1), "typing right now\n\nfrom a link\nmore", "typing carries on without losing anything")
    }

    func testAddingToAnotherPadLeavesTheOpenOneAlone() {
        let model = EditorModel()
        model.open(number: 1)
        model.text = "mine"
        model.handle(url("scrap://add?text=other&pad=4"))
        XCTAssertEqual(model.text, "mine")
        XCTAssertEqual(read(4), "other\n")
    }

    func testLinksCanBeTurnedOff() {
        UserDefaults.standard.set(false, forKey: "allowURLAdd")
        let model = EditorModel()
        XCTAssertEqual(model.handle(url("scrap://add?text=nope")), .ignored)
        XCTAssertNil(read(7))
        XCTAssertTrue(model.notice?.contains("Settings") == true, "and the user is told why")
        XCTAssertEqual(model.handle(url("scrap://open?pad=2")), .opened(pad: 2), "opening a pad is harmless and still works")
    }

    // MARK: open

    func testOpenSwitchesPads() {
        let model = EditorModel()
        XCTAssertEqual(model.handle(url("scrap://open?pad=3")), .opened(pad: 3))
        XCTAssertEqual(model.pad.number, 3)
        XCTAssertEqual(model.handle(url("scrap://open")), .opened(pad: nil))
        XCTAssertEqual(model.pad.number, 3, "no pad given: it stays where it is")
    }

    // MARK: things that must not work

    func testBadLinksChangeNothingAndSaySo() {
        let model = EditorModel()
        for bad in ["scrap://add?text=x&pad=99", "scrap://add?text=x&pad=zero", "scrap://add", "scrap://read?pad=1", "scrap://open?pad=99"] {
            XCTAssertEqual(model.handle(url(bad)), .ignored, bad)
            XCTAssertTrue(model.notice?.hasPrefix("Ignored") == true, "\(bad): \(model.notice ?? "no notice")")
        }
        for n in 1...7 { XCTAssertNil(read(n), "nothing was written to pad \(n)") }
    }

    func testATooLongTextIsRefused() {
        let model = EditorModel()
        let long = String(repeating: "a", count: ScrapURL.maxTextBytes + 1)
        XCTAssertEqual(model.handle(url("scrap://add?text=" + long)), .ignored)
        XCTAssertNil(read(7))
        XCTAssertTrue(model.notice?.contains("too long") == true)
    }

    func testOtherSchemesAreIgnoredQuietly() {
        let model = EditorModel()
        XCTAssertEqual(model.handle(url("https://example.com/add?text=x")), .ignored)
        XCTAssertNil(model.notice)
    }

    func testThereIsNoWayToReadAPadThroughALink() {
        let model = EditorModel()
        model.handle(url("scrap://add?text=secret&pad=1"))
        // Whatever a page tries, the only things a link can do are open and add, and neither returns text.
        for attempt in ["scrap://show?pad=1", "scrap://get?pad=1", "scrap://add?text=x&x-success=https%3A%2F%2Fevil.example%2F%3Fd%3D", "scrap://open?pad=1&x-success=https%3A%2F%2Fevil.example"] {
            _ = model.handle(url(attempt))
        }
        XCTAssertEqual(read(1)?.contains("evil"), false)
    }

    // MARK: registration

    func testTheAppDeclaresTheScheme() throws {
        // Resources/Info.plist, found from this file's own path (…/Tests/ScrapAppTests/LinkTests.swift).
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try XCTUnwrap(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
        XCTAssertEqual(schemes, ["scrap"])
    }
}
