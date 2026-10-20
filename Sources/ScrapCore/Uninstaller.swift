import Foundation

/// `scrap uninstall`: takes the link out of /Applications and then runs `brew uninstall scrap`, so no dead link is left
/// behind (a formula can't do that itself: Homebrew has no uninstall hook for formulae). Pads are never touched.
public enum Uninstaller {
    public struct Plan: Equatable {
        /// `<prefix>/bin/brew` of the Homebrew this copy of scrap was installed by.
        public var brew: URL
        /// Where the `Scrap.app` link lives (/Applications).
        public var applications: URL
    }

    public struct Report: Equatable {
        /// The link was there and has been removed.
        public var removedLink: Bool
        /// A real Scrap.app (not a link) is in Applications; it was left alone, and says where it is.
        public var leftRealApp: String?
    }

    public enum UninstallError: LocalizedError, Equatable {
        case notHomebrew
        case brewNotFound(String)
        case brewFailed(Int32)
        case cantRemoveLink(String)

        public var errorDescription: String? {
            switch self {
            case .notHomebrew:
                "this copy of scrap wasn't installed with Homebrew. If you used `make install`, run `make uninstall` in the source folder."
            case .brewNotFound(let path):
                "couldn't find Homebrew at \(path). Run `scrap unlink`, then `brew uninstall scrap`."
            case .brewFailed(let code):
                "`brew uninstall scrap` failed (exit \(code)). The Applications link has already been removed; run `brew uninstall scrap` yourself to finish."
            case .cantRemoveLink(let message):
                "couldn't remove the link from Applications (\(message)). Nothing has been uninstalled."
            }
        }
    }

    /// The Homebrew prefix when `executable` is the keg's `bin/scrap` (`<prefix>/Cellar/scrap/<version>/bin/scrap`).
    public static func homebrewPrefix(executable: URL) -> URL? {
        let path = executable.resolvingSymlinksInPath().path
        guard let range = path.range(of: "/Cellar/scrap/") else { return nil }
        return URL(fileURLWithPath: String(path[..<range.lowerBound]))
    }

    public static func plan(executable: URL, applications: URL = URL(fileURLWithPath: "/Applications"),
                            fileManager: FileManager = .default) throws -> Plan {
        guard let prefix = homebrewPrefix(executable: executable) else { throw UninstallError.notHomebrew }
        let brew = prefix.appendingPathComponent("bin/brew")
        guard fileManager.isExecutableFile(atPath: brew.path) else { throw UninstallError.brewNotFound(brew.path) }
        return Plan(brew: brew, applications: applications)
    }

    /// Unlinks, then runs `brew` with the given arguments through `runBrew` (which returns its exit status).
    public static func run(_ plan: Plan, runBrew: (_ brew: URL, _ arguments: [String]) throws -> Int32) throws -> Report {
        var report = Report(removedLink: false, leftRealApp: nil)
        do {
            report.removedLink = try AppLinker.unlink(from: plan.applications)
        } catch AppLinker.LinkError.notALink(let path) {
            report.leftRealApp = path   // a copy from `make install`: not ours to remove, and brew doesn't own it
        } catch {
            throw UninstallError.cantRemoveLink(error.localizedDescription)
        }
        let status = try runBrew(plan.brew, ["uninstall", "scrap"])
        guard status == 0 else { throw UninstallError.brewFailed(status) }
        return report
    }
}
