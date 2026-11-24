import Foundation

/// Exactly what the widget shows: the newest visible items, the unread count and when the next shown
/// item expires.
///
/// It holds only data derived from the items and the pending widget actions, never the current time,
/// so two snapshots built from the same data compare equal and a changed snapshot means the widget
/// must be redrawn.
public struct WidgetSnapshot: Codable, Sendable, Hashable {
    /// The most items any widget size shows.
    public static let maxItems = 6

    /// Visible items, newest first, at most the `limit` given to `make`. Read items stay, dimmed by
    /// the view.
    public let items: [Item]
    /// Every visible unread item, not only the ones in `items`.
    public let unreadCount: Int
    /// The earliest expiry among the visible items, so the widget timeline can drop an item when it
    /// expires without the app asking for a reload.
    public let nextExpiry: Date?

    public init(items: [Item], unreadCount: Int, nextExpiry: Date?) {
        self.items = items
        self.unreadCount = unreadCount
        self.nextExpiry = nextExpiry
    }

    public static let empty = WidgetSnapshot(items: [], unreadCount: 0, nextExpiry: nil)

    /// Builds the snapshot from the stored items with the actions still waiting in the inbox laid over
    /// them: an item waiting for deletion is hidden and an item waiting to be read shows as read from
    /// the time of the tap. Actions for unknown items are ignored.
    public static func make(items: [Item], pending: [WidgetAction], now: Date, limit: Int = maxItems) -> WidgetSnapshot {
        var overlaid = items
        let index = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        for action in pending.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let position = index[action.itemId] else { continue }
            switch action.operation {
            case .markRead:
                if overlaid[position].readAt == nil { overlaid[position].readAt = action.createdAt }
            case .delete:
                if overlaid[position].deletedAt == nil { overlaid[position].deletedAt = action.createdAt }
            }
        }

        let visible = overlaid.filter { $0.isVisible(at: now) }.sorted(by: newestFirst)
        return WidgetSnapshot(
            items: Array(visible.prefix(max(limit, 0))),
            unreadCount: visible.count(where: { !$0.isRead }),
            nextExpiry: visible.compactMap(\.expiresAt).min()
        )
    }

    private static func newestFirst(_ a: Item, _ b: Item) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id > b.id
    }
}
