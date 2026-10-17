import Foundation

/// A change to apply to a text view: replace `range` with `replacement`, then select `selection` (in the new text).
public struct TextEdit: Equatable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange
}

/// Markdown list helpers for the editor: continue a list on Return, indent with Tab, toggle task checkboxes.
/// Pure functions over UTF-16 offsets (what NSTextView uses), so they are easy to test.
public enum ListEditing {
    private static let marker = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|\d{1,9}[.)])([ \t]+)(\[[ xX]\][ \t]+)?"#)
    private static let step = "  "

    private struct Line {
        let range: NSRange        // without the line break
        let text: String
        let match: NSTextCheckingResult?
    }

    private static func line(at location: Int, in ns: NSString) -> Line {
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: min(location, ns.length), length: 0))
        let range = NSRange(location: start, length: contentsEnd - start)
        let text = ns.substring(with: range)
        let match = marker.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        return Line(range: range, text: text, match: match)
    }

    // MARK: Return

    /// Return on a list line: continue the list, or end it when the item is empty. nil = let the text view handle it.
    public static func returnKey(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let line = line(at: selection.location, in: ns)
        guard let m = line.match else { return nil }
        let column = selection.location - line.range.location
        guard column >= m.range.length else { return nil } // cursor is inside the marker

        let lineNS = line.text as NSString
        let content = lineNS.substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
        if content.isEmpty {
            // Empty item: drop the marker and end the list.
            return TextEdit(range: line.range, replacement: "", selection: NSRange(location: line.range.location, length: 0))
        }

        let indent = lineNS.substring(with: m.range(at: 1))
        let bullet = lineNS.substring(with: m.range(at: 2))
        let spacing = lineNS.substring(with: m.range(at: 3))
        let next: String
        if let last = bullet.last, last == "." || last == ")", let n = Int(bullet.dropLast()) {
            next = "\(n + 1)\(last)"
        } else {
            next = bullet
        }
        let task = m.range(at: 4).location != NSNotFound ? "[ ] " : ""
        let insertion = "\n" + indent + next + spacing + task
        return TextEdit(range: selection, replacement: insertion,
                        selection: NSRange(location: selection.location + (insertion as NSString).length, length: 0))
    }

    // MARK: Tab and Shift-Tab

    /// Indent or outdent the selected list lines. nil when the selection isn't made of list lines.
    public static func indent(in text: String, selection: NSRange, outdent: Bool) -> TextEdit? {
        let ns = text as NSString
        let block = ns.lineRange(for: selection)
        var lines: [(text: String, terminator: String, isList: Bool)] = []
        var changed = false

        ns.enumerateSubstrings(in: block, options: [.byLines, .substringNotRequired]) { _, lineRange, enclosing, _ in
            let content = ns.substring(with: lineRange)
            let terminator = ns.substring(with: NSRange(location: lineRange.upperBound, length: enclosing.upperBound - lineRange.upperBound))
            let isList = marker.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) != nil
            lines.append((content, terminator, isList))
        }
        guard !lines.isEmpty, lines.contains(where: \.isList), lines.allSatisfy({ $0.isList || $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }

        var result = ""
        var firstLineDelta = 0
        for (i, l) in lines.enumerated() {
            var t = l.text
            if l.isList {
                if outdent {
                    let removable = t.prefix { $0 == " " || $0 == "\t" }
                    let remove: Int
                    if removable.hasPrefix("\t") { remove = 1 } else { remove = min(step.count, removable.count) }
                    if remove > 0 { t.removeFirst(remove); changed = true; if i == 0 { firstLineDelta = -remove } }
                } else {
                    t = step + t
                    changed = true
                    if i == 0 { firstLineDelta = step.count }
                }
            }
            result += t + l.terminator
        }
        guard changed else { return nil }

        let newSelection: NSRange
        if selection.length == 0 {
            let column = selection.location - block.location
            let newColumn = max(0, column + firstLineDelta)
            newSelection = NSRange(location: block.location + newColumn, length: 0)
        } else {
            // Keep the whole edited block selected (without its trailing line break).
            let len = (result as NSString).length - ((result.hasSuffix("\n")) ? 1 : 0)
            newSelection = NSRange(location: block.location, length: len)
        }
        return TextEdit(range: block, replacement: result, selection: newSelection)
    }

    // MARK: Checkbox

    /// Toggle a task checkbox on the cursor's line; turns a bullet or plain line into a task.
    public static func toggleChecklist(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let line = line(at: selection.location, in: ns)
        let base = line.range.location
        guard let m = line.match else {
            // Plain line: make it a task after any indentation.
            let indentLength = line.text.prefix { $0 == " " || $0 == "\t" }.count
            let insertion = "- [ ] "
            let at = NSRange(location: base + indentLength, length: 0)
            let shift = (insertion as NSString).length
            let cursor = selection.location >= at.location ? selection.location + shift : selection.location
            return TextEdit(range: at, replacement: insertion, selection: NSRange(location: cursor, length: 0))
        }
        let box = m.range(at: 4)
        if box.location != NSNotFound {
            let open = NSRange(location: base + box.location + 1, length: 1)
            let current = ns.substring(with: open)
            let replacement = current == " " ? "x" : " "
            return TextEdit(range: open, replacement: replacement, selection: selection)
        }
        // List item without a box: add one after the marker.
        let afterMarker = m.range(at: 3).upperBound
        let at = NSRange(location: base + afterMarker, length: 0)
        let cursor = selection.location >= at.location ? selection.location + 4 : selection.location
        return TextEdit(range: at, replacement: "[ ] ", selection: NSRange(location: cursor, length: 0))
    }
}
