import ScrapCore
import SwiftUI

/// The `*` picker: smart bullets, dividers, bullets, checkmarks, arrows, numbers, technical keys and symbols.
/// It opens as a popover below the `*` button, so it never covers the note. Choosing one puts it in the text at the cursor
/// and closes the picker.
struct SymbolPicker: View {
    /// The popover's content size.
    static let size = CGSize(width: 316, height: 360)

    @State private var hovered: String?
    /// Your own smart bullets, listed after the built-in ones.
    @AppStorage("customBullets") private var customBullets = ""

    /// Groups of wide items (a pair of bullets, a divider) get bigger cells than single characters.
    private func columns(for group: SymbolGroup) -> [GridItem] {
        let wide = group.name == "Smart Bullets" || group.name == "Dividers"
        return [GridItem(.adaptive(minimum: wide ? 56 : 34), spacing: 4)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(SymbolCatalog.groups(custom: CustomBullets.decode(customBullets))) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.name.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns(for: group), alignment: .leading, spacing: 4) {
                            ForEach(group.items) { item in cell(item) }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private func cell(_ item: SymbolItem) -> some View {
        Button { choose(item) } label: {
            Text(item.label)
                .font(.system(size: item.label.count > 3 ? 11 : 17))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovered == item.id ? Color.primary.opacity(0.12) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
        .help(item.title)
    }

    private func choose(_ item: SymbolItem) { Self.send(item) }

    /// Puts the item into the text and closes the picker.
    static func send(_ item: SymbolItem) {
        SymbolRequest(item.kind).post()
        NotificationCenter.default.post(name: .closeSymbols, object: nil)
    }
}
