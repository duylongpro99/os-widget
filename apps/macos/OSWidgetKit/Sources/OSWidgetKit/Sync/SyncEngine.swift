import Foundation
import os

/// Where sync and Realtime log lines go: `os.Logger` with subsystem `local.oswidget.app`, category
/// `sync`. Lines carry only ids, sequence numbers, status codes and states, never a token or item
/// content. Tests capture the lines instead.
public struct SyncLog: Sendable {
    private let write: @Sendable (String) -> Void

    public init(_ write: @escaping @Sendable (String) -> Void) {
        self.write = write
    }

    public static let system: SyncLog = {
        let logger = Logger(subsystem: "local.oswidget.app", category: "sync")
        return SyncLog { logger.info("\($0, privacy: .public)") }
    }()

    func callAsFunction(_ message: String) {
        write(message)
    }
}

/// Keeps the local store in step with the server (architecture §5).
///
/// One round sends the queued user actions, then fetches: `GET /items` when there is no cursor yet,
/// otherwise `GET /events` page by page from a little before the cursor, announcing the new items once
/// at the end. Sending before fetching, within one round, keeps a fetch from racing an action that is
/// still on its way. A full `GET /items` reconciliation follows the event fetch when the last one is
/// more than six hours old or after a long sleep.
///
/// Rounds never overlap: a request that arrives during a round makes exactly one more round run after
/// it. A round that fails for lack of network or a server error is retried after 2, 4, 8 … up to 60
/// seconds; any other trigger runs a round straight away.
public actor SyncEngine {
    /// How far before the cursor a fetch starts, to catch events committed out of `seq` order.
    public static let eventLookback: Int64 = 20
    public static let reconcileInterval: TimeInterval = 6 * 60 * 60

    private let api: APIClient
    private let store: ItemStore
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let log: SyncLog

    private var running = false
    private var rerunRequested = false
    private var reconcileRequested = false
    private var loggedNotConfigured = false
    private var retryBackoff = ReconnectPolicy(initial: .seconds(2), maximum: .seconds(60))
    /// Bumped by every round, so a retry scheduled before it no longer fires.
    private var retryGeneration = 0

    public init(
        api: APIClient,
        store: ItemStore,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        log: SyncLog = .system
    ) {
        self.api = api
        self.store = store
        self.now = now
        self.sleep = sleep
        self.log = log
    }

    /// Runs a round, or, when one is running, makes one more round run after it and returns at once.
    public func sync() async {
        guard !running else {
            rerunRequested = true
            return
        }
        running = true
        repeat {
            rerunRequested = false
            await round()
        } while rerunRequested
        running = false
    }

    /// Starts `sync()` without waiting for it.
    public nonisolated func trigger() {
        Task { await self.sync() }
    }

    /// Makes the next round reconcile with `GET /items` whatever the time of the last one, for example
    /// after the Mac slept for more than a day.
    public func requestReconcile() {
        reconcileRequested = true
    }

    /// Triggers a round for every signal until the stream ends.
    public func listen(to signal: some ChangeSignal) async {
        for await _ in signal.signals {
            trigger()
        }
    }

    // MARK: - Round

    private func round() async {
        guard api.isConfigured else {
            if !loggedNotConfigured {
                log("sync.not_configured")
                loggedNotConfigured = true
            }
            return
        }
        loggedNotConfigured = false
        retryGeneration += 1
        log("sync.start")
        do throws(APIError) {
            try await sendQueue()
            let fresh = try await fetchEvents()
            try await reconcileIfDue()
            await announce(fresh)
            retryBackoff.reset()
        } catch {
            handle(error)
        }
    }

    /// Sends the queued actions oldest first. Stops at the first action that cannot be sent now.
    private func sendQueue() async throws(APIError) {
        let actions = await store.queue
        for action in actions {
            let status: Int?
            do throws(APIError) {
                switch action.operation {
                case .read(let read):
                    status = try await api.patchRead(id: action.itemId, read: read)
                case .delete:
                    status = try await api.delete(id: action.itemId)
                }
            } catch {
                guard error == .network else { throw error }
                status = nil
            }
            let outcome = PendingAction.outcome(for: status)
            await store.complete(action, outcome: outcome)
            if let status {
                log("sync.queue_sent id=\(action.itemId) status=\(status)")
            }
            switch outcome {
            case .stop, .retry:
                throw status.map(APIError.status) ?? .network
            case .done, .rejected:
                continue
            }
        }
    }

    /// Brings the store up to date and returns the ids of the items new in this round, in order.
    private func fetchEvents() async throws(APIError) -> [String] {
        guard let cursor = await store.cursor else {
            try await fullSync()
            return []
        }
        var since = max(0, cursor - Self.eventLookback)
        var fresh: [String] = []
        var firstSeq: Int64?
        var lastSeq: Int64?
        while true {
            let events = try await api.getEvents(since: since, limit: APIClient.eventPageSize)
            guard let pageLast = events.map(\.seq).max() else { break }
            let new = await store.apply(events: events)
            for item in new where !fresh.contains(item.id) {
                fresh.append(item.id)
            }
            firstSeq = firstSeq ?? events.map(\.seq).min()
            lastSeq = pageLast
            guard events.count >= APIClient.eventPageSize, pageLast > since else { break }
            since = pageLast
        }
        if let firstSeq, let lastSeq {
            log("sync.applied seq=\(firstSeq)..\(lastSeq) new=\(fresh.count)")
        }
        return fresh
    }

    private func reconcileIfDue() async throws(APIError) {
        let lastFullSync = await store.lastFullSyncAt
        let stale = lastFullSync.map { now().timeIntervalSince($0) > Self.reconcileInterval } ?? true
        guard reconcileRequested || stale else { return }
        try await fullSync()
    }

    private func fullSync() async throws(APIError) {
        let response = try await api.getItems()
        await store.replaceAll(items: response.items, seq: response.seq)
        reconcileRequested = false
        log("sync.reconcile items=\(response.items.count)")
    }

    /// Announces the new items that are still unread and visible after the whole round.
    private func announce(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        await MainActor.run {
            let wanted = Set(ids)
            store.announce(store.visibleItems.filter { wanted.contains($0.id) && !$0.isRead })
        }
    }

    // MARK: - Failures

    private func handle(_ error: APIError) {
        if error.isAuthFailure {
            log("sync.auth_failed")
        } else if error.isTemporary {
            let delay = retryBackoff.nextDelay()
            log("sync.retry in=\(delay.components.seconds)s reason=\(Self.describe(error))")
            scheduleRetry(after: delay)
        } else if error == .notConfigured {
            log("sync.not_configured")
        } else {
            log("sync.failed reason=\(Self.describe(error))")
        }
    }

    private func scheduleRetry(after delay: Duration) {
        let generation = retryGeneration
        let sleep = sleep
        Task {
            do {
                try await sleep(delay)
            } catch {
                return
            }
            await self.retryFired(generation: generation)
        }
    }

    private func retryFired(generation: Int) async {
        guard generation == retryGeneration else { return }
        await sync()
    }

    private static func describe(_ error: APIError) -> String {
        switch error {
        case .notConfigured: "not_configured"
        case .network: "network"
        case .status(let code): "status_\(code)"
        case .decoding: "decoding"
        }
    }
}
