import OSWidgetKit
import SwiftUI

/// What the popup shows: the card of the newest item, a "+N" line when more items arrived, and a close
/// button. The card comes from `card` so the popup renders items the same way as the list.
struct PopupContentView<Card: View>: View {
    let item: Item
    let othersCount: Int
    let card: (Item) -> Card
    /// A click on the card outside its links.
    let onOpenItem: @MainActor () -> Void
    /// A click on a link inside the card; the URL has passed `URLPolicy` already.
    let onOpenLink: @MainActor (URL) -> Void
    let onShowList: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                card(item)
                    .onCardClick(tap: onOpenItem, link: onOpenLink)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng")
                .frame(width: PopupPanel.closeColumnWidth)
                .padding(.top, CardMetrics.padding)
            }
            if othersCount > 0 {
                Button("+\(othersCount) mục khác", action: onShowList)
                    .buttonStyle(.link)
                    .padding(.horizontal, CardMetrics.padding)
                    .padding(.bottom, CardMetrics.padding)
            }
        }
        .frame(width: PopupPanel.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
