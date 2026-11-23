import OSWidgetKit
import SwiftUI

/// What the popup shows: the card of the newest item, a "+N" line when more items arrived, and a close
/// button. The card comes from `card` so the popup renders items the same way as the list.
struct PopupContentView<Card: View>: View {
    let item: Item
    let othersCount: Int
    let card: (Item) -> Card
    let onOpenItem: () -> Void
    let onShowList: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onOpenItem) {
                    card(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng")
            }
            if othersCount > 0 {
                Button("+\(othersCount) mục khác", action: onShowList)
                    .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(width: PopupPanel.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A plain card with the fields every item has: title, summary and source.
struct PopupPlainCard: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.headline)
                .lineLimit(2)
            Text(item.summary)
                .font(.subheadline)
                .lineLimit(4)
            Text(item.source)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
