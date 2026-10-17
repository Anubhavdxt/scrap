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
    static let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
}

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme

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
        private let baseFont = EditorFont.font

        var focusObserver: NSObjectProtocol?

        init(_ parent: EditorView) { self.parent = parent }

        deinit { focusObserver.map(NotificationCenter.default.removeObserver) }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            highlight(tv)
        }

        func apply(_ theme: Theme, to tv: NSTextView, force: Bool) {
            guard force || appliedTheme != theme.id else { return }
            appliedTheme = theme.id
            tv.drawsBackground = true
            tv.backgroundColor = NSColor(hex: theme.background)
            tv.insertionPointColor = NSColor(hex: theme.accent)
            tv.selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.accent, alpha: 0.3)]
            tv.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
            highlight(tv)
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
