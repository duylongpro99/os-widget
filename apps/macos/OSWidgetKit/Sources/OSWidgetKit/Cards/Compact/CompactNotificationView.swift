import SwiftUI

/// A `notification` item in compact form: the title and the first line of its text as plain text, or its
/// summary when it has no text.
struct CompactNotificationView: View {
    let item: Item
    let lines: Int

    var body: some View {
        CompactCardLayout(item: item, detail: CompactCardView.detail(for: item), lines: lines)
    }
}
