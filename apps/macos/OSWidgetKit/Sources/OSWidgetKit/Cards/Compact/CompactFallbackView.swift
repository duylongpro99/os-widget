import SwiftUI

/// An item whose kind has no compact view, or whose body does not match its kind: title and summary.
struct CompactFallbackView: View {
    let item: Item
    let lines: Int

    var body: some View {
        CompactCardLayout(item: item, detail: CompactCardView.detail(for: item), lines: lines)
    }
}
