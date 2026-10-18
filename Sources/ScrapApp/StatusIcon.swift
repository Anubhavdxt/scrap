import AppKit

enum StatusIcon {
    /// A copy of a template (black on clear) image filled with `color`, which macOS won't recolour.
    static func tinted(_ template: NSImage, with color: NSColor) -> NSImage {
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = template.accessibilityDescription
        return image
    }
}
