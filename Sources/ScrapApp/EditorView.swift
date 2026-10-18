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

enum EditorFont {
    static let defaultSize: Double = 14
    static let sizeRange: ClosedRange<Double> = 9...32

    /// `family` empty means the system monospaced font.
    static func font(size: Double, family: String) -> NSFont {
        let pt = CGFloat(min(max(size, sizeRange.lowerBound), sizeRange.upperBound))
        if !family.isEmpty, let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: pt) { return font }
        return .monospacedSystemFont(ofSize: pt, weight: .regular)
    }

    /// The font from the saved settings (used to size the window in columns and rows).
    static var current: NSFont {
        let d = UserDefaults.standard
        return font(size: d.object(forKey: "fontSize") as? Double ?? defaultSize, family: d.string(forKey: "fontFamily") ?? "")
    }

    /// Installed monospaced font families.
    static let families: [String] = NSFontManager.shared.availableFontFamilies.filter {
        NSFontManager.shared.font(withFamily: $0, traits: [], weight: 5, size: 12)?.isFixedPitch == true
    }
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    let fontSize: Double
    let fontFamily: String
    let wrap: Bool

    private static let maxHighlightLength = 300_000

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
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

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        private var appliedTheme: String?
        private var baseFont: NSFont { EditorFont.font(size: parent.fontSize, family: parent.fontFamily) }

        var focusObserver: NSObjectProtocol?
        var commandObserver: NSObjectProtocol?

        init(_ parent: EditorView) { self.parent = parent }

        deinit {
            focusObserver.map(NotificationCenter.default.removeObserver)
            commandObserver.map(NotificationCenter.default.removeObserver)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
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
            case #selector(NSResponder.insertTab(_:)):
                return apply(ListEditing.indent(in: text, selection: selection, outdent: false), to: textView)
            case #selector(NSResponder.insertBacktab(_:)):
                return apply(ListEditing.indent(in: text, selection: selection, outdent: true), to: textView)
            default:
                return false
            }
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
            let key = "\(theme.id)|\(parent.fontSize)|\(parent.fontFamily)|\(parent.wrap)"
            guard force || appliedTheme != key else { return }
            appliedTheme = key
            setWrap(parent.wrap, in: tv)
            tv.drawsBackground = true
            tv.backgroundColor = NSColor(hex: theme.background)
            tv.insertionPointColor = NSColor(hex: theme.accent)
            tv.selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.accent, alpha: 0.3)]
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

        func highlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let theme = parent.theme
            let base = [NSAttributedString.Key.font: baseFont, .foregroundColor: NSColor(hex: theme.color(.base))]
            tv.typingAttributes = base
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(base, range: full)
            if storage.length <= EditorView.maxHighlightLength {
                for span in MarkdownHighlighter.spans(in: storage.string) {
                    var attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor(hex: theme.color(span.token))]
                    let italic = span.italic || theme.italic.contains(span.token)
                    if span.bold || italic {
                        var traits: NSFontDescriptor.SymbolicTraits = []
                        if span.bold { traits.insert(.bold) }
                        if italic { traits.insert(.italic) }
                        attrs[.font] = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(traits), size: baseFont.pointSize) ?? baseFont
                    }
                    storage.addAttributes(attrs, range: span.range)
                }
            }
            storage.endEditing()
        }
    }
}
