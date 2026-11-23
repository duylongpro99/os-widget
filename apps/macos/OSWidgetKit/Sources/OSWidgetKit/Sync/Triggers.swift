import AppKit
import Foundation
import Network
import Observation

/// Watches the store's action queue and calls `onNewAction` when it gains an action that was not there
/// before, so a read or delete is sent at once. Actions only being removed (a round draining the queue)
/// and actions kept for a retry do not trigger again; the retry backoff and the other triggers cover
/// those.
@MainActor
public final class QueueWatcher {
    private let store: ItemStore
    private let onNewAction: @MainActor () -> Void
    private var known: Set<UUID> = []
    /// Bumped by `start()` and `stop()` so a tracking armed before then is ignored.
    private var generation = 0

    public init(store: ItemStore, onNewAction: @escaping @MainActor () -> Void) {
        self.store = store
        self.onNewAction = onNewAction
    }

    public func start() {
        generation += 1
        known = Set(store.queue.map(\.id))
        observe(generation: generation)
    }

    public func stop() {
        generation += 1
    }

    private func observe(generation: Int) {
        withObservationTracking {
            _ = store.queue
        } onChange: { [weak self] in
            Task { @MainActor in self?.queueChanged(generation: generation) }
        }
    }

    private func queueChanged(generation: Int) {
        guard generation == self.generation else { return }
        let ids = Set(store.queue.map(\.id))
        let added = !ids.subtracting(known).isEmpty
        known = ids
        observe(generation: generation)
        if added { onNewAction() }
    }
}

/// System events that call for a sync: the Mac waking up, the network coming back, and a fallback poll
/// every five minutes. It also reports when the Mac is about to sleep so the Realtime socket can close.
@MainActor
public final class SystemTriggers {
    public static let pollInterval: Duration = .seconds(5 * 60)

    private let onSync: @MainActor () -> Void
    private let onWillSleep: @MainActor () -> Void
    /// Called with how long the Mac slept, in seconds.
    private let onDidWake: @MainActor (TimeInterval) -> Void
    private let pollInterval: Duration

    private var observers: [NSObjectProtocol] = []
    private var pathMonitor: NWPathMonitor?
    private var pollTask: Task<Void, Never>?
    private var sleptAt: Date?

    public init(
        pollInterval: Duration = SystemTriggers.pollInterval,
        onSync: @escaping @MainActor () -> Void,
        onWillSleep: @escaping @MainActor () -> Void,
        onDidWake: @escaping @MainActor (TimeInterval) -> Void
    ) {
        self.pollInterval = pollInterval
        self.onSync = onSync
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
    }

    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })

        let monitor = NWPathMonitor()
        let last = PathState()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            // The first update reports the state at start; only a later change to satisfied triggers.
            let cameBack = last.wasSatisfied == false && satisfied
            last.wasSatisfied = satisfied
            guard cameBack else { return }
            Task { @MainActor in self?.onSync() }
        }
        monitor.start(queue: DispatchQueue(label: "local.oswidget.app.path-monitor"))
        pathMonitor = monitor

        let interval = pollInterval
        pollTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
                self?.onSync()
            }
        }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
        pathMonitor?.cancel()
        pathMonitor = nil
        pollTask?.cancel()
        pollTask = nil
    }

    private func willSleep() {
        sleptAt = Date()
        onWillSleep()
    }

    private func didWake() {
        let slept = sleptAt.map { Date().timeIntervalSince($0) } ?? 0
        sleptAt = nil
        onDidWake(slept)
    }
}

/// The last network state seen. Only touched by the path monitor's serial queue.
private final class PathState: @unchecked Sendable {
    var wasSatisfied: Bool?
}
