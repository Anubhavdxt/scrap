import XCTest
@testable import ScrapApp

final class AppIconTests: XCTestCase {
    func testUnknownIconFallsBackToTheDefault() {
        XCTAssertEqual(AppIcons.resolve("nope"), AppIcons.default)
        XCTAssertEqual(AppIcons.resolve("forest"), "forest")
        XCTAssertEqual(Set(AppIcons.all.map(\.id)).count, AppIcons.all.count)
        XCTAssertTrue(AppIcons.all.contains { $0.id == AppIcons.default })
    }

    func testEveryChoiceHasARenderedImageInTheRepo() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for choice in AppIcons.all {
            let url = root.appendingPathComponent("Resources/Icons/\(choice.id).png")
            XCTAssertNotNil(NSImage(contentsOf: url), "\(choice.id) icon missing: run make icons")
        }
    }

    func testNumberColourContrastsWithTheDisc() {
        XCTAssertEqual(PadDotStyle.numberColor(on: NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)).whiteComponent, 0, accuracy: 0.01)
        XCTAssertEqual(PadDotStyle.numberColor(on: NSColor(srgbRed: 0.2, green: 0.3, blue: 0.9, alpha: 1)).whiteComponent, 1, accuracy: 0.01)
    }
}
