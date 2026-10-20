import XCTest
import AppKit

/// Tests that look at what is really on screen need a live display: on a locked or sleeping screen a capture comes back
/// black, so those tests skip rather than fail.
enum ScreenCapture {
    /// True when the picture is one flat colour (a locked screen, an empty capture).
    static func isBlank(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard rep.pixelsWide > 4, rep.pixelsHigh > 4, let first = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2) else { return true }
        for step in 1...12 {
            let x = rep.pixelsWide * step / 13, y = rep.pixelsHigh * (13 - step) / 13
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            if abs(c.redComponent - first.redComponent) + abs(c.greenComponent - first.greenComponent) + abs(c.blueComponent - first.blueComponent) > 0.02 { return false }
        }
        return true
    }

    static func usable(_ image: CGImage?) throws -> CGImage {
        guard let image, !isBlank(image) else { throw XCTSkip("the screen can't be captured here (locked, asleep or headless)") }
        return image
    }
}
