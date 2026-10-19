import AppKit
import ScrapCore

/// Restyling after a keystroke: only the paragraphs whose styling can have changed, not the whole pad.
extension MarkdownStyler {
    /// The part of the new text (in its own coordinates) whose styling may differ from before: the edit itself, plus
    /// every place where the spans changed (a fence typed above a code block restyles the block).
    static func dirtyRange(oldText: String, newText: String, oldSpans: [Span], newSpans: [Span]) -> NSRange {
        let old = oldText as NSString, new = newText as NSString
        let (prefix, suffix) = commonEnds(old, new)
        let delta = new.length - old.length
        var dirty = NSRange(location: prefix, length: new.length - suffix - prefix)

        func map(_ x: Int) -> Int {
            if x <= prefix { return x }
            if x >= old.length - suffix { return x + delta }
            return min(x, dirty.upperBound)
        }
        func shifted(_ s: Span) -> Span {
            var copy = s
            copy.range.location += delta
            return copy
        }

        let common = min(oldSpans.count, newSpans.count)
        var front = 0
        while front < common, oldSpans[front] == newSpans[front] { front += 1 }
        var back = 0
        while back < common - front, shifted(oldSpans[oldSpans.count - 1 - back]) == newSpans[newSpans.count - 1 - back] { back += 1 }

        for i in front..<(newSpans.count - back) { dirty = NSUnionRange(dirty, newSpans[i].range) }
        for i in front..<(oldSpans.count - back) {
            let r = oldSpans[i].range
            let lower = map(r.location), upper = map(r.upperBound)
            dirty = NSUnionRange(dirty, NSRange(location: lower, length: max(upper - lower, 0)))
        }
        let lower = min(dirty.location, new.length), upper = min(dirty.upperBound, new.length)
        return NSRange(location: lower, length: upper - lower)
    }

    /// The length of the text the two strings share at the start and at the end.
    private static func commonEnds(_ old: NSString, _ new: NSString) -> (prefix: Int, suffix: Int) {
        let shortest = min(old.length, new.length)
        var prefix = 0
        while prefix < shortest, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < shortest - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        return (prefix, suffix)
    }

    /// Brings the styling of `storage` (already holding `newText`, with the old attributes carried along) up to date.
    /// Returns the ranges it restyled.
    @discardableResult
    static func applyEdit(oldText: String, oldSpans: [Span], newSpans: [Span], oldReveal: NSRange, newReveal: NSRange,
                          to storage: NSTextStorage, style: MarkdownStyle) -> [NSRange] {
        let new = storage.string as NSString
        let dirty = dirtyRange(oldText: oldText, newText: storage.string, oldSpans: oldSpans, newSpans: newSpans)
        var wanted = [paragraphs(dirty, in: new), paragraphs(newReveal, in: new)]
        // The paragraph that was revealed before is hidden again, wherever it ended up.
        let old = oldText as NSString
        let (_, suffix) = commonEnds(old, new)
        let movedLocation = oldReveal.location >= old.length - suffix ? oldReveal.location + new.length - old.length : oldReveal.location
        if movedLocation >= 0, movedLocation <= new.length {
            wanted.append(paragraphs(NSRange(location: movedLocation, length: 0), in: new))
        }
        var merged: [NSRange] = []
        for r in wanted.sorted(by: { $0.location < $1.location }) {
            if let last = merged.last, r.location <= last.upperBound { merged[merged.count - 1] = NSUnionRange(last, r) } else { merged.append(r) }
        }
        for r in merged where r.length > 0 || new.length == 0 {
            apply(newSpans, to: storage, range: r, reveal: newReveal, style: style)
        }
        return merged
    }

    private static func paragraphs(_ range: NSRange, in text: NSString) -> NSRange {
        let location = min(range.location, text.length)
        return text.paragraphRange(for: NSRange(location: location, length: min(range.length, text.length - location)))
    }
}
