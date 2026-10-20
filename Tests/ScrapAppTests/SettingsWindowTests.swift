import XCTest
import Vision
import SwiftUI
@testable import ScrapApp
import ScrapCore

@MainActor
final class SettingsWindowTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = NSSize(width: 440, height: 412)

    func testItSitsOnTheRightOfTheEditorTopAligned() {
        let editor = NSRect(x: 300, y: 400, width: 500, height: 350)
        let origin = SettingsWindowController.origin(for: size, beside: editor, screen: screen)
        XCTAssertEqual(origin.x, 810, accuracy: 0.5)
        XCTAssertEqual(origin.y + size.height, editor.maxY, accuracy: 0.5, "tops line up")
    }

    func testItMovesToTheLeftWhenThereIsNoRoomOnTheRight() {
        let editor = NSRect(x: 1000, y: 400, width: 420, height: 350)
        let origin = SettingsWindowController.origin(for: size, beside: editor, screen: screen)
        XCTAssertEqual(origin.x, 1000 - 440 - 10, accuracy: 0.5)
    }

    func testItStaysOnTheScreenWhenTheEditorIsHigh() {
        let editor = NSRect(x: 100, y: 700, width: 420, height: 190)
        let origin = SettingsWindowController.origin(for: size, beside: editor, screen: screen)
        XCTAssertLessThanOrEqual(origin.y + size.height, screen.maxY)
        XCTAssertGreaterThanOrEqual(origin.y, screen.minY)
    }

    func testTheWindowShowsHidesAndFollowsTheAlwaysOnTopSetting() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-setwin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; UserDefaults.standard.removeObject(forKey: "windowFloating"); try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        UserDefaults.standard.set(true, forKey: "windowFloating")

        let controller = SettingsWindowController(model: EditorModel())
        XCTAssertFalse(controller.isVisible)
        controller.show(beside: nil)
        XCTAssertTrue(controller.isVisible)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.level, .floating)
        XCTAssertFalse(window.styleMask.contains(.resizable), "a fixed-size pane")
        XCTAssertEqual(window.contentLayoutRect.width, SettingsView.size.width, accuracy: 1)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, SettingsView.size.height, accuracy: 1, "the pane itself, no extra strip")
        XCTAssertFalse(controller.windowShouldClose(window), "closing only hides it")
        XCTAssertFalse(controller.isVisible)
        window.close()
    }

    func testTheEditorWindowTellsItsSettingsToGoWhenItHides() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-setwin2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        let model = EditorModel()
        let editor = EditorWindowController(model: model)
        let settings = SettingsWindowController(model: model)
        editor.onHide = { settings.hide() }
        editor.show()
        settings.show(beside: editor.window)
        XCTAssertTrue(settings.isVisible)
        editor.hide()
        XCTAssertFalse(settings.isVisible)
        editor.window?.close(); settings.window?.close()
    }
}

@MainActor
final class SettingsWindowLayoutTests: XCTestCase {
    /// In its own window the pane must not sit under the (transparent) title bar: no empty band above the tabs, and the
    /// footer fully inside the window.
    func testTheFooterIsInsideTheSettingsWindow() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-setlayout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        UserDefaults.standard.set(true, forKey: "sayHiDone")

        let controller = SettingsWindowController(model: EditorModel())
        controller.show(beside: nil)
        defer { controller.window?.close() }
        let window = try XCTUnwrap(controller.window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let image = try ScreenCapture.usable(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        let lines = observations.compactMap { ($0.topCandidates(1).first?.string, $0.boundingBox) }
        let texts = lines.compactMap(\.0)
        XCTAssertTrue(texts.contains { $0.uppercased().contains("SCRAP 0.") }, "the footer's version text is drawn inside the window: \(texts)")
        // The tab labels start close to the top of the window, not a title bar's height down.
        let tabs = try XCTUnwrap(lines.first { ($0.0 ?? "").contains("General") }, "tabs not found: \(texts)")
        XCTAssertGreaterThan(tabs.1.maxY, 0.82, "the tabs sit near the top of the window (maxY \(tabs.1.maxY))")
    }
}
