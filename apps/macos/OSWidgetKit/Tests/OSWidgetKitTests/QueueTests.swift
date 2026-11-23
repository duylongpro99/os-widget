import Foundation
import Testing
@testable import OSWidgetKit

@MainActor
@Suite("Queue")
struct QueueTests {
    private func store(with ids: [String] = ["a", "b"]) -> ItemStore {
        let store = ItemStore(location: nil, now: TestClock().function)
        store.replaceAll(items: ids.map { TestData.item($0) }, seq: 10)
        return store
    }

    @Test func userActionsApplyImmediately() {
        let store = store()
        store.markRead("a")
        #expect(store.item(id: "a")?.isRead == true)
        #expect(store.unreadCount == 1)
        store.delete("b")
        #expect(store.visibleItems.map(\.id) == ["a"])
        #expect(store.queue.map(\.operation) == [.read(true), .delete])
    }

    @Test func deleteWinsOverRead() {
        let store = store()
        store.markRead("a")
        store.delete("a")
        #expect(store.queue.map(\.operation) == [.delete])

        store.markRead("a")
        store.markUnread("a")
        store.delete("a")
        #expect(store.queue.count == 1)
        #expect(store.queue.first?.operation == .delete)
        #expect(store.item(id: "a")?.isDeleted == true)
    }

    @Test func deletedItemTakesNoActionsAfterTheDeleteWasSent() throws {
        let store = store()
        store.delete("a")
        let sent = try #require(store.queue.first)
        store.complete(sent, outcome: .done)
        #expect(store.queue.isEmpty)

        store.markRead("a")
        store.markUnread("a")
        store.delete("a")
        #expect(store.queue.isEmpty)
        #expect(store.item(id: "a")?.isDeleted == true)
    }

    @Test func readThenUnreadBecomeOneAction() {
        let store = store()
        store.markRead("a")
        store.markUnread("a")
        #expect(store.queue.map(\.operation) == [.read(false)])
        #expect(store.queue.map(\.itemId) == ["a"])
        #expect(store.item(id: "a")?.isRead == false)
    }

    @Test func pendingActionIsReappliedAfterServerUnread() {
        let store = store()
        store.markRead("a")
        store.apply(events: [TestData.event(11, .unread, "a")])
        #expect(store.item(id: "a")?.isRead == true)
        #expect(store.queue.count == 1)

        store.replaceAll(items: [TestData.item("a"), TestData.item("b")], seq: 12)
        #expect(store.item(id: "a")?.isRead == true)

        store.delete("b")
        store.apply(events: [TestData.created(13, TestData.item("b"))])
        #expect(store.item(id: "b")?.isDeleted == true)
    }

    @Test func actionsForUnknownItemsAreNotQueued() {
        let store = store()
        store.markRead("missing")
        store.delete("missing")
        #expect(store.queue.isEmpty)
    }

    @Test(arguments: [
        (200, QueueOutcome.done), (204, .done), (404, .done),
        (400, .rejected), (409, .rejected),
        (401, .stop), (403, .stop),
        (429, .retry), (500, .retry), (502, .retry), (503, .retry),
    ])
    func outcomeForStatus(status: Int, expected: QueueOutcome) {
        #expect(PendingAction.outcome(for: status) == expected)
    }

    @Test func networkErrorKeepsTheAction() {
        #expect(PendingAction.outcome(for: nil) == .retry)
        #expect(!QueueOutcome.retry.removesAction && !QueueOutcome.stop.removesAction)
        #expect(QueueOutcome.done.removesAction && QueueOutcome.rejected.removesAction)
    }

    @Test func completingRemovesOnlyFinishedActions() throws {
        let store = store()
        store.markRead("a")
        store.delete("b")
        let read = try #require(store.queue.first)
        let delete = try #require(store.queue.last)

        store.complete(read, outcome: .retry)
        store.complete(delete, outcome: .stop)
        #expect(store.queue.count == 2)

        store.complete(read, outcome: .done)
        store.complete(delete, outcome: .rejected)
        #expect(store.queue.isEmpty)
    }

    @Test func replacedActionIsNotRemovedByAnOlderResult() throws {
        let store = store()
        store.markRead("a")
        let sent = try #require(store.queue.first)
        store.markUnread("a")
        store.complete(sent, outcome: .done)
        #expect(store.queue.map(\.operation) == [.read(false)])
    }

    @Test func queueSurvivesReload() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        store.replaceAll(items: [TestData.item("a"), TestData.item("b")], seq: 3)
        store.markRead("a")
        store.delete("b")

        let reloaded = ItemStore(location: dir.location, now: clock.function)
        #expect(reloaded.queue == store.queue)
        #expect(reloaded.item(id: "a")?.isRead == true)
        #expect(reloaded.item(id: "b")?.isDeleted == true)
    }
}
