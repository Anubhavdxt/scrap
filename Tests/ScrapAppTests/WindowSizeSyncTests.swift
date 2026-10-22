import XCTest
@testable import ScrapApp
import ScrapCore

@MainActor
final class WindowSizeSyncTests: XCTestCase {
    private var home: URL!
    private var oldHome: String?
    private let keys = ["windowCols", "windowRows", "fontSize", "sayHiDone"]

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: "sayHiDone")
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    private func contentSize(_ window: NSWindow) -> CGSize { window.contentRect(forFrameRect: window.frame).size }

    private func shownController() -> (EditorWindowController, NSWindow) {
        let controller = EditorWindowController(model: EditorModel())
        controller.show()
        return (controller, controller.window!)
    }

    // MARK: The arithmetic

    func testColumnsAndRowsRoundTripThroughASize() {
        for (cols, rows) in [(64, 16), (30, 8), (100, 40), (120, 25)] {
            let size = WindowSize.contentSize(cols: cols, rows: rows)
            let back = WindowSize.cells(forContentSize: size)
            let again = WindowSize.contentSize(cols: back.cols, rows: back.rows)
            XCTAssertEqual(again.width, size.width, accuracy: 0.5, "\(cols)x\(rows)")
            XCTAssertEqual(again.height, size.height, accuracy: 0.5, "\(cols)x\(rows)")
        }
    }

    func testSnappingGoesToTheNearestWholeCellAndStaysInRange() {
        let exact = WindowSize.contentSize(cols: 80, rows: 20)
        let snapped = WindowSize.snapped(CGSize(width: exact.width + 3, height: exact.height - 4))
        XCTAssertEqual(snapped.width, exact.width, accuracy: 0.5)
        XCTAssertEqual(snapped.height, exact.height, accuracy: 0.5)
        let tiny = WindowSize.cells(forContentSize: CGSize(width: 10, height: 10))
        XCTAssertEqual(tiny.cols, WindowSize.colsRange.lowerBound)
        XCTAssertEqual(tiny.rows, WindowSize.rowsRange.lowerBound)
    }

    // MARK: Settings drive the window

    func testChangingColumnsAndRowsResizesTheDetachedWindow() {
        let (controller, window) = shownController()
        defer { window.close() }
        XCTAssertEqual(contentSize(window).width, WindowSize.current().width, accuracy: 1, "starts at the Settings size")
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)

        UserDefaults.standard.set(90, forKey: "windowCols")
        UserDefaults.standard.set(24, forKey: "windowRows")
        controller.applySettings()
        XCTAssertEqual(contentSize(window).width, WindowSize.current().width, accuracy: 1)
        XCTAssertEqual(contentSize(window).height, WindowSize.current().height, accuracy: 1)
        XCTAssertEqual(window.frame.minX, topLeft.x, accuracy: 0.5, "the top-left corner stays put")
        XCTAssertEqual(window.frame.maxY, topLeft.y, accuracy: 0.5)
    }

    func testChangingTheFontSizeAlsoMovesTheWindowToTheNewSize() {
        let (controller, window) = shownController()
        defer { window.close() }
        let before = contentSize(window)
        UserDefaults.standard.set(20.0, forKey: "fontSize")
        controller.applySettings()
        XCTAssertGreaterThan(contentSize(window).width, before.width + 20, "the same columns are wider in a bigger font")
        XCTAssertEqual(contentSize(window).width, WindowSize.current().width, accuracy: 1)
    }

    // MARK: Resizing the window drives Settings

    func testResizingTheWindowSnapsAndWritesTheColumnsAndRowsBack() {
        let (controller, window) = shownController()
        defer { window.close() }
        let wanted = WindowSize.contentSize(cols: 100, rows: 30)
        // What the user drags to: close to 100 x 30, but not exactly on a cell boundary.
        let dragged = window.frameRect(forContentRect: NSRect(origin: .zero, size: CGSize(width: wanted.width + 4, height: wanted.height - 5))).size
        let snappedFrame = controller.windowWillResize(window, to: dragged)
        window.setFrame(NSRect(origin: window.frame.origin, size: snappedFrame), display: false)
        XCTAssertEqual(contentSize(window).width, wanted.width, accuracy: 0.5, "snapped to the cell grid")

        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "windowCols"), 100)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "windowRows"), 30)
        // The popover reads the same numbers, so both are the same size.
        XCTAssertEqual(WindowSize.current().width, contentSize(window).width, accuracy: 0.5)
        XCTAssertEqual(WindowSize.current().height, contentSize(window).height, accuracy: 0.5)
    }

    func testApplyingSettingsAfterAManualResizeLeavesTheWindowAlone() {
        let (controller, window) = shownController()
        defer { window.close() }
        let wanted = WindowSize.contentSize(cols: 80, rows: 20)
        window.setFrame(NSRect(origin: window.frame.origin, size: window.frameRect(forContentRect: NSRect(origin: .zero, size: wanted)).size), display: false)
        controller.windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: window))
        let frame = window.frame
        controller.applySettings()
        XCTAssertEqual(window.frame, frame, "already in step, so nothing moves")
    }
}
