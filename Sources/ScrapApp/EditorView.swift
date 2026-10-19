import AppKit
import ScrapCore
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    let fontSize: Double
    let fontFamily: String
    let wrap: Bool
    var colorHighlights = true
    var markers = "hide"
    /// False shows the file as plain text: one monospaced font, every marker visible, nothing drawn.
    var rendered = true
    /// Selected text is highlighted in this colour (the current pad's).
    var selectionColor: NSColor? = nil
    /// Receives the selection so the footer can count the selected text.
    var selection: Binding<NSRange>? = nil
    /// The user's own smart bullets, as stored in Settings (JSON).
    var customBullets = ""

    private static let maxHighlightLength = 300_000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 stack with our layout manager, which draws the task icons and bullets.
        let storage = NSTextStorage()
        let layout = ScrapLayoutManager()
        layout.delegate = context.coordinator
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = ScrapTextView(frame: .zero, textContainer: container)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        tv.delegate = context.coordinator
        tv.onToggleTask = { [weak tv, weak coordinator = context.coordinator] index in
            guard let tv else { return }
            coordinator?.toggleTask(at: index, in: tv)
        }
        tv.onToggleSmartBullet = { [weak tv, weak coordinator = context.coordinator] index in
            guard let tv else { return }
            coordinator?.toggleSmartBullet(at: index, in: tv)
        }
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 12, height: 12)
        tv.string = text
        context.coordinator.apply(theme, to: tv, force: true)
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(forName: .focusEditor, object: nil, queue: .main) { [weak tv] _ in
            tv.flatMap { $0.window?.makeFirstResponder($0) }
        }
        context.coordinator.symbolObserver = NotificationCenter.default.addObserver(forName: .insertSymbol, object: nil, queue: .main) { [weak tv, weak coordinator = context.coordinator] note in
            // The picker is a window of its own, so the editor isn't the key window while it is open.
            guard let tv, tv.window != nil, let request = note.object as? SymbolRequest else { return }
            coordinator?.insert(request.kind, in: tv)
        }
        context.coordinator.revealObserver = NotificationCenter.default.addObserver(forName: .revealRange, object: nil, queue: .main) { [weak tv] note in
            guard let location = note.userInfo?["location"] as? Int, let length = note.userInfo?["length"] as? Int else { return }
            // The pad's text arrives with the next SwiftUI update, so wait for it.
            DispatchQueue.main.async { DispatchQueue.main.async {
                guard let tv else { return }
                let total = (tv.string as NSString).length
                guard location <= total else { return }
                let range = NSRange(location: location, length: min(length, total - location))
                tv.window?.makeFirstResponder(tv)
                tv.setSelectedRange(range)
                tv.scrollRangeToVisible(range)
                tv.showFindIndicator(for: range)
            } }
        }
        context.coordinator.commandObserver = NotificationCenter.default.addObserver(forName: .editorCommand, object: nil, queue: .main) { [weak tv, weak coordinator = context.coordinator] note in
            guard let tv, tv.window?.isKeyWindow == true, let raw = note.userInfo?["command"] as? String,
                  let command = EditorCommand(rawValue: raw) else { return }
            coordinator?.run(command, in: tv)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! NSTextView
        context.coordinator.parent = self
        if tv.string != text {
            let selection = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            context.coordinator.highlight(tv)
        }
        context.coordinator.apply(theme, to: tv, force: false)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: EditorView
        private var appliedTheme: String?
        /// The prose font; raw mode is monospaced.
        private var baseFont: NSFont {
            parent.rendered ? EditorFont.font(size: parent.fontSize, family: parent.fontFamily)
                            : EditorFont.codeFont(size: parent.fontSize, family: parent.fontFamily)
        }

        var focusObserver: NSObjectProtocol?
        var revealObserver: NSObjectProtocol?
        var commandObserver: NSObjectProtocol?
        var symbolObserver: NSObjectProtocol?

        init(_ parent: EditorView) { self.parent = parent }

        /// Settles the layout of what is on screen and redraws it, after the styling changed line heights.
        func refreshDisplay(_ tv: NSTextView) {
            if let layout = tv.layoutManager, let container = tv.textContainer { layout.ensureLayout(forBoundingRect: tv.visibleRect, in: container) }
            tv.needsDisplay = true
        }

        /// Lines can move after they were first drawn (a hidden code fence collapses, a revealed one grows, layout
        /// finishes in the background). Redraw once layout settles so no line is left drawn at its old position.
        func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
            guard layoutFinishedFlag, let view = textContainer?.textView else { return }
            DispatchQueue.main.async { view.needsDisplay = true }
        }

        deinit {
            focusObserver.map(NotificationCenter.default.removeObserver)
            revealObserver.map(NotificationCenter.default.removeObserver)
            commandObserver.map(NotificationCenter.default.removeObserver)
            symbolObserver.map(NotificationCenter.default.removeObserver)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv, edited: true)
        }

        /// List editing: Return continues a list, Tab and Shift-Tab indent list items.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false } // let input methods finish composing
            let text = textView.string, selection = textView.selectedRange()
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let d = UserDefaults.standard
                let edit = ListEditing.returnKey(in: text, selection: selection,
                                                 continueLists: d.object(forKey: "autoList") as? Bool ?? true,
                                                 keepIndent: d.object(forKey: "keepIndent") as? Bool ?? true)
                return apply(edit, to: textView)
            case #selector(NSResponder.deleteBackward(_:)):
                return apply(ListEditing.backspace(in: text, selection: selection), to: textView)
            case #selector(NSResponder.insertTab(_:)):
                return apply(ListEditing.indent(in: text, selection: selection, outdent: false), to: textView)
            case #selector(NSResponder.insertBacktab(_:)):
                return apply(ListEditing.indent(in: text, selection: selection, outdent: true), to: textView)
            default:
                return false
            }
        }

        /// Clicking a task icon checks or unchecks it without moving the caret.
        func toggleTask(at index: Int, in tv: NSTextView) {
            let saved = tv.selectedRange()
            if apply(ListEditing.toggleChecklist(in: tv.string, selection: NSRange(location: index, length: 0)), to: tv) {
                tv.setSelectedRange(saved)
            }
        }

        /// Clicking a smart bullet flips it without moving the caret.
        func toggleSmartBullet(at index: Int, in tv: NSTextView) {
            let saved = tv.selectedRange()
            if apply(SmartBullets.toggle(in: tv.string, at: index), to: tv) { tv.setSelectedRange(saved) }
        }

        /// Puts something chosen in the symbol picker into the text.
        func insert(_ kind: SymbolItem.Kind, in tv: NSTextView) {
            let text = tv.string, selection = tv.selectedRange()
            let edit: TextEdit?
            switch kind {
            case .smartBullet(let pair): edit = ListEditing.insertSmartBullet(pair, in: text, selection: selection)
            case .markdownTask:
                // "Make this a task" never un-makes one.
                let toggled = ListEditing.toggleTask(in: text, selection: selection)
                edit = toggled?.replacement.isEmpty == true ? nil : toggled
            case .divider(let line): edit = Formatting.insertDividerLine(line, in: text, selection: selection)
            case .text(let string): edit = Formatting.insertText(string, in: text, selection: selection)
            }
            apply(edit, to: tv)
        }

        /// Runs a formatting or list command on the current selection.
        func run(_ command: EditorCommand, in tv: NSTextView) {
            let text = tv.string, selection = tv.selectedRange()
            let edit: TextEdit?
            switch command {
            case .bold: edit = Formatting.toggle(.bold, in: text, selection: selection)
            case .italic: edit = Formatting.toggle(.italic, in: text, selection: selection)
            case .strikethrough: edit = Formatting.toggle(.strikethrough, in: text, selection: selection)
            case .code: edit = Formatting.toggle(.code, in: text, selection: selection)
            case .divider: edit = Formatting.insertDivider(in: text, selection: selection)
            case .task: edit = ListEditing.toggleTask(in: text, selection: selection)
            case .checkbox: edit = ListEditing.toggleChecklist(in: text, selection: selection)
            }
            apply(edit, to: tv)
        }

        /// Applies an edit as one undoable change. Returns whether there was an edit.
        @discardableResult
        func apply(_ edit: TextEdit?, to tv: NSTextView) -> Bool {
            guard let edit, tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return false }
            tv.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            tv.didChangeText()
            tv.setSelectedRange(edit.selection)
            return true
        }

        func apply(_ theme: Theme, to tv: NSTextView, force: Bool) {
            let key = "\(theme.id)|\(parent.fontSize)|\(parent.fontFamily)|\(parent.wrap)|\(parent.colorHighlights)|\(parent.markers)|\(parent.rendered)|\(parent.selectionColor?.description ?? "")|\(parent.customBullets)"
            guard force || appliedTheme != key else { return }
            appliedTheme = key
            setWrap(parent.wrap, in: tv)
            tv.drawsBackground = true
            tv.backgroundColor = NSColor(hex: theme.background)
            tv.insertionPointColor = NSColor(hex: theme.accent)
            tv.selectedTextAttributes = [.backgroundColor: (parent.selectionColor ?? NSColor(hex: theme.accent)).withAlphaComponent(0.35)]
            tv.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
            highlight(tv)
        }

        /// Soft-wrap to the view width, or scroll horizontally.
        private func setWrap(_ on: Bool, in tv: NSTextView) {
            guard let scroll = tv.enclosingScrollView, let container = tv.textContainer else { return }
            scroll.hasHorizontalScroller = !on
            tv.isHorizontallyResizable = !on
            container.widthTracksTextView = on
            if on {
                tv.autoresizingMask = [.width]
                container.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
                tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: tv.frame.height))
            } else {
                container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            }
            tv.needsLayout = true
        }

        // MARK: Styling

        private var spans: [Span] = []
        private var spansText: String?
        private var spansBullets: String?
        private var revealed = NSRange(location: 0, length: 0)

        private var style: MarkdownStyle {
            MarkdownStyle(theme: parent.theme, baseFont: baseFont, codeFont: EditorFont.codeFont(size: parent.fontSize, family: parent.fontFamily),
                          colorHighlights: parent.colorHighlights, markers: MarkerMode(rawValue: parent.markers) ?? .hide,
                          raw: !parent.rendered)
        }

        /// Re-styles the whole text (after an edit or a settings change).
        func highlight(_ tv: NSTextView, edited: Bool = false) {
            guard let storage = tv.textStorage else { return }
            let style = self.style
            if let lm = tv.layoutManager as? ScrapLayoutManager {
                lm.accent = style.accent
                lm.textColor = style.base
                lm.iconSize = (style.baseFont.pointSize * 0.95).rounded()
                lm.iconAdvance = style.iconAdvance
            }
            let full = NSRange(location: 0, length: storage.length)
            tv.typingAttributes = style.baseAttributes
            // The user's own smart bullets decide what counts as a bullet, so set them before reading the text.
            if spansBullets != parent.customBullets {
                SmartBullets.custom = CustomBullets.decode(parent.customBullets)
                spansBullets = parent.customBullets
                spansText = nil
            }
            if storage.length <= EditorView.maxHighlightLength {
                if spansText != storage.string {
                    let previous = (text: spansText, spans: spans)
                    spans = MarkdownHighlighter.spans(in: storage.string)
                    spansText = storage.string
                    // After a keystroke, restyle only what the edit touched.
                    if edited, let oldText = previous.text, (oldText as NSString).length <= EditorView.maxHighlightLength {
                        let oldRevealed = revealed
                        revealed = paragraphs(of: tv.selectedRange(), in: storage)
                        MarkdownStyler.applyEdit(oldText: oldText, oldSpans: previous.spans, newSpans: spans, oldReveal: oldRevealed,
                                                 newReveal: revealed, to: storage, style: style)
                        refreshDisplay(tv)
                        return
                    }
                }
            } else {
                spans = []
                spansText = nil
            }
            revealed = paragraphs(of: tv.selectedRange(), in: storage)
            MarkdownStyler.apply(spans, to: storage, range: full, reveal: revealed, style: style)
            refreshDisplay(tv)
        }

        /// Moving the caret to another paragraph shows that paragraph's Markdown syntax and hides the previous one's.
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, let storage = tv.textStorage else { return }
            if let binding = parent.selection {
                let range = tv.selectedRange()
                // Deferred: this can fire while SwiftUI is updating views.
                DispatchQueue.main.async { if binding.wrappedValue != range { binding.wrappedValue = range } }
            }
            guard parent.rendered, !spans.isEmpty, spansText == storage.string else { return }
            let now = paragraphs(of: tv.selectedRange(), in: storage)
            guard now != revealed else { return }
            let before = revealed
            revealed = now
            let style = self.style
            for range in [before, now] where range.upperBound <= storage.length {
                MarkdownStyler.apply(spans, to: storage, range: range, reveal: now, style: style)
            }
            refreshDisplay(tv)
        }

        private func paragraphs(of selection: NSRange, in storage: NSTextStorage) -> NSRange {
            let ns = storage.string as NSString
            let location = min(selection.location, ns.length)
            return ns.paragraphRange(for: NSRange(location: location, length: min(selection.length, ns.length - location)))
        }
    }
}
