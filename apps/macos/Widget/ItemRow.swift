import OSWidgetKit
import SwiftUI

/// One item in the widget: its compact card with the row's buttons at the end. Tapping the card itself
/// does nothing; only the buttons act.
struct ItemRow: View {
    let item: Item
    let lines: Int

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            CompactCardView(item: item, lines: lines)
            ItemRowActions(item: item)
        }
    }
}
