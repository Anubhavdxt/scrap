import AppKit

/// Popover size measured in editor character cells, like a terminal's columns and rows.
enum WindowSize {
    static let defaultCols = 64
    static let defaultRows = 16
    static let colsRange = 30...200
    static let rowsRange = 8...60

    // Chrome around the text view: top bar, status line, two dividers and the text view's insets.
    private static let topBar: CGFloat = 34
    private static let statusLine: CGFloat = 24
    private static let dividers: CGFloat = 2
    private static let textInset: CGFloat = 12 // each side
    private static let linePadding: CGFloat = 5 // NSTextContainer lineFragmentPadding, each side

    static func contentSize(cols: Int, rows: Int) -> CGSize {
        let font = EditorFont.current
        let cell = EditorFont.cellWidth(font)
        let line = NSLayoutManager().defaultLineHeight(for: font)
        var size = CGSize(
            width: ceil(CGFloat(cols) * cell + 2 * (textInset + linePadding)),
            height: ceil(CGFloat(rows) * line + 2 * textInset + topBar + statusLine + dividers)
        )
        if let screen = NSScreen.main?.visibleFrame {
            size.width = min(size.width, screen.width * 0.95)
            size.height = min(size.height, screen.height * 0.9)
        }
        return size
    }

    static func current(_ defaults: UserDefaults = .standard) -> CGSize {
        let cols = defaults.object(forKey: "windowCols") as? Int ?? defaultCols
        let rows = defaults.object(forKey: "windowRows") as? Int ?? defaultRows
        return contentSize(cols: min(max(cols, colsRange.lowerBound), colsRange.upperBound),
                           rows: min(max(rows, rowsRange.lowerBound), rowsRange.upperBound))
    }
}
