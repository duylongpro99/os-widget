import OSWidgetKit
import SwiftUI
import WidgetKit

/// The newest items in medium and large sizes.
struct ItemsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.items, provider: ItemsProvider()) { entry in
            ItemsWidgetView(entry: entry)
        }
        .configurationDisplayName("OS Widget")
        .description("Các mục mới nhất")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

extension WidgetSize {
    /// The size for a widget family. Only medium and large are offered, so anything else is drawn as
    /// medium.
    init(family: WidgetFamily) {
        self = family == .systemLarge ? .large : .medium
    }
}

#Preview("Medium", as: .systemMedium) {
    ItemsWidget()
} timeline: {
    ItemsEntry(date: .now, snapshot: ItemsSamples.snapshot)
    ItemsEntry(date: .now, snapshot: .empty)
    ItemsEntry(date: .now, snapshot: nil)
}

#Preview("Large", as: .systemLarge) {
    ItemsWidget()
} timeline: {
    ItemsEntry(date: .now, snapshot: ItemsSamples.snapshot)
    ItemsEntry(date: .now, snapshot: .empty)
    ItemsEntry(date: .now, snapshot: nil)
}
