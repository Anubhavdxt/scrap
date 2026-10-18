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
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertEqual(window.standardWindowButton(button)?.isHidden, true, "no macOS traffic-light buttons, like Tot")
        }
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.isMovableByWindowBackground)
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

/// The detached window, built by the real controller, as a picture (opt-in, like the other snapshots).
@MainActor
final class WindowedSnapshotTests: XCTestCase {
    func testRenderTheRealWindow() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        _ = NSApplication.shared
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-snapw-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        try "# Window mode\n- [ ] no traffic lights\nsecond line".write(to: pads.appendingPathComponent("1.md"), atomically: true, encoding: .utf8)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame ScrapEditorWindow")
        defer { UserDefaults.standard.removeObject(forKey: "sayHiDone"); UserDefaults.standard.removeObject(forKey: "NSWindow Frame ScrapEditorWindow") }

        let controller = EditorWindowController(model: EditorModel())
        controller.show()
        let window = try XCTUnwrap(controller.window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        // The whole window, frame included: what you would see on screen.
        let id = CGWindowID(window.windowNumber)
        let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming])
        let rep: NSBitmapImageRep
        if let image { rep = NSBitmapImageRep(cgImage: image) } else {
            let view = try XCTUnwrap(window.contentView)
            rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("window.png"))
        controller.hide()
    }
}

final class PointerPlacementTests: XCTestCase {
    private typealias Screen = PointerPlacement.Screen
    /// A 1440×900 screen with a 25 pt menu bar at the top and a 70 pt Dock at the bottom.
    private let main = Screen(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), visible: NSRect(x: 0, y: 70, width: 1440, height: 805))
    private let size = NSSize(width: 600, height: 350)

    func testPointerEndsUpInTheTopBarWithTheWindowCentredOnIt() {
        let frame = PointerPlacement.frame(size: size, pointer: NSPoint(x: 700, y: 500), screens: [main])
        XCTAssertEqual(frame.midX, 700, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, 500 + PointerPlacement.topOffset, accuracy: 0.5, "the top edge is just above the pointer")
        XCTAssertEqual(frame.size, size)
    }

    func testStaysInsideTheVisibleArea() {
        let m = PointerPlacement.margin
        let right = PointerPlacement.frame(size: size, pointer: NSPoint(x: 1435, y: 500), screens: [main])
        XCTAssertEqual(right.maxX, 1440 - m, accuracy: 0.5)
        let left = PointerPlacement.frame(size: size, pointer: NSPoint(x: 2, y: 500), screens: [main])
        XCTAssertEqual(left.minX, m, accuracy: 0.5)
        let top = PointerPlacement.frame(size: size, pointer: NSPoint(x: 700, y: 895), screens: [main])
        XCTAssertEqual(top.maxY, 875 - m, accuracy: 0.5, "below the menu bar")
        let bottom = PointerPlacement.frame(size: size, pointer: NSPoint(x: 700, y: 80), screens: [main])
        XCTAssertEqual(bottom.minY, 70 + m, accuracy: 0.5, "above the Dock")
    }

    func testUsesTheScreenThePointerIsOn() {
        let second = Screen(frame: NSRect(x: 1440, y: 0, width: 1920, height: 1080), visible: NSRect(x: 1440, y: 0, width: 1920, height: 1055))
        let frame = PointerPlacement.frame(size: size, pointer: NSPoint(x: 2400, y: 600), screens: [main, second])
        XCTAssertEqual(frame.midX, 2400, accuracy: 0.5)
        XCTAssertTrue(second.visible.contains(frame))
        let edge = PointerPlacement.frame(size: size, pointer: NSPoint(x: 1445, y: 600), screens: [main, second])
        XCTAssertGreaterThanOrEqual(edge.minX, 1440, "it doesn't straddle the two screens")
    }

    func testPointerOutsideEveryScreenFallsBackToTheNearest() {
        let frame = PointerPlacement.frame(size: size, pointer: NSPoint(x: 5000, y: 300), screens: [main])
        XCTAssertTrue(main.visible.contains(frame))
    }

    func testAWindowBiggerThanTheScreenIsPinnedToItsTopLeft() {
        let small = Screen(frame: NSRect(x: 0, y: 0, width: 500, height: 300), visible: NSRect(x: 0, y: 0, width: 500, height: 280))
        let frame = PointerPlacement.frame(size: size, pointer: NSPoint(x: 250, y: 150), screens: [small])
        XCTAssertEqual(frame.minX, PointerPlacement.margin)
        XCTAssertEqual(frame.maxY, 280 - PointerPlacement.margin)
    }

    func testWithNoScreensItJustCentresOnThePointer() {
        let frame = PointerPlacement.frame(size: size, pointer: NSPoint(x: 100, y: 100), screens: [])
        XCTAssertEqual(frame.midX, 100, accuracy: 0.5)
    }
}

@MainActor
final class WindowFollowsPointerTests: XCTestCase {
    private var home: URL!
    private var oldHome: String?

    override func setUpWithError() throws {
        _ = NSApplication.shared
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-follow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame ScrapEditorWindow")
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in ["sayHiDone", "NSWindow Frame ScrapEditorWindow", "lastPad"] { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    func testShowingNearThePointerMovesTheWindowThere() throws {
        // Real screens: macOS pulls any shown window back onto them, so a made-up bigger screen can't be tested.
        let screens = PointerPlacement.currentScreens
        guard let area = screens.first?.visible, area.width > 900, area.height > 600 else { throw XCTSkip("needs a display") }
        let controller = EditorWindowController(model: EditorModel())
        let centre = NSPoint(x: area.midX, y: area.midY)
        controller.show(near: centre)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.frame.midX, centre.x, accuracy: 1.5)
        XCTAssertEqual(window.frame.maxY, centre.y + PointerPlacement.topOffset, accuracy: 1.5)

        let other = NSPoint(x: area.minX + area.width * 0.3, y: area.minY + area.height * 0.6)
        controller.show(near: other)
        XCTAssertEqual(window.frame.midX, other.x, accuracy: 1.5, "it follows the pointer each time")
        controller.hide()
    }

    func testPlainShowLeavesTheWindowWhereItWas() throws {
        let controller = EditorWindowController(model: EditorModel())
        controller.show()
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: 123, y: 321))
        controller.hide()
        controller.show()
        XCTAssertEqual(window.frame.origin.x, 123, accuracy: 1)
        XCTAssertEqual(window.frame.origin.y, 321, accuracy: 1)
        controller.hide()
    }
}
