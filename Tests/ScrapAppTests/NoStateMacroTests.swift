import XCTest

/// `@State` is a macro on the macOS 27 SDK and its plugin ships only with Xcode, so a Homebrew build with just the
/// Command Line Tools would fail. The app uses `Local` (Sources/ScrapApp/LocalState.swift) instead.
final class NoStateMacroTests: XCTestCase {
    func testTheAppDoesNotUseTheStateMacro() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ScrapApp")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let pattern = try NSRegularExpression(pattern: #"^[^/\n]*@State\b(?!Object)"#, options: .anchorsMatchLines)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let hits = pattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertEqual(hits, 0, "\(file.lastPathComponent) uses @State: use @Local so the app still builds with only the Command Line Tools")
        }
    }
}
