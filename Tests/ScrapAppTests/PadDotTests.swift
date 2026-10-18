import AppKit
import SwiftUI
import XCTest
@testable import ScrapApp
import ScrapCore

final class PadDotStyleTests: XCTestCase {
    func testThreeStatesAreClearlyDifferent() {
        let open = PadDotStyle.make(current: true, empty: false)
        let written = PadDotStyle.make(current: false, empty: false)
        let empty = PadDotStyle.make(current: false, empty: true)

        XCTAssertEqual(open.fillOpacity, 1, "the open pad is a solid disc")
        XCTAssertEqual(open.ringWidth, 0)
        XCTAssertGreaterThan(open.halo, 0, "with a halo")
        XCTAssertGreaterThan(open.diameter, written.diameter, "and a little larger")

        XCTAssertGreaterThan(written.innerDot, 4, "a pad with text has a clear dot in the middle")
        XCTAssertEqual(written.ringOpacity, 1)
        XCTAssertGreaterThanOrEqual(written.ringWidth, 2)

        XCTAssertEqual(empty.innerDot, 0, "an empty pad has no dot")
        XCTAssertLessThan(empty.ringOpacity, written.ringOpacity, "and a fainter ring")
        XCTAssertLessThan(empty.ringWidth, written.ringWidth, "and a thinner one")
        XCTAssertEqual(empty.fillOpacity, 0)
        XCTAssertEqual(empty.halo, 0)
    }

    func testTheOpenPadIsTheOpenPadWhetherOrNotItHasText() {
        XCTAssertEqual(PadDotStyle.make(current: true, empty: true), PadDotStyle.make(current: true, empty: false))
    }

    func testEveryStateFitsItsSlotIncludingTheHalo() {
        for (current, empty) in [(true, false), (false, false), (false, true)] {
            let s = PadDotStyle.make(current: current, empty: empty)
            XCTAssertLessThanOrEqual(s.diameter + s.halo * 2, PadDotStyle.slot, "current: \(current), empty: \(empty)")
            XCTAssertLessThan(s.innerDot, s.diameter - s.ringWidth * 2 + 1)
        }
    }
}

final class FooterTintTests: XCTestCase {
    private func rgb(_ c: NSColor) -> [CGFloat] {
        let s = c.usingColorSpace(.sRGB)!
        return [s.redComponent, s.greenComponent, s.blueComponent]
    }

    func testBlendMovesTowardsThePadColourByTheStrength() {
        let bg = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let pad = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let out = rgb(FooterTint.color(background: bg, pad: pad, strength: 0.2))
        XCTAssertEqual(out[0], 0.1 + (1 - 0.1) * 0.2, accuracy: 0.01)
        XCTAssertEqual(out[1], 0.2 * 0.8, accuracy: 0.01)
        XCTAssertEqual(out[2], 0.3 * 0.8, accuracy: 0.01)
    }

    func testZeroStrengthIsTheBackgroundAndOutOfRangeIsClamped() {
        let bg = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let pad = NSColor.systemRed
        XCTAssertEqual(rgb(FooterTint.color(background: bg, pad: pad, strength: 0)), rgb(bg))
        XCTAssertEqual(rgb(FooterTint.color(background: bg, pad: pad, strength: 9)), rgb(pad))
        XCTAssertEqual(rgb(FooterTint.color(background: bg, pad: pad, strength: -3)), rgb(bg))
    }

    func testEachPadGivesADifferentTintAndItStaysSubtle() {
        for theme in [Themes.all.first { $0.id == "cobalt2-dark" }!, Themes.all.first { $0.id == "cobalt2-light" }!] {
            let bg = NSColor(hex: theme.background)
            let strength: CGFloat = theme.isDark ? 0.18 : 0.14
            let tints = (1...7).map { FooterTint.color(background: bg, pad: PadColors.nsColor(for: $0), strength: strength) }
            XCTAssertEqual(Set(tints.map { rgb($0).map { ($0 * 255).rounded() } }.map { "\($0)" }).count, 7, "each pad tints differently")
            for tint in tints {
                for (a, b) in zip(rgb(tint), rgb(bg)) {
                    XCTAssertLessThanOrEqual(abs(a - b), strength + 0.01, "no channel moves further than the strength allows")
                }
            }
        }
    }
}

/// The dots and the tinted footer, as a picture (opt-in).
@MainActor
final class PadDotSnapshotTests: XCTestCase {
    func testRender() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCRAP_SNAPSHOT_DIR"] else { throw XCTSkip("set SCRAP_SNAPSHOT_DIR to write snapshots") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scrap-dots-\(UUID().uuidString)")
        let pads = home.appendingPathComponent("pads")
        try FileManager.default.createDirectory(at: pads, withIntermediateDirectories: true)
        let old = getenv("HOME").map { String(cString: $0) }
        setenv("HOME", home.path, 1)
        defer { if let old { setenv("HOME", old, 1) }; try? FileManager.default.removeItem(at: home) }
        try Config.save(Config.File(folder: pads.path, pads: 7), home: home)
        for n in [1, 3, 4, 6] { try "pad \(n) has some text".write(to: pads.appendingPathComponent("\(n).md"), atomically: true, encoding: .utf8) }
        UserDefaults.standard.set(true, forKey: "sayHiDone")
        defer { ["sayHiDone", "lastPad", "appearance", "themeFamily", "tintFooter"].forEach { UserDefaults.standard.removeObject(forKey: $0) } }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        func shot(_ name: String, pad: Int, appearance: String, theme: String = "cobalt2", tint: Bool = true) throws {
            UserDefaults.standard.set(pad, forKey: "lastPad")
            UserDefaults.standard.set(appearance, forKey: "appearance")
            UserDefaults.standard.set(theme, forKey: "themeFamily")
            UserDefaults.standard.set(tint, forKey: "tintFooter")
            let model = EditorModel()
            let size = CGSize(width: 520, height: 200)
            let view = NSHostingView(rootView: ContentView(model: model).frame(width: size.width, height: size.height))
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)   // like the popover does
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
        }
        try shot("dots-pad4-dark.png", pad: 4, appearance: "dark")
        try shot("dots-pad6-light.png", pad: 6, appearance: "light", theme: "one")
        try shot("dots-pad4-untinted.png", pad: 4, appearance: "dark", tint: false)
    }
}
