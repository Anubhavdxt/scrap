import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

/// Writes the README's screenshots and the frames of its demo GIF, from the real app views (run `make demo`).
@MainActor
final class DemoAssetsTests: XCTestCase {
    private var home: URL!
    private var pads: URL!
    private var oldHome: String?
    private let keys = ["themeFamily", "appearance", "sayHiDone", "lastPad", "fontSize", "rendered"]

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-demo-\(UUID().uuidString)")
        pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set(true, forKey: "sayHiDone")
    }

    override func tearDownWithError() throws {
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ n: Int, _ text: String) throws { try text.write(to: pads.appendingPathComponent("\(n).md"), atomically: true, encoding: .utf8) }

    private func find(_ v: NSView) -> NSTextView? { (v as? NSTextView) ?? v.subviews.lazy.compactMap(find).first }

    private func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func makeWindow(_ model: EditorModel) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 220, y: 260, width: 520, height: 380), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { window.standardWindowButton(button)?.isHidden = true }
        window.contentView = NSHostingView(rootView: ContentView(model: model).environment(\.scrapWindowed, true))
        window.makeKeyAndOrderFront(nil)
        spin(0.6)
        return window
    }

    private func shot(_ window: NSWindow, _ name: String, to dir: String) throws {
        spin(0.25)
        let image = try ScreenCapture.usable(CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]))
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
    }

    private func type(_ text: String, into window: NSWindow, every: Int, frame: (() throws -> Void)?) throws {
        guard let tv = find(window.contentView!) else { return XCTFail("no editor") }
        window.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        var count = 0
        for ch in text {
            tv.insertText(String(ch), replacementRange: tv.selectedRange())
            count += 1
            spin(0.02)
            if count % every == 0 { try frame?() }
        }
        try frame?()
    }

    func testWriteDemoAssets() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_DEMO_DIR"] else { throw XCTSkip("set SCRAP_DEMO_DIR to write the demo assets") }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try write(1, """
        # Launch plan

        Ship **scrap 0.4** this week, then tell people.

        - [x] cut the release
        - [ ] write the README
        - [ ] post to r/macapps

        ```swift
        let pads = 7
        print("a scratchpad that stays out of the way")
        ```
        """)
        try write(2, "# Groceries\n- [ ] oat milk\n- [ ] eggs\n- [ ] lemons")
        try write(3, "# Pasta recipe\nBoil the water, salt it well.\nSimmer the tomatoes with garlic and basil for 20 minutes.\nSave a cup of pasta water.")
        try write(4, "Call the dentist\nhttps://example.com/appointments")
        UserDefaults.standard.set("cobalt2", forKey: "themeFamily")
        UserDefaults.standard.set("dark", forKey: "appearance")
        UserDefaults.standard.set(15.0, forKey: "fontSize")

        let model = EditorModel()
        let window = makeWindow(model)
        defer { window.close() }
        find(window.contentView!)?.setSelectedRange(NSRange(location: 14, length: 0))   // the code fences hide away from the caret
        try shot(window, "hero.png", to: dir)

        // Search, with a typo.
        model.showSearch = true
        spin(0.4)
        guard let field = window.firstResponder as? NSTextView else { return XCTFail("the search field has no keyboard") }
        for ch in "recipie" { field.insertText(String(ch), replacementRange: field.selectedRange()); spin(0.05) }
        spin(0.7)
        try shot(window, "search.png", to: dir)
        model.showSearch = false
        spin(0.3)

        // A light theme, in a window of its own.
        UserDefaults.standard.set("gruvbox", forKey: "themeFamily")
        UserDefaults.standard.set("light", forKey: "appearance")
        let light = makeWindow(model)
        find(light.contentView!)?.setSelectedRange(NSRange(location: 14, length: 0))
        try shot(light, "light.png", to: dir)
        light.close()

        // The GIF: typing into an empty pad, ticking a task, then a search.
        UserDefaults.standard.set("cobalt2", forKey: "themeFamily")
        UserDefaults.standard.set("dark", forKey: "appearance")
        model.open(number: 5)
        spin(0.5)
        var index = 0
        func frame() throws { try shot(window, String(format: "frame-%03d.png", index), to: dir); index += 1 }
        try frame()
        try type("# Trip to Lisbon\n\nBook the **flights** and the hotel.\n\n- [ ] passports\n- [ ] ", into: window, every: 6, frame: frame)
        try type("tram pass\n\n```sh\nscrap add \"pack sunscreen\"\n```\n", into: window, every: 6, frame: frame)
        model.open(number: 1)
        spin(0.4); try frame(); try frame()
        model.showSearch = true
        spin(0.4)
        guard let search = window.firstResponder as? NSTextView else { return XCTFail("the search field has no keyboard") }
        for ch in "tomatoes" { search.insertText(String(ch), replacementRange: search.selectedRange()); spin(0.05); if index % 1 == 0 { try frame() } }
        spin(0.6); try frame(); try frame(); try frame()
    }
}
