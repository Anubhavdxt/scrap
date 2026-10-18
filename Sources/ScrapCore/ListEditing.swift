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
    public static func returnKey(in text: String, selection: NSRange, continueLists: Bool = true, keepIndent: Bool = true) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let line = line(at: selection.location, in: ns)
        guard continueLists, let m = line.match else {
            return keepIndent ? indentOnly(line, caret: selection.location) : nil
        }
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
        var numbered: (value: Int, delimiter: Character)?
        if let last = bullet.last, last == "." || last == ")", let n = Int(bullet.dropLast()) {
            next = "\(n + 1)\(last)"
            numbered = (n, last)
        } else {
            next = bullet
        }
        let task = m.range(at: 4).location != NSNotFound ? "[ ] " : ""
        let insertion = "\n" + indent + next + spacing + task
        let caret = NSRange(location: selection.location + (insertion as NSString).length, length: 0)

        // Inserting into the middle of a numbered list shifts the numbers of the items below.
        if let numbered, let shifted = renumberedTail(after: line, indent: indent, firstNumber: numbered.value + 2,
                                                      delimiter: numbered.delimiter, in: ns) {
            let remainder = ns.substring(with: NSRange(location: selection.location, length: line.range.upperBound - selection.location))
            let range = NSRange(location: selection.location, length: shifted.end - selection.location)
            return TextEdit(range: range, replacement: insertion + remainder + shifted.text, selection: caret)
        }
        return TextEdit(range: selection, replacement: insertion, selection: caret)
    }

    /// The lines below `line` with their numbers rewritten to count on from `firstNumber`, up to the end of the list.
    /// Same-indent items with the same delimiter are renumbered; deeper nested items are passed over; anything else
    /// (a blank line, plain text, a shallower item) ends the list. nil if nothing needs to change.
    private static func renumberedTail(after line: Line, indent: String, firstNumber: Int, delimiter: Character,
                                       in ns: NSString) -> (text: String, end: Int)? {
        var out = ""
        var cursor = line.range.upperBound   // index of the line break (or the end of the text)
        var end = cursor
        var expected = firstNumber
        var changed = false

        while cursor < ns.length {
            let next = self.line(at: cursor + 1, in: ns)
            guard next.range.location == cursor + 1, let nm = next.match else { break }
            let nextNS = next.text as NSString
            let nextIndent = nextNS.substring(with: nm.range(at: 1))
            var text = next.text
            if nextIndent == indent {
                let marker = nextNS.substring(with: nm.range(at: 2))
                guard marker.last == delimiter, Int(marker.dropLast()) != nil else { break }
                let renumbered = "\(expected)\(delimiter)"
                if renumbered != marker { changed = true }
                text = nextNS.replacingCharacters(in: nm.range(at: 2), with: renumbered)
                expected += 1
            } else if nextIndent.count < indent.count {
                break
            }
            out += "\n" + text
            cursor = next.range.upperBound
            end = cursor
        }
        return changed ? (out, end) : nil
    }

    /// Return on a plain line that starts with spaces or tabs: start the next line at the same indentation.
    /// On a line that is only indentation, clear it instead (the way out of an indented block).
    private static func indentOnly(_ line: Line, caret: Int) -> TextEdit? {
        let column = caret - line.range.location
        let indent = String(line.text.prefix { $0 == " " || $0 == "\t" })
        let indentLength = (indent as NSString).length
        guard indentLength > 0, column >= indentLength else { return nil }
        if line.text.trimmingCharacters(in: .whitespaces).isEmpty {
            return TextEdit(range: line.range, replacement: "", selection: NSRange(location: line.range.location, length: 0))
        }
        let insertion = "\n" + indent
        return TextEdit(range: NSRange(location: caret, length: 0), replacement: insertion,
                        selection: NSRange(location: caret + (insertion as NSString).length, length: 0))
    }

    // MARK: Backspace

    /// Backspace right after a bullet or task marker removes the marker (a task becomes a plain bullet first), as a
    /// single step: the marker is drawn as one icon, so deleting it character by character would be invisible.
    public static func backspace(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0 else { return nil }
        let ns = text as NSString
        let line = line(at: selection.location, in: ns)
        guard let m = line.match, selection.location == line.range.location + m.range.length else { return nil }
        let lineNS = line.text as NSString
        let bullet = lineNS.substring(with: m.range(at: 2))
        let box = m.range(at: 4)
        let base = line.range.location
        let range: NSRange
        if box.location != NSNotFound {
            range = NSRange(location: base + box.location, length: box.length)             // task -> plain bullet
        } else if "-*+".contains(bullet) {
            range = NSRange(location: base + m.range(at: 2).location, length: m.range.length - m.range(at: 1).length) // bullet -> text
        } else {
            return nil                                                                    // numbers delete normally
        }
        return TextEdit(range: range, replacement: "", selection: NSRange(location: selection.location - range.length, length: 0))
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

    /// Turns the cursor's line into a task (adds `- [ ] `), or back into a plain item if it already is one.
    public static func toggleTask(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let line = line(at: selection.location, in: ns)
        let base = line.range.location
        guard let m = line.match else {
            let indentLength = (String(line.text.prefix { $0 == " " || $0 == "\t" }) as NSString).length
            return insert("- [ ] ", at: base + indentLength, selection: selection)
        }
        let box = m.range(at: 4)
        if box.location != NSNotFound {
            let range = NSRange(location: base + box.location, length: box.length)
            let cursor = selection.location > range.location ? max(range.location, selection.location - range.length) : selection.location
            return TextEdit(range: range, replacement: "", selection: NSRange(location: cursor, length: 0))
        }
        return insert("[ ] ", at: base + m.range(at: 3).upperBound, selection: selection)
    }

    private static func insert(_ s: String, at location: Int, selection: NSRange) -> TextEdit {
        let shift = (s as NSString).length
        let cursor = selection.location >= location ? selection.location + shift : selection.location
        return TextEdit(range: NSRange(location: location, length: 0), replacement: s, selection: NSRange(location: cursor, length: 0))
    }
}
