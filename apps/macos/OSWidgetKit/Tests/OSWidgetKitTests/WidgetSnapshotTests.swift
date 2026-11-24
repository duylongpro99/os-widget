import Foundation
import Testing
@testable import OSWidgetKit

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    private let now = TestData.now

    /// Eight unread items, `i0` newest, each expiring an hour after it was created.
    private func eight() -> [Item] {
        (0..<8).map { (index: Int) -> Item in
            let age = TimeInterval(10 * (index + 1))
            let expiresIn = TimeInterval(3600 - 10 * index)
            return TestData.item("i\(index)", createdSecondsAgo: age, expiresIn: expiresIn)
        }
    }

    private func action(_ id: String, _ operation: WidgetAction.Operation, secondsAgo: TimeInterval = 5) -> WidgetAction {
        WidgetAction(itemId: id, operation: operation, createdAt: now.addingTimeInterval(-secondsAgo))
    }

    @Test func newestFirstCutAtTheLimitKeepingReadItems() {
        var items = eight().shuffled()
        let position = items.firstIndex { $0.id == "i1" }!
        items[position].readAt = now

        let snapshot = WidgetSnapshot.make(items: items, pending: [], now: now)
        #expect(snapshot.items.map(\.id) == ["i0", "i1", "i2", "i3", "i4", "i5"])
        #expect(snapshot.items[1].isRead)
        #expect(WidgetSnapshot.make(items: items, pending: [], now: now, limit: 3).items.map(\.id) == ["i0", "i1", "i2"])
    }

    @Test func sameCreationTimeOrdersByIdDescending() {
        let items = [TestData.item("a", createdSecondsAgo: 10), TestData.item("c", createdSecondsAgo: 10), TestData.item("b", createdSecondsAgo: 10)]
        #expect(WidgetSnapshot.make(items: items, pending: [], now: now).items.map(\.id) == ["c", "b", "a"])
    }

    @Test func dropsDeletedAndExpiredAndCountsUnreadBeyondTheLimit() {
        let items = eight() + [
            TestData.item("gone", createdSecondsAgo: 1, deleted: true),
            TestData.item("stale", createdSecondsAgo: 2, expiresIn: -1),
            TestData.item("old-read", createdSecondsAgo: 500, expiresIn: 60, read: true),
        ]
        let snapshot = WidgetSnapshot.make(items: items, pending: [], now: now)
        #expect(!snapshot.items.contains { $0.id == "gone" || $0.id == "stale" })
        #expect(snapshot.unreadCount == 8)
        // The earliest expiry among every visible item, including those past the limit.
        #expect(snapshot.nextExpiry == now.addingTimeInterval(60))
    }

    @Test func noExpiryWhenNoVisibleItemExpires() {
        let snapshot = WidgetSnapshot.make(items: [TestData.item("a", expiresIn: nil)], pending: [], now: now)
        #expect(snapshot.nextExpiry == nil)
        #expect(WidgetSnapshot.make(items: [], pending: [], now: now) == .empty)
    }

    @Test func pendingActionsAreLaidOverTheItems() {
        let pending = [action("i0", .delete), action("i1", .markRead, secondsAgo: 3), action("unknown", .delete), action("unknown", .markRead)]
        let snapshot = WidgetSnapshot.make(items: eight(), pending: pending, now: now)

        #expect(snapshot.items.map(\.id) == ["i1", "i2", "i3", "i4", "i5", "i6"])
        #expect(snapshot.items[0].readAt == now.addingTimeInterval(-3))
        #expect(snapshot.unreadCount == 6)
    }

    @Test func pendingReadKeepsAnEarlierReadTime() {
        let read = TestData.item("a", read: true)
        let snapshot = WidgetSnapshot.make(items: [read], pending: [action("a", .markRead)], now: now)
        #expect(snapshot.items[0].readAt == read.readAt)
    }

    @Test func pendingReadThenDeleteHidesTheItem() {
        let snapshot = WidgetSnapshot.make(items: eight(), pending: [action("i0", .markRead, secondsAgo: 9), action("i0", .delete, secondsAgo: 4)], now: now)
        #expect(snapshot.items.first?.id == "i1")
        #expect(snapshot.unreadCount == 7)
    }

    @Test func equalAcrossTimeAndChangedOnlyByWhatTheWidgetShows() {
        let items = eight()
        let first = WidgetSnapshot.make(items: items, pending: [], now: now)
        #expect(WidgetSnapshot.make(items: items, pending: [], now: now.addingTimeInterval(600)) == first)

        var readInTopSix = items
        readInTopSix[3].readAt = now
        #expect(WidgetSnapshot.make(items: readInTopSix, pending: [], now: now) != first)

        // The seventh item is not shown: changing it, or removing it once it is read, leaves the
        // snapshot as it was.
        var readSeventh = items
        readSeventh[6].readAt = now
        let base = WidgetSnapshot.make(items: readSeventh, pending: [], now: now)
        var changedSeventh = readSeventh
        changedSeventh[6].title = "edited"
        changedSeventh[6].summary = "edited"
        #expect(WidgetSnapshot.make(items: changedSeventh, pending: [], now: now) == base)
        #expect(WidgetSnapshot.make(items: readSeventh, pending: [action("i6", .delete)], now: now) == base)

        // Reading an unread seventh item changes only the unread count, which the widget shows.
        let readOutside = WidgetSnapshot.make(items: items, pending: [action("i6", .markRead)], now: now)
        #expect(readOutside.items == first.items && readOutside.unreadCount == first.unreadCount - 1)
    }

    @Test func roundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot.make(items: eight(), pending: [action("i2", .markRead)], now: now)
        let data = try ServerJSON.makeEncoder().encode(snapshot)
        #expect(try ServerJSON.makeDecoder().decode(WidgetSnapshot.self, from: data) == snapshot)
    }
}
