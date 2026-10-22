import XCTest
import ServiceManagement
@testable import ScrapApp

final class LaunchAtLoginTests: XCTestCase {
    func testTurningItOnSaysSo() {
        XCTAssertEqual(LaunchAtLogin.message(requested: true, status: .enabled), "scrap will open when you log in.")
    }

    func testTurningItOffSaysSo() {
        XCTAssertEqual(LaunchAtLogin.message(requested: false, status: .notRegistered), "scrap won't open at login.")
    }

    func testAnApprovalRequestIsPassedOn() {
        for requested in [true, false] {
            XCTAssertTrue(LaunchAtLogin.message(requested: requested, status: .requiresApproval).contains("Login Items"))
        }
    }

    func testAFailureToTurnItOnIsNotReportedAsSuccess() {
        let message = LaunchAtLogin.message(requested: true, status: .notFound)
        XCTAssertTrue(message.contains("Couldn't turn it on"), message)
        XCTAssertTrue(LaunchAtLogin.message(requested: false, status: .enabled).contains("Couldn't turn it off"))
    }
}
