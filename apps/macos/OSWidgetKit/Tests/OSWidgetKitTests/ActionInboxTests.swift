import Foundation
import Synchronization
import Testing
@testable import OSWidgetKit

@MainActor
@Suite("Action inbox")
struct ActionInboxTests {
    private func action(_ id: String, _ operation: WidgetAction.Operation, secondsAgo: TimeInterval = 5) -> WidgetAction {
        WidgetAction(itemId: id, operation: operation, createdAt: TestData.now.addingTimeInterval(-secondsAgo))
    }

    private func files(in url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted()
    }

    @Test func submittedActionsArePendingOldestFirst() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let inbox = ActionInbox(location: dir.location)
        #expect(inbox.pending().isEmpty)

        let later = action("b", .delete, secondsAgo: 1)
        let earlier = action("a", .markRead, secondsAgo: 9)
        try inbox.submit(later)
        try inbox.submit(earlier)

        #expect(inbox.pending() == [earlier, later])
        #expect(files(in: inbox.directory) == [earlier, later].map { "\($0.id.uuidString).json" }.sorted())
        #expect(inbox.directory == dir.url.appending(path: "inbox", directoryHint: .isDirectory))
    }

    @Test func temporaryFilesAreIgnored() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let inbox = ActionInbox(location: dir.location)
        let kept = action("a", .markRead)
        try inbox.submit(kept)
        let unfinished = action("b", .delete)
        try ServerJSON.makeEncoder().encode(unfinished).write(to: inbox.directory.appending(path: ".tmp-\(unfinished.id.uuidString).json"))

        #expect(inbox.pending() == [kept])
        #expect(inbox.contents().corrupt.isEmpty)
    }

    @Test func corruptFilesDoNotBlockOthersAndAreDrained() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let store = ItemStore(location: dir.location, now: TestClock().function)
        store.replaceAll(items: [TestData.item("a")], seq: 1)
        let inbox = ActionInbox(location: dir.location)
        let good = action("a", .markRead)
        try inbox.submit(good)
        try Data("{\"id\": ".utf8).write(to: inbox.directory.appending(path: "\(UUID().uuidString).json"))
        // A valid action under a name that is not its id could never be removed by id.
        try ServerJSON.makeEncoder().encode(action("a", .delete)).write(to: inbox.directory.appending(path: "\(UUID().uuidString).json"))

        let contents = inbox.contents()
        #expect(contents.actions == [good])
        #expect(contents.corrupt.count == 2)

        #expect(store.drain(inbox) == 1)
        #expect(store.item(id: "a")?.isRead == true && store.item(id: "a")?.isDeleted == false)
        #expect(files(in: inbox.directory).isEmpty)
    }

    @Test func removeSkipsMissingFiles() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let inbox = ActionInbox(location: dir.location)
        let kept = action("a", .markRead)
        try inbox.submit(kept)
        inbox.remove([UUID(), UUID()])
        #expect(inbox.pending() == [kept])
    }

    @Test func submittingNeverTouchesTheStoreFile() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let store = ItemStore(location: dir.location, now: TestClock().function)
        store.replaceAll(items: [TestData.item("a")], seq: 1)
        let before = try Data(contentsOf: dir.storeFile)
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.storeFile.path(percentEncoded: false))

        let inbox = ActionInbox(location: dir.location)
        try inbox.submit(action("a", .markRead))
        try inbox.submit(action("a", .delete))

        #expect(try Data(contentsOf: dir.storeFile) == before)
        let after = try FileManager.default.attributesOfItem(atPath: dir.storeFile.path(percentEncoded: false))
        #expect(after[.modificationDate] as? Date == attributes[.modificationDate] as? Date)
        #expect(files(in: dir.url) == ["inbox", ItemStore.fileName])
    }

    @Test func drainFollowsTheStoreRulesAndSaves() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        store.replaceAll(items: [TestData.item("a"), TestData.item("b"), TestData.item("gone", deleted: true)], seq: 1)
        let inbox = ActionInbox(location: dir.location)
        try inbox.submit(action("a", .markRead, secondsAgo: 9))
        try inbox.submit(action("a", .delete, secondsAgo: 8))
        try inbox.submit(action("b", .markRead, secondsAgo: 7))
        try inbox.submit(action("missing", .markRead, secondsAgo: 6))
        try inbox.submit(action("gone", .markRead, secondsAgo: 5))

        #expect(store.drain(inbox) == 3)

        // Delete wins over read: one delete for `a`, one read for `b`, nothing for unknown or deleted items.
        #expect(store.queue.map(\.itemId) == ["a", "b"])
        #expect(store.queue.map(\.operation) == [.delete, .read(true)])
        #expect(store.queue.map(\.createdAt) == [TestData.now.addingTimeInterval(-8), TestData.now.addingTimeInterval(-7)])
        #expect(store.item(id: "a")?.isDeleted == true)
        #expect(store.item(id: "b")?.readAt == TestData.now.addingTimeInterval(-7))
        #expect(files(in: inbox.directory).isEmpty)

        let reloaded = ItemStore(location: dir.location, now: clock.function)
        #expect(StoreSnapshot(reloaded) == StoreSnapshot(store))
        #expect(store.drain(inbox) == 0)
    }

    @Test func drainedStoreMatchesTheSnapshotShownWhileWaiting() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        store.replaceAll(items: (0..<8).map { TestData.item("i\($0)", createdSecondsAgo: TimeInterval(10 + $0)) }, seq: 1)
        let inbox = ActionInbox(location: dir.location)
        try inbox.submit(action("i0", .markRead))
        try inbox.submit(action("i1", .delete))

        let shown = WidgetSnapshot.make(items: store.items, pending: inbox.pending(), now: clock.now)
        clock.advance(by: 30)
        store.drain(inbox)
        #expect(WidgetSnapshot.make(items: store.items, pending: inbox.pending(), now: clock.now) == shown)
    }

    @Test func drainingAgainAfterDyingBeforeRemovalChangesNothing() throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        store.replaceAll(items: [TestData.item("a"), TestData.item("b"), TestData.item("c")], seq: 1)
        let inbox = ActionInbox(location: dir.location)
        try inbox.submit(action("a", .markRead, secondsAgo: 9))
        try inbox.submit(action("a", .delete, secondsAgo: 8))
        try inbox.submit(action("b", .markRead, secondsAgo: 7))
        try inbox.submit(action("c", .delete, secondsAgo: 6))

        // Keep copies of the files: the app applied them, saved, then died before removing them.
        let names = files(in: inbox.directory)
        let saved = try names.map { try Data(contentsOf: inbox.directory.appending(path: $0)) }
        #expect(store.drain(inbox) == 4)
        let once = StoreSnapshot(store)
        for (name, data) in zip(names, saved) {
            try data.write(to: inbox.directory.appending(path: name))
        }

        let restarted = ItemStore(location: dir.location, now: clock.function)
        #expect(restarted.drain(inbox) == 0)
        #expect(StoreSnapshot(restarted) == once)
        #expect(files(in: inbox.directory).isEmpty)
    }

    @Test func concurrentWritersWhileDrainingApplyEveryActionOnce() async throws {
        let dir = TempStoreDirectory()
        defer { dir.remove() }
        let clock = TestClock()
        let store = ItemStore(location: dir.location, now: clock.function)
        let writers = 8
        let perWriter = 25
        let ids = (0..<writers).flatMap { w in (0..<perWriter).map { "w\(w)-\($0)" } }
        store.replaceAll(items: ids.map { TestData.item($0) }, seq: 1)
        let storeBytesWrittenByStore = try Data(contentsOf: dir.storeFile)
        #expect(!storeBytesWrittenByStore.isEmpty)
        let inbox = ActionInbox(location: dir.location)
        let finished = Flag()

        let submitting = Task.detached {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for w in 0..<writers {
                    group.addTask {
                        for i in 0..<perWriter {
                            let operation: WidgetAction.Operation = i.isMultiple(of: 2) ? .markRead : .delete
                            try inbox.submit(WidgetAction(itemId: "w\(w)-\(i)", operation: operation, createdAt: TestData.now))
                        }
                    }
                }
                try await group.waitForAll()
            }
            finished.set()
        }

        var applied = 0
        var corrupt = 0
        while !finished.isSet {
            corrupt += inbox.contents().corrupt.count
            applied += store.drain(inbox)
            await Task.yield()
        }
        try await submitting.value
        corrupt += inbox.contents().corrupt.count
        applied += store.drain(inbox)

        #expect(applied == writers * perWriter)
        #expect(corrupt == 0)
        #expect(files(in: inbox.directory).isEmpty)
        #expect(store.queue.count == writers * perWriter)
        for w in 0..<writers {
            for i in 0..<perWriter {
                let item = try #require(store.item(id: "w\(w)-\(i)"))
                if i.isMultiple(of: 2) {
                    #expect(item.isRead && !item.isDeleted)
                } else {
                    #expect(item.isDeleted)
                }
            }
        }
        // The only files beside the inbox are the store's own.
        #expect(files(in: dir.url) == ["inbox", ItemStore.fileName])
        let reloaded = ItemStore(location: dir.location, now: clock.function)
        #expect(StoreSnapshot(reloaded) == StoreSnapshot(store))
    }
}

private final class Flag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool { value.withLock { $0 } }

    func set() {
        value.withLock { $0 = true }
    }
}
