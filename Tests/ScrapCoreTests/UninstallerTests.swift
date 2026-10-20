import XCTest
@testable import ScrapCore

final class UninstallerTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Let a test that made a folder read-only clean up.
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("Applications").path)
        try? fm.removeItem(at: root)
    }

    /// A pretend Homebrew: `<root>/brew/bin/brew`, a keg with the CLI, and brew's own `bin/scrap` link to it.
    @discardableResult private func fakeHomebrew(withBrew: Bool = true) throws -> URL {
        let keg = root.appendingPathComponent("brew/Cellar/scrap/0.3.0")
        try fm.createDirectory(at: keg.appendingPathComponent("bin"), withIntermediateDirectories: true)
        fm.createFile(atPath: keg.appendingPathComponent("bin/scrap").path, contents: Data())
        try fm.createDirectory(at: root.appendingPathComponent("brew/bin"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: root.appendingPathComponent("brew/bin/scrap"), withDestinationURL: keg.appendingPathComponent("bin/scrap"))
        if withBrew {
            let brew = root.appendingPathComponent("brew/bin/brew")
            fm.createFile(atPath: brew.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        }
        return root.appendingPathComponent("brew/bin/scrap")
    }

    private func applications(withLinkTo target: String? = nil, realApp: Bool = false) throws -> URL {
        let apps = root.appendingPathComponent("Applications")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        if let target { try fm.createSymbolicLink(at: apps.appendingPathComponent("Scrap.app"), withDestinationURL: URL(fileURLWithPath: target)) }
        if realApp { try fm.createDirectory(at: apps.appendingPathComponent("Scrap.app"), withIntermediateDirectories: true) }
        return apps
    }

    // MARK: Plan

    func testItFindsTheHomebrewPrefixThroughBrewsOwnLink() throws {
        let exe = try fakeHomebrew()
        XCTAssertEqual(Uninstaller.homebrewPrefix(executable: exe)?.path, root.appendingPathComponent("brew").path)
    }

    func testACopyFromMakeInstallIsNotHomebrews() throws {
        let local = root.appendingPathComponent("usr/local/bin")
        try fm.createDirectory(at: local, withIntermediateDirectories: true)
        fm.createFile(atPath: local.appendingPathComponent("scrap").path, contents: Data())
        XCTAssertNil(Uninstaller.homebrewPrefix(executable: local.appendingPathComponent("scrap")))
        XCTAssertThrowsError(try Uninstaller.plan(executable: local.appendingPathComponent("scrap"))) {
            XCTAssertEqual($0 as? Uninstaller.UninstallError, .notHomebrew)
        }
    }

    func testItNeedsBrewItselfToBeThere() throws {
        let exe = try fakeHomebrew(withBrew: false)
        XCTAssertThrowsError(try Uninstaller.plan(executable: exe)) {
            guard case Uninstaller.UninstallError.brewNotFound(let path)? = $0 as? Uninstaller.UninstallError else { return XCTFail("\($0)") }
            XCTAssertTrue(path.hasSuffix("brew/bin/brew"))
        }
    }

    func testThePlanPointsAtThatHomebrew() throws {
        let exe = try fakeHomebrew()
        let apps = try applications()
        let plan = try Uninstaller.plan(executable: exe, applications: apps)
        XCTAssertEqual(plan.brew.path, root.appendingPathComponent("brew/bin/brew").path)
        XCTAssertEqual(plan.applications, apps)
    }

    // MARK: Run

    func testTheLinkGoesBeforeBrewRuns() throws {
        let exe = try fakeHomebrew()
        let apps = try applications(withLinkTo: "/opt/homebrew/opt/scrap/Scrap.app")
        let plan = try Uninstaller.plan(executable: exe, applications: apps)
        var linkWasGoneWhenBrewRan: Bool?
        var arguments: [String] = []
        let report = try Uninstaller.run(plan) { _, args in
            linkWasGoneWhenBrewRan = (try? self.fm.destinationOfSymbolicLink(atPath: apps.appendingPathComponent("Scrap.app").path)) == nil
            arguments = args
            return 0
        }
        XCTAssertTrue(report.removedLink)
        XCTAssertEqual(linkWasGoneWhenBrewRan, true, "no dead link is ever left behind")
        XCTAssertEqual(arguments, ["uninstall", "scrap"])
    }

    func testNoLinkIsFine() throws {
        let exe = try fakeHomebrew()
        let plan = try Uninstaller.plan(executable: exe, applications: try applications())
        var ran = false
        let report = try Uninstaller.run(plan) { _, _ in ran = true; return 0 }
        XCTAssertFalse(report.removedLink)
        XCTAssertTrue(ran)
    }

    func testARealAppInApplicationsIsNeverTouched() throws {
        let exe = try fakeHomebrew()
        let apps = try applications(realApp: true)
        let plan = try Uninstaller.plan(executable: exe, applications: apps)
        var ran = false
        let report = try Uninstaller.run(plan) { _, _ in ran = true; return 0 }
        XCTAssertEqual(report.leftRealApp, apps.appendingPathComponent("Scrap.app").path)
        XCTAssertFalse(report.removedLink)
        XCTAssertTrue(fm.fileExists(atPath: apps.appendingPathComponent("Scrap.app").path), "still there")
        XCTAssertTrue(ran, "brew still removes its own copy")
    }

    func testABrewFailureIsReportedWithItsExitCode() throws {
        let exe = try fakeHomebrew()
        let apps = try applications(withLinkTo: "/nowhere/Scrap.app")
        let plan = try Uninstaller.plan(executable: exe, applications: apps)
        XCTAssertThrowsError(try Uninstaller.run(plan) { _, _ in 1 }) {
            XCTAssertEqual($0 as? Uninstaller.UninstallError, .brewFailed(1))
            XCTAssertTrue(($0 as? Uninstaller.UninstallError)?.errorDescription?.contains("already been removed") == true)
        }
    }

    func testIfTheLinkCantBeRemovedNothingIsUninstalled() throws {
        let exe = try fakeHomebrew()
        let apps = try applications(withLinkTo: "/x/Scrap.app")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: apps.path)   // read-only folder
        let plan = try Uninstaller.plan(executable: exe, applications: apps)
        var ran = false
        XCTAssertThrowsError(try Uninstaller.run(plan) { _, _ in ran = true; return 0 }) {
            guard case Uninstaller.UninstallError.cantRemoveLink? = $0 as? Uninstaller.UninstallError else { return XCTFail("\($0)") }
        }
        XCTAssertFalse(ran, "brew must not run while the link is still there")
    }

    // MARK: The command

    /// Run from a build folder (not Homebrew's), the command refuses and changes nothing.
    func testTheCommandRefusesOutsideHomebrew() throws {
        let cli = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("scrap-cli")
        try XCTSkipUnless(fm.isExecutableFile(atPath: cli.path), "scrap-cli is not built next to the tests")
        let process = Process()
        process.executableURL = cli
        process.arguments = ["uninstall", "--yes"]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 1)
        XCTAssertTrue(message.contains("wasn't installed with Homebrew"), message)
    }
}
