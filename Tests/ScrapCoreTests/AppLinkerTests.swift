import XCTest
@testable import ScrapCore

final class AppLinkerTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: root) }

    private func dir(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testLocatesAppNextToCLIAndPrefersBrewOptPath() throws {
        let cellar = try dir("brew/Cellar/scrap/0.1.0")
        try fm.createDirectory(at: cellar.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: cellar.appendingPathComponent("Scrap.app"), withIntermediateDirectories: true)
        fm.createFile(atPath: cellar.appendingPathComponent("bin/scrap").path, contents: Data())
        // brew's bin symlink and opt symlink
        try fm.createDirectory(at: root.appendingPathComponent("brew/bin"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("brew/bin/scrap"), withDestinationURL: cellar.appendingPathComponent("bin/scrap"))
        try fm.createDirectory(at: root.appendingPathComponent("brew/opt"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("brew/opt/scrap"), withDestinationURL: cellar)

        let found = AppLinker.locateApp(executable: root.appendingPathComponent("brew/bin/scrap"))
        XCTAssertEqual(found?.path, root.appendingPathComponent("brew/opt/scrap/Scrap.app").path)
    }

    func testNotFoundWithoutAdjacentApp() throws {
        let bin = try dir("usr/bin")
        fm.createFile(atPath: bin.appendingPathComponent("scrap").path, contents: Data())
        XCTAssertNil(AppLinker.locateApp(executable: bin.appendingPathComponent("scrap")))
    }

    func testLinkIsIdempotentAndRelinks() throws {
        let apps = try dir("Applications")
        let a = try dir("a/Scrap.app"), b = try dir("b/Scrap.app")
        XCTAssertEqual(try AppLinker.link(app: a, into: apps), .linked(apps.appendingPathComponent("Scrap.app")))
        XCTAssertEqual(try AppLinker.link(app: a, into: apps), .alreadyLinked(apps.appendingPathComponent("Scrap.app")))
        XCTAssertEqual(try AppLinker.link(app: b, into: apps), .relinked(apps.appendingPathComponent("Scrap.app")))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: apps.appendingPathComponent("Scrap.app").path), b.path)
    }

    func testNeverTouchesARealApp() throws {
        let apps = try dir("Applications")
        let real = try dir("Applications/Scrap.app")
        fm.createFile(atPath: real.appendingPathComponent("keep").path, contents: Data("x".utf8))
        let app = try dir("a/Scrap.app")
        XCTAssertThrowsError(try AppLinker.link(app: app, into: apps)) { XCTAssertEqual($0 as? AppLinker.LinkError, .realAppInTheWay(real.path)) }
        XCTAssertThrowsError(try AppLinker.unlink(from: apps)) { XCTAssertEqual($0 as? AppLinker.LinkError, .notALink(real.path)) }
        XCTAssertTrue(fm.fileExists(atPath: real.appendingPathComponent("keep").path))
    }

    func testUnlinkRemovesOnlyTheLink() throws {
        let apps = try dir("Applications")
        let app = try dir("a/Scrap.app")
        XCTAssertFalse(try AppLinker.unlink(from: apps))
        _ = try AppLinker.link(app: app, into: apps)
        XCTAssertTrue(try AppLinker.unlink(from: apps))
        XCTAssertFalse(fm.fileExists(atPath: apps.appendingPathComponent("Scrap.app").path))
        XCTAssertTrue(fm.fileExists(atPath: app.path), "the real app is untouched")
    }
}
