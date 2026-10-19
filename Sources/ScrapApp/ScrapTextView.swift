import AppKit
import ScrapCore

extension NSAttributedString.Key {
    /// Marks the start of a bullet or task marker. The characters stay in the text (the file is plain Markdown) but
    /// are collapsed and made invisible, and `ScrapLayoutManager` draws an icon in their place.
    static let scrapMarker = NSAttributedString.Key("scrap.marker")
    /// A smart bullet character (○ ● □ ■ …): clicking it flips it between its open and done form.
    static let scrapSmartBullet = NSAttributedString.Key("scrap.smartBullet")
    /// The address a link points to; ⌘-click opens it.
    static let scrapURL = NSAttributedString.Key("scrap.url")
}

enum MarkerKind: Int {
    case bullet = 1, taskOpen, taskDone
}

/// Draws the icons for list markers over the (invisible) marker characters.
final class ScrapLayoutManager: NSLayoutManager {
    var accent = NSColor.systemBlue
    var textColor = NSColor.labelColor
    /// Diameter of the drawn icon, and the horizontal room reserved for it (the markers are kerned to this width).
    var iconSize: CGFloat = 13
    var iconAdvance: CGFloat = 19

    /// Panels behind fenced code blocks and bars beside block quotes.
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // Whole panels and bars, even when only part of one is being redrawn (the graphics context clips the rest):
        // drawing just the redrawn paragraphs left seams and stale edges where a line's height had changed.
        var drawn = Set<Int>()
        storage.enumerateAttribute(.scrapBlock, in: characters, options: []) { value, range, _ in
            guard value != nil, let block = wholeRun(of: .scrapBlock, containing: range.location), drawn.insert(block.location).inserted,
                  let rect = fragments(in: block, origin: origin) else { return }
            textColor.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: -4, dy: -5), xRadius: 6, yRadius: 6).fill()
        }
        // The language label, at the top-right corner of its panel (like the portfolio's code blocks).
        storage.enumerateAttribute(.scrapBlockLabel, in: characters, options: []) { value, range, _ in
            guard let label = value as? String, let block = blockRange(containing: range.location),
                  let panel = fragments(in: block, origin: origin)?.insetBy(dx: -4, dy: -5) else { return }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: textColor.withAlphaComponent(0.55),
            ]
            let size = (label as NSString).size(withAttributes: attributes)
            (label as NSString).draw(at: NSPoint(x: panel.maxX - size.width - 10, y: panel.minY + 4), withAttributes: attributes)
        }
        drawn.removeAll()
        storage.enumerateAttribute(.scrapQuote, in: characters, options: []) { value, range, _ in
            guard value != nil, let quote = wholeRun(of: .scrapQuote, containing: range.location), drawn.insert(quote.location).inserted,
                  let rect = fragments(in: quote, origin: origin) else { return }
            accent.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX + 3, y: rect.minY + 1, width: 3, height: rect.height - 2), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    /// The whole code block (its run of `.scrapBlock` paragraphs) that contains `location`.
    private func blockRange(containing location: Int) -> NSRange? { wholeRun(of: .scrapBlock, containing: location) }

    /// The full run of `key` around `location`, not clipped to what is being drawn.
    private func wholeRun(of key: NSAttributedString.Key, containing location: Int) -> NSRange? {
        guard let storage = textStorage, location < storage.length else { return nil }
        var range = NSRange(location: 0, length: 0)
        guard storage.attribute(key, at: location, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) != nil else { return nil }
        return range
    }

    /// The union of the line fragments holding `characters`, in text view coordinates.
    private func fragments(in characters: NSRange, origin: NSPoint) -> NSRect? {
        let glyphs = glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        var union = NSRect.null
        enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in union = union.union(rect) }
        return union.isNull ? nil : union.offsetBy(dx: origin.x, dy: origin.y)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.scrapMarker, in: characters, options: []) { value, range, _ in
            guard let raw = value as? Int, let kind = MarkerKind(rawValue: raw), let rect = iconRect(forMarkerAt: range.location, origin: origin) else { return }
            draw(kind, in: rect)
        }
    }

    /// Where the icon for the marker starting at `index` is drawn, in text view coordinates.
    func iconRect(forMarkerAt index: Int, origin: NSPoint) -> NSRect? {
        guard index < (textStorage?.length ?? 0) else { return nil }
        let glyph = glyphIndexForCharacter(at: index)
        let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let used = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        let x = origin.x + line.minX + location(forGlyphAt: glyph).x
        return NSRect(x: x + (iconAdvance - iconSize) / 2, y: origin.y + used.midY - iconSize / 2, width: iconSize, height: iconSize)
    }

    private func draw(_ kind: MarkerKind, in rect: NSRect) {
        switch kind {
        case .bullet:
            let d = rect.width * 0.34
            textColor.withAlphaComponent(0.8).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)).fill()
        case .taskOpen:
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 1.6
            accent.setStroke()
            ring.stroke()
        case .taskDone:
            accent.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            // A check mark, in unit coordinates (y grows downward in the flipped text view).
            let flipped = NSGraphicsContext.current?.isFlipped ?? true
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * (flipped ? y : 1 - y))
            }
            let check = NSBezierPath()
            check.move(to: point(0.27, 0.52))
            check.line(to: point(0.43, 0.68))
            check.line(to: point(0.74, 0.33))
            check.lineWidth = 1.7
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        }
    }
}

/// A text view that makes task icons clickable and opens links on ⌘-click.
final class ScrapTextView: NSTextView {
    /// Called with a character index inside a task's marker when its icon is clicked.
    var onToggleTask: ((Int) -> Void)?
    /// Called with the index of a smart bullet character that was clicked.
    var onToggleSmartBullet: ((Int) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .inVisibleRect, .activeInKeyWindow], owner: self, userInfo: nil))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = taskMarkerIndex(at: point) {
            onToggleTask?(index)
            return
        }
        if let index = smartBulletIndex(at: point) {
            onToggleSmartBullet?(index)
            return
        }
        if event.modifierFlags.contains(.command), let url = linkURL(at: point) {
            NSWorkspace.shared.open(url)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        if taskMarkerIndex(at: point) != nil || smartBulletIndex(at: point) != nil || (event.modifierFlags.contains(.command) && linkURL(at: point) != nil) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    // MARK: Hit testing

    /// The start of a task marker whose icon is under `point` (view coordinates).
    func taskMarkerIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager as? ScrapLayoutManager, let storage = textStorage, let container = textContainer,
              storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let guess = lm.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        for candidate in [guess, guess - 1] where candidate >= 0 && candidate < storage.length {
            var range = NSRange(location: 0, length: 0)
            guard let raw = storage.attribute(.scrapMarker, at: candidate, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? Int,
                  let kind = MarkerKind(rawValue: raw), kind != .bullet,
                  let rect = lm.iconRect(forMarkerAt: range.location, origin: origin) else { continue }
            if rect.insetBy(dx: -4, dy: -3).contains(point) { return range.location }
        }
        return nil
    }

    /// The index of the smart bullet character under `point` (view coordinates).
    func smartBulletIndex(at point: NSPoint) -> Int? {
        guard let lm = layoutManager, let storage = textStorage, let container = textContainer, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let guess = lm.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
        for candidate in [guess, guess - 1] where candidate >= 0 && candidate < storage.length {
            var range = NSRange(location: 0, length: 0)
            guard storage.attribute(.scrapSmartBullet, at: candidate, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) != nil else { continue }
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
                .offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -5, dy: -3)
            if rect.contains(point) { return range.location }
        }
        return nil
    }

    func linkURL(at point: NSPoint) -> URL? {
        guard let lm = layoutManager, let storage = textStorage, let container = textContainer, storage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let index = lm.characterIndex(for: local, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard index < storage.length,
              lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: index), length: 1), in: container)
                .insetBy(dx: -1, dy: 0).contains(local),
              let string = storage.attribute(.scrapURL, at: index, effectiveRange: nil) as? String else { return nil }
        return URL(string: string)
    }
}
