import Foundation
import Testing
@testable import OSWidgetKit

@MainActor
@Suite("Store apply")
struct StoreApplyTests {
    /// Six events around seq 100: two items created, one read, one created then deleted, one unread.
    private func page(since: Int64) -> [ServerEvent] {
        let a = TestData.item("a", createdSecondsAgo: 300)
        let b = TestData.item("b", createdSecondsAgo: 200)
        let c = TestData.item("c", createdSecondsAgo: 100)
        let all: [ServerEvent] = [
            TestData.created(96, a),
            TestData.created(97, b),
            TestData.event(98, .read, "a"),
            TestData.created(99, c),
            TestData.event(100, .deleted, "c"),
            TestData.event(101, .unread, "a"),
        ]
        return all.filter { $0.seq > since }
    }

    @Test func applyingTheSamePageTwiceEqualsApplyingItOnce() throws {
        let clock = TestClock()
        let once = ItemStore(location: nil, now: clock.function)
        once.apply(events: page(since: 95))

        let twice = ItemStore(location: nil, now: clock.function)
        twice.apply(events: page(since: 95))
        let secondNew = twice.apply(events: page(since: 95))

        #expect(StoreSnapshot(once) == StoreSnapshot(twice))
        #expect(Set(twice.items.map(\.id)).count == twice.items.count)
        #expect(secondNew.isEmpty)

        let fixture = try Fixture.events()
        let real = ItemStore(location: nil, now: clock.function)
        real.apply(events: fixture)
        let afterOnce = StoreSnapshot(real)
        real.apply(events: fixture)
        #expect(StoreSnapshot(real) == afterOnce)
        // Every real acceptance item was deleted on the server; three of them have also expired.
        #expect(real.visibleItems.isEmpty)
        #expect(real.items.count == 1)
        #expect(real.cursor == 394)
    }

    @Test func overlappingOlderPageChangesNothingAndCursorDoesNotGoBack() {
        let clock = TestClock()
        let store = ItemStore(location: nil, now: clock.function)
        store.apply(events: page(since: 95))
        let before = StoreSnapshot(store)
        #expect(store.cursor == 101)

        let new = store.apply(events: page(since: 101 - 5))
        #expect(new.isEmpty)
        #expect(StoreSnapshot(store) == before)
        #expect(store.cursor == 101)

        store.apply(events: [TestData.event(90, .read, "b")])
        #expect(store.cursor == 101)
    }

    @Test func newItemsAreOnlyUnreadUnexpiredAndNewToTheStore() {
        let clock = TestClock()
        let store = ItemStore(location: nil, now: clock.function)
        store.replaceAll(items: [TestData.item("known")], seq: 10)

        let new = store.apply(events: [
            TestData.created(11, TestData.item("known")),
            TestData.created(12, TestData.item("older", createdSecondsAgo: 500)),
            TestData.created(13, TestData.item("newer", createdSecondsAgo: 5)),
            TestData.created(14, TestData.item("readThenSeen")),
            TestData.event(15, .read, "readThenSeen"),
            TestData.created(16, TestData.item("expired", expiresIn: -1)),
            TestData.created(17, TestData.item("alreadyRead", read: true)),
            TestData.created(18, TestData.item("gone")),
            TestData.event(19, .deleted, "gone"),
        ])

        #expect(new.map(\.id) == ["newer", "older"])
        #expect(store.unreadCount == 3)
        #expect(store.visibleItems.map(\.id) == ["newer", "readThenSeen", "known", "alreadyRead", "older"])
    }

    @Test func createdWithoutItemIsIgnoredButTheCursorMoves() {
        let store = ItemStore(location: nil, now: TestClock().function)
        store.replaceAll(items: [], seq: 5)
        let new = store.apply(events: [TestData.created(6, nil, id: "purged")])
        #expect(new.isEmpty)
        #expect(store.items.isEmpty)
        #expect(store.cursor == 6)
    }

    @Test func eventsForUnknownItemsAndUnknownTypesAreIgnored() {
        let store = ItemStore(location: nil, now: TestClock().function)
        store.replaceAll(items: [TestData.item("a")], seq: 1)
        let before = store.items
        store.apply(events: [
            TestData.event(2, .read, "missing"),
            TestData.event(3, .deleted, "missing"),
            TestData.event(4, .other("item.pinned"), "a"),
        ])
        #expect(store.items == before)
        #expect(store.cursor == 4)
    }

    @Test func reconcileDropsItemsMissingOnTheServerAndTakesTheLargerCursor() {
        let clock = TestClock()
        let store = ItemStore(location: nil, now: clock.function)
        store.apply(events: [
            TestData.created(40, TestData.item("stays")),
            TestData.created(41, TestData.item("purged")),
        ])
        #expect(store.lastFullSyncAt == nil)

        var serverStays = TestData.item("stays")
        serverStays.readAt = TestData.now
        store.replaceAll(items: [serverStays, TestData.item("fresh")], seq: 30)
        #expect(store.items.map(\.id).sorted() == ["fresh", "stays"])
        #expect(store.item(id: "stays")?.isRead == true)
        #expect(store.cursor == 41)
        #expect(store.lastFullSyncAt == clock.now)

        store.replaceAll(items: [serverStays], seq: 55)
        #expect(store.cursor == 55)
        #expect(store.items.map(\.id) == ["stays"])
    }

    @Test func firstReplaceAllSetsTheCursor() {
        let store = ItemStore(location: nil, now: TestClock().function)
        #expect(store.cursor == nil)
        store.replaceAll(items: [], seq: 392)
        #expect(store.cursor == 392)
    }

    @Test func expiredItemsAreHiddenAndDroppedFromTheFile() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        store.replaceAll(items: [
            TestData.item("soon", expiresIn: 30),
            TestData.item("later", expiresIn: 7200),
            TestData.item("forever", expiresIn: nil),
        ], seq: 1)
        #expect(store.visibleItems.count == 3)

        clock.advance(by: 60)
        #expect(store.visibleItems.map(\.id).sorted() == ["forever", "later"])
        #expect(store.unreadCount == 2)

        store.setQuietMode(true)
        let reloaded = ItemStore(location: dir.location, now: clock.function)
        #expect(reloaded.items.map(\.id).sorted() == ["forever", "later"])
        let raw = try String(contentsOf: dir.storeFile, encoding: .utf8)
        #expect(!raw.contains("\"soon\""))
    }

    @Test func savedStateReloadsUnchanged() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        let fixture = try Fixture.items()
        store.replaceAll(items: fixture.items, seq: fixture.seq)
        store.apply(events: [TestData.created(400, TestData.item("x")), TestData.created(401, TestData.item("y"))])
        store.markRead("x")
        store.delete("y")
        store.setPopup(kind: "vocab", enabled: false)
        store.setQuietMode(true)
        store.announce([TestData.item("x")])

        let reloaded = ItemStore(location: dir.location, now: clock.function)
        #expect(StoreSnapshot(reloaded) == StoreSnapshot(store))
        #expect(reloaded.cursor == 401)
        #expect(reloaded.queue.count == 2)
        #expect(reloaded.popupSettings == PopupSettings(disabledKinds: ["vocab"], quietMode: true))
        #expect(reloaded.announcement == nil)
    }

    @Test func missingFileStartsEmpty() {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let store = ItemStore(location: dir.location, now: TestClock().function)
        #expect(store.items.isEmpty && store.cursor == nil && store.queue.isEmpty)
        #expect(store.popupSettings == .default)
        #expect(store.popupSettings.isEnabled(kind: "vocab") && !store.popupSettings.quietMode)
    }

    @Test func corruptFileStartsEmptyWithNoCursor() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        store.replaceAll(items: [TestData.item("a")], seq: 9)
        try Data("{\"version\": 1, \"items\": [".utf8).write(to: dir.storeFile)

        let reloaded = ItemStore(location: dir.location, now: clock.function)
        #expect(reloaded.items.isEmpty)
        #expect(reloaded.cursor == nil)
        #expect(reloaded.queue.isEmpty)
        #expect(reloaded.lastFullSyncAt == nil)
    }

    @Test func announcementsCountUpNewestFirstAndSkipEmptyLists() {
        let store = ItemStore(location: nil, now: TestClock().function)
        store.announce([])
        #expect(store.announcement == nil)

        store.announce([TestData.item("old", createdSecondsAgo: 90), TestData.item("new", createdSecondsAgo: 9)])
        #expect(store.announcement?.serial == 1)
        #expect(store.announcement?.items.map(\.id) == ["new", "old"])

        store.announce([TestData.item("old", createdSecondsAgo: 90), TestData.item("new", createdSecondsAgo: 9)])
        #expect(store.announcement?.serial == 2)
        store.announce([])
        #expect(store.announcement?.serial == 2)
    }

    @Test func idsAreKeptExactlyAsTheServerSentThem() {
        let store = ItemStore(location: nil, now: TestClock().function)
        store.apply(events: [TestData.created(1, TestData.item("AbC-123"))])
        store.markRead("AbC-123")
        #expect(store.item(id: "abc-123") == nil)
        #expect(store.queue.map(\.itemId) == ["AbC-123"])
    }
}
