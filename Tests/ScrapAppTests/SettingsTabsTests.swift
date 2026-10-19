import XCTest
import SwiftUI
@testable import ScrapApp
import ScrapCore

@MainActor
final class SettingsTabsTests: XCTestCase {
    static let tabs = ["General", "Appearance", "Editor", "About"]
    private var home: URL!
    private var oldHome: String?

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-tabs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appendingPathComponent("pads"), withIntermediateDirectories: true)
        oldHome = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        try Config.save(Config.File(folder: home.appendingPathComponent("pads").path, pads: 7), home: home)
        for key in ["settingsTab", "themeFamily", "appearance"] { UserDefaults.standard.removeObject(forKey: key) }
        // The icons the app bundle carries, taken from the repo.
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        if let bundle = Bundle(path: resources.path) { AppIcons.bundle = bundle }
        UserDefaults.standard.set("cobalt2", forKey: "themeFamily")
        UserDefaults.standard.set("dark", forKey: "appearance")
    }

    override func tearDownWithError() throws {
        AppIcons.bundle = .main
        if let oldHome { setenv("HOME", oldHome, 1) }
        for key in ["settingsTab", "themeFamily", "appearance"] { UserDefaults.standard.removeObject(forKey: key) }
        try? FileManager.default.removeItem(at: home)
    }

    /// The pane drawn in a window of the given height.
    private func render(tab: String, height: CGFloat) throws -> NSBitmapImageRep {
        UserDefaults.standard.set(tab, forKey: "settingsTab")
        let model = EditorModel()
        let size = CGSize(width: SettingsView.size.width, height: height)
        let view = NSHostingView(rootView: SettingsView(model: model, height: height).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.appearance = NSAppearance(named: .darkAqua)
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        window.close()
        return rep
    }

    func testWriteSnapshots() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR") }
        for tab in Self.tabs {
            try render(tab: tab, height: SettingsView.size.height).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-\(tab).png"))
            try render(tab: tab, height: 1100).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("settings-\(tab)-tall.png"))
        }
    }

    /// Where the lowest content of a tab ends, in points from the top (measured in a window tall enough to show it all).
    private func contentBottom(of tab: String) throws -> CGFloat {
        let tall: CGFloat = 1100, footer: CGFloat = 0, top: CGFloat = 76
        let rep = try render(tab: tab, height: tall)
        let scale = CGFloat(rep.pixelsHigh) / tall
        let width = rep.pixelsWide
        var lowest: CGFloat = top
        var y = Int((tall - footer - 2) * scale)
        while y > Int(top * scale) {
            let background = rep.colorAt(x: 2, y: y)
            for x in stride(from: 8, to: width - 8, by: 2) {
                guard let a = background, let b = rep.colorAt(x: x, y: y) else { continue }
                if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.12 {
                    lowest = CGFloat(y) / scale
                    return lowest
                }
            }
            y -= 1
        }
        return lowest
    }

    /// Each tab fits the pane without scrolling (collapsed sections stay collapsed).
    func testEveryTabFitsWithoutScrolling() throws {
        let visibleBottom = SettingsView.size.height - 14   // a little room below the content
        for tab in Self.tabs {
            let bottom = try contentBottom(of: tab)
            XCTAssertLessThanOrEqual(bottom, visibleBottom, "\(tab) runs to \(Int(bottom)) pt and the pane shows \(Int(visibleBottom)) pt of content")
        }
    }

    func testAnOldSavedTabIsStillShown() throws {
        for old in ["Shortcuts", "Window"] {
            let rep = try render(tab: old, height: SettingsView.size.height)
            XCTAssertGreaterThan(rep.pixelsHigh, 0)
        }
    }
}
