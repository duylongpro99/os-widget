import SwiftUI

/// A `generic` item in compact form: the title and the text of its first heading or text block. Images,
/// code, lists and other blocks are left out.
struct CompactGenericView: View {
    let item: Item
    let lines: Int

    var body: some View {
        CompactCardLayout(item: item, detail: CompactCardView.detail(for: item), lines: lines)
    }
}
