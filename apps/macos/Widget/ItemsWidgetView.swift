import OSWidgetKit
import SwiftUI
import WidgetKit

/// The widget body: a header with the unread count, then the newest items with the newest on top.
struct ItemsWidgetView: View {
    let entry: ItemsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "OS Widget")
                .font(.headline)
            Spacer(minLength: 4)
            if let unread = entry.snapshot?.unreadCount, unread > 0 {
                Text("\(unread) chưa đọc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let size = WidgetSize(family: family)
        if let snapshot = entry.snapshot {
            let items = Array(snapshot.items.prefix(size.rowLimit))
            if items.isEmpty {
                message("Chưa có mục")
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ItemRow(item: item, lines: index == 0 ? size.leadRowLines : size.rowLines)
                    }
                }
            }
        } else {
            message("Mở OS Widget để đồng bộ")
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
