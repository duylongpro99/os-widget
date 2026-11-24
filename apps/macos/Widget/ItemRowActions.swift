import OSWidgetKit
import SwiftUI

/// The read and delete buttons at the end of a row. The check mark shows only while the item is unread;
/// the trash can always shows. Each button runs its intent in the widget extension.
struct ItemRowActions: View {
    let item: Item

    var body: some View {
        HStack(spacing: 4) {
            if !item.isRead {
                Button(intent: MarkItemReadIntent(itemID: item.id)) {
                    Image(systemName: "checkmark.circle")
                }
                .accessibilityLabel(Text("Đánh dấu đã đọc"))
            }
            Button(intent: DeleteItemIntent(itemID: item.id)) {
                Image(systemName: "trash")
            }
            .accessibilityLabel(Text("Xoá"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .imageScale(.small)
    }
}
