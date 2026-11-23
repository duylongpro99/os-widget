import Foundation
import Synchronization
import Testing
@testable import OSWidgetKit

@MainActor
@Suite("Sync engine")
struct SyncEngineTests {
    let server = FakeServer()
    let logs = LogRecorder()
    let clock = TestClock()

    private func makeStore() -> ItemStore {
        ItemStore(location: nil, now: clock.function)
    }

    private func makeEngine(
        _ store: ItemStore,
        credentials: ServerCredentials? = SyncTestData.credentials,
        sleep: @escaping @Sendable (Duration) async throws -> Void = SyncTestData.neverSleep
    ) -> SyncEngine {
        SyncEngine(
            api: APIClient(credentials: { credentials }, transport: server),
            store: store,
            now: clock.function,
            sleep: sleep,
            log: logs.log
        )
    }

    /// A store already synced with the server at its current `seq`, without recording requests.
    private func syncedStore(items: [Item] = []) -> ItemStore {
        let store = makeStore()
        store.replaceAll(items: items, seq: server.seq)
        return store
    }

    private static func item(_ id: String, createdSecondsAgo: TimeInterval = 60) -> Item {
        TestData.item(id, createdSecondsAgo: createdSecondsAgo, expiresIn: nil)
    }

    // MARK: First sync

    @Test func firstSyncFetchesItemsOnlyAndAnnouncesNothing() async {
        server.publish(Self.item("a"))
        server.publish(Self.item("b"))
        let store = makeStore()

        await makeEngine(store).sync()

        #expect(server.requestLines == ["GET /items"])
        #expect(Set(store.visibleItems.map(\.id)) == ["a", "b"])
        #expect(store.cursor == 2)
        #expect(store.announcement == nil)
        #expect(logs.all.contains("sync.reconcile items=2"))
    }

    // MARK: Events

    @Test func fullPagesAreFollowedWithTheLastSeq() async {
        let store = makeStore()
        store.replaceAll(items: [], seq: 0)
        for index in 1...150 {
            server.logEvent(.read, id: "missing-\(index)")
        }

        await makeEngine(store).sync()

        #expect(server.requestLines == ["GET /events?limit=100&since=0", "GET /events?limit=100&since=100"])
        #expect(store.cursor == 150)
        #expect(logs.all.contains("sync.applied seq=1..150 new=0"))
    }

    @Test func newItemsOfEveryPageAreAnnouncedOnceAtTheEndOfTheRound() async {
        let store = syncedStore()
        let ids = (1...120).map { String(format: "n%03d", $0) }
        for (index, id) in ids.enumerated() {
            server.publish(Self.item(id, createdSecondsAgo: Double(1000 - index)))
        }

        await makeEngine(store).sync()

        #expect(server.requests.count == 2)
        #expect(store.announcement?.serial == 1)
        #expect(store.announcement?.items.map(\.id) == ids.reversed())
    }

    @Test func aShortPageEndsTheFetch() async {
        let store = makeStore()
        store.replaceAll(items: [], seq: 0)
        for index in 1...99 {
            server.logEvent(.read, id: "missing-\(index)")
        }

        await makeEngine(store).sync()

        #expect(server.requestLines == ["GET /events?limit=100&since=0"])
    }

    @Test(arguments: [(Int64(50), "30"), (Int64(20), "0"), (Int64(5), "0")])
    func fetchStartsTwentyBeforeTheCursorButNotBelowZero(cursor: Int64, since: String) async {
        let store = makeStore()
        store.replaceAll(items: [], seq: cursor)

        await makeEngine(store).sync()

        #expect(server.requests.first?.query["since"] == since)
    }

    @Test func roundsNeverOverlap() async {
        let store = makeStore()
        let engine = makeEngine(store)
        server.hold()

        let first = Task { await engine.sync() }
        let reached1 = await eventually { [logs] in logs.count("sync.start") == 1 }
        #expect(reached1)
        await engine.sync()
        await engine.sync()
        await engine.sync()
        server.release()
        await first.value

        #expect(logs.count("sync.start") == 2)
        #expect(server.requestLines == ["GET /items", "GET /events?limit=100&since=0"])
    }

    @Test func offlineThenOnlineBringsEveryMissedItemOnce() async {
        server.publish(Self.item("old"))
        let store = syncedStore(items: [Self.item("old")])
        let engine = makeEngine(store)

        server.setOffline(true)
        for (index, id) in ["x", "y", "z"].enumerated() {
            server.publish(Self.item(id, createdSecondsAgo: Double(30 - index)))
        }
        await engine.sync()
        #expect(store.visibleItems.map(\.id) == ["old"])
        #expect(logs.all.contains("sync.retry in=2s reason=network"))

        server.setOffline(false)
        await engine.sync()

        #expect(store.visibleItems.map(\.id) == ["z", "y", "x", "old"])
        #expect(store.items.count == 4)
        #expect(store.announcement?.serial == 1)
        #expect(store.announcement?.items.map(\.id) == ["z", "y", "x"])

        await engine.sync()
        #expect(store.items.count == 4)
        #expect(store.announcement?.serial == 1)
    }

    @Test func retriesBackOffAndResetAfterSuccess() async {
        let delays = Mutex<[Duration]>([])
        let store = syncedStore()
        let engine = makeEngine(store, sleep: { delay in
            delays.withLock { $0.append(delay) }
            throw CancellationError()
        })

        server.setOffline(true)
        for _ in 0..<7 {
            await engine.sync()
        }
        server.setOffline(false)
        await engine.sync()
        server.setOffline(true)
        await engine.sync()

        let reached2 = await eventually { delays.withLock { $0.count } == 8 }
        #expect(reached2)
        #expect(delays.withLock { $0 } == [2, 4, 8, 16, 32, 60, 60, 2].map { Duration.seconds($0) })
    }

    @Test func aScheduledRetryRunsARound() async {
        let store = syncedStore()
        let engine = makeEngine(store, sleep: { _ in })
        server.setOffline(true)
        await engine.sync()
        server.setOffline(false)

        let reached3 = await eventually { [server] in server.requests.count == 1 }
        #expect(reached3)
        #expect(server.requestLines == ["GET /events?limit=100&since=0"])
    }

    // MARK: Queue

    @Test func queueIsSentBeforeTheFetch() async {
        let items = ["a", "b"].map { Self.item($0) }
        items.forEach(server.publish)
        let store = syncedStore(items: items)
        store.markRead("a")
        store.delete("b")

        await makeEngine(store).sync()

        #expect(server.requestLines == ["PATCH /items/a", "DELETE /items/b", "GET /events?limit=100&since=0"])
        #expect(store.queue.isEmpty)
        #expect(store.item(id: "a")?.isRead == true)
        #expect(store.visibleItems.map(\.id) == ["a"])
        #expect(logs.all.contains("sync.queue_sent id=a status=204"))
    }

    @Test func notFoundIsDroppedAndServerErrorIsKeptForTheNextRound() async {
        let items = ["a", "b"].map { Self.item($0) }
        items.forEach(server.publish)
        let store = syncedStore(items: items)
        server.force([404], for: "a")
        server.force([503], for: "b")
        store.markRead("a")
        store.markRead("b")
        let engine = makeEngine(store)

        await engine.sync()

        #expect(server.requestLines == ["PATCH /items/a", "PATCH /items/b"])
        #expect(store.queue.map(\.itemId) == ["b"])
        #expect(store.item(id: "b")?.isRead == true)

        await engine.sync()

        #expect(server.requestLines.suffix(2) == ["PATCH /items/b", "GET /events?limit=100&since=0"])
        #expect(store.queue.isEmpty)
    }

    @Test func unauthorizedStopsSendingAndLogs() async {
        let items = ["a", "b"].map { Self.item($0) }
        items.forEach(server.publish)
        let store = syncedStore(items: items)
        server.force([401], for: "a")
        store.markRead("a")
        store.delete("b")

        await makeEngine(store).sync()

        #expect(server.requestLines == ["PATCH /items/a"])
        #expect(store.queue.map(\.itemId) == ["a", "b"])
        #expect(logs.count("sync.auth_failed") == 1)
        #expect(logs.count("sync.retry") == 0)
    }

    // MARK: Reconciliation

    @Test func reconcileRunsAfterTheEventFetchOnceSixHoursPassed() async {
        let items = ["a", "b"].map { Self.item($0) }
        items.forEach(server.publish)
        let store = syncedStore(items: items)
        let engine = makeEngine(store)

        server.purge("b")
        server.publish(Self.item("c", createdSecondsAgo: 1))
        clock.advance(by: 5 * 60 * 60)
        await engine.sync()
        #expect(!server.requestLines.contains("GET /items"))
        #expect(store.item(id: "b") != nil)

        clock.advance(by: 60 * 60 + 1)
        await engine.sync()

        #expect(server.requestLines.suffix(2) == ["GET /events?limit=100&since=0", "GET /items"])
        #expect(store.item(id: "b") == nil)
        #expect(Set(store.visibleItems.map(\.id)) == ["a", "c"])
        #expect(store.lastFullSyncAt == clock.now)
        #expect(store.announcement?.items.map(\.id) == ["c"])
        #expect(store.announcement?.serial == 1)
    }

    @Test func requestedReconcileRunsOnTheNextRound() async {
        let store = syncedStore()
        let engine = makeEngine(store)

        await engine.requestReconcile()
        await engine.sync()
        await engine.sync()

        #expect(server.requestLines == ["GET /events?limit=100&since=0", "GET /items", "GET /events?limit=100&since=0"])
    }

    // MARK: Other devices

    @Test func readOnAnotherDeviceMarksTheItemRead() async {
        let items = ["a", "b"].map { Self.item($0) }
        items.forEach(server.publish)
        let store = syncedStore(items: items)
        #expect(store.unreadCount == 2)

        server.markRead("a")
        await makeEngine(store).sync()

        #expect(store.item(id: "a")?.isRead == true)
        #expect(store.unreadCount == 1)
        #expect(store.announcement == nil)
    }

    // MARK: Configuration

    @Test func withoutCredentialsNothingIsSentAndTheGapIsLoggedOnce() async {
        let store = makeStore()
        let engine = makeEngine(store, credentials: nil)

        await engine.sync()
        await engine.sync()

        #expect(server.requests.isEmpty)
        #expect(logs.all == ["sync.not_configured"])
    }

    @Test func signalsTriggerRounds() async {
        let store = syncedStore()
        let engine = makeEngine(store)
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let listening = Task { await engine.listen(to: SyncTestSignal(signals: stream)) }
        continuation.yield()
        let reached4 = await eventually { [logs] in logs.count("sync.start") >= 1 }
        #expect(reached4)
        continuation.finish()
        await listening.value
    }

    // MARK: Queue watcher

    @Test func aNewActionTriggersOneSyncAndDrainingTriggersNone() async throws {
        let store = syncedStore(items: ["a", "b"].map { Self.item($0) })
        let triggered = Counter()
        let watcher = QueueWatcher(store: store) { triggered.increment() }
        watcher.start()

        store.markRead("a")
        let reached5 = await eventually { triggered.count == 1 }
        #expect(reached5)

        let action = try #require(store.queue.first)
        store.complete(action, outcome: .retry)
        store.complete(action, outcome: .done)
        try await Task.sleep(for: .milliseconds(100))
        #expect(triggered.count == 1)
        #expect(store.queue.isEmpty)

        store.delete("b")
        let reached6 = await eventually { triggered.count == 2 }
        #expect(reached6)
        watcher.stop()
        store.markRead("a")
        try await Task.sleep(for: .milliseconds(100))
        #expect(triggered.count == 2)
    }
}
