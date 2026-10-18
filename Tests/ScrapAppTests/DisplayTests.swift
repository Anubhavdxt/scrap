import AppKit
import SwiftUI
import XCTest
@testable import ScrapApp
import ScrapCore

final class DisplayPolicyTests: XCTestCase {
    func testMenuBarOnlyIsAPopoverUnlessDetached() {
        let attached = DisplayPolicy.resolve(icon: .menuBar, detached: false)
        XCTAssertEqual(attached, DisplayPolicy(showsStatusItem: true, showsDockIcon: false, usesWindow: false, canAttach: true))
        let detached = DisplayPolicy.resolve(icon: .menuBar, detached: true)
        XCTAssertEqual(detached, DisplayPolicy(showsStatusItem: true, showsDockIcon: false, usesWindow: true, canAttach: true))
    }

    func testDockOnlyIsAlwaysAWindow() {
        for detached in [false, true] {
            let policy = DisplayPolicy.resolve(icon: .dock, detached: detached)
            XCTAssertEqual(policy, DisplayPolicy(showsStatusItem: false, showsDockIcon: true, usesWindow: true, canAttach: false), "detached: \(detached)")
        }
    }

    func testBothIconsFollowTheDetachedChoice() {
        XCTAssertEqual(DisplayPolicy.resolve(icon: .both, detached: false),
                       DisplayPolicy(showsStatusItem: true, showsDockIcon: true, usesWindow: false, canAttach: true))
        XCTAssertTrue(DisplayPolicy.resolve(icon: .both, detached: true).usesWindow)
    }

    func testThereIsAlwaysAWayToReachTheEditor() {
        for icon in IconMode.allCases {
            for detached in [false, true] {
                let p = DisplayPolicy.resolve(icon: icon, detached: detached)
                XCTAssertTrue(p.showsStatusItem || p.showsDockIcon, "\(icon) must leave at least one icon")
                XCTAssertFalse(!p.showsStatusItem && !p.usesWindow, "a popover can't exist without its menu bar icon")
            }
        }
    }

    func testReadsTheSavedSettingsAndIgnoresJunk() {
        let defaults = UserDefaults(suiteName: "scrap.tests.policy.\(UUID().uuidString)")!
        XCTAssertEqual(DisplayPolicy.current(defaults), DisplayPolicy.resolve(icon: .menuBar, detached: false), "defaults")
        defaults.set("dock", forKey: "iconMode")
        XCTAssertTrue(DisplayPolicy.current(defaults).usesWindow)
        defaults.set("something else", forKey: "iconMode")
        defaults.set(true, forKey: "detached")
        XCTAssertEqual(DisplayPolicy.current(defaults), DisplayPolicy.resolve(icon: .menuBar, detached: true), "unknown value falls back to the menu bar")
    }
}

@MainActor
final class EditorWindowControllerTests: XCTestCase {
    private var home: URL!
    private var oldHome: String?

    override func setUpWithError() throws {
        _ = NSApplication.shared // NSApp must exist before windows are activated
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-win-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        UserDefaults.standard.removeObject(forKey: "windowFloating")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame ScrapEditorWindow")
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in ["sayHiDone", "windowFloating", "NSWindow Frame ScrapEditorWindow", "lastPad"] { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    func testTheWindowIsAResizableTitledWindowSizedInColumnsAndRows() throws {
        let controller = EditorWindowController(model: EditorModel())
        XCTAssertNil(controller.window, "nothing is built until it's needed")
        controller.show()
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView), "the top bar sits under the traffic lights")
        XCTAssertEqual(window.title, "Pad 1")
        let expected = WindowSize.current()
        XCTAssertEqual(window.contentLayoutRect.size.width, expected.width, accuracy: 2)
        XCTAssertEqual(window.contentLayoutRect.size.height, expected.height, accuracy: 40, "titlebar area is part of the content")
        XCTAssertGreaterThanOrEqual(window.minSize.width, 300)
    }

    func testClosingHidesTheWindowAndShowBringsItBack() throws {
        let controller = EditorWindowController(model: EditorModel())
        controller.show()
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(controller.windowShouldClose(window), "the close button hides, it doesn't destroy the window")
        XCTAssertFalse(window.isVisible)
        controller.show()
        XCTAssertTrue(controller.window === window, "the same window comes back")
        XCTAssertTrue(window.isVisible)
        controller.hide()
        XCTAssertFalse(controller.isVisible)
    }

    func testAlwaysOnTopFollowsTheSettingAndTheTitleFollowsThePad() throws {
        let model = EditorModel()
        let controller = EditorWindowController(model: model)
        controller.show()
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.level, .normal)
        UserDefaults.standard.set(true, forKey: "windowFloating")
        controller.applySettings()
        XCTAssertEqual(window.level, .floating)
        UserDefaults.standard.set(false, forKey: "windowFloating")
        controller.applySettings()
        XCTAssertEqual(window.level, .normal)
        model.open(number: 3)
        XCTAssertEqual(window.title, "Pad 3")
        controller.hide()
    }

    func testHidingSavesWhatWasTyped() throws {
        let model = EditorModel()
        let controller = EditorWindowController(model: model)
        controller.show()
        model.text = "typed in the window"
        controller.hide()
        let saved = try String(contentsOf: home.appendingPathComponent("pads/1.md"), encoding: .utf8)
        XCTAssertEqual(saved, "typed in the window")
    }
}

/// The windowed layout as a picture (opt-in, like the other snapshots).
@MainActor
final class WindowedSnapshotTests: XCTestCase {
    func testRenderWindowedLayout() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-snapw-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        try "# Window mode\n- [ ] pinned as a window\nsecond line".write(to: pads.appendingPathComponent("1.md"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        defer { UserDefaults.standard.removeObject(forKey: "sayHiDone") }
        let model = EditorModel()
        let size = WindowSize.current()
        let view = NSHostingView(rootView: ContentView(model: model).environment(\.scrapWindowed, true).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("window.png"))
    }
}
