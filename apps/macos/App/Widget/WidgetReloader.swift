import Foundation
import OSLog
import OSWidgetKit
import WidgetKit

/// Asks WidgetKit to reload the items widget when what the widget shows has changed.
///
/// Every change to the store's items builds a `WidgetSnapshot`, with the actions still waiting in the
/// inbox laid over it, and offers it to `WidgetReloadPolicy`. Sync rounds that change nothing the
/// widget shows, and queue or cursor changes, produce an equal snapshot and no reload. Each request
/// is logged at `notice` so `scripts/widget-reload-count.sh` can count them.
@MainActor
final class WidgetReloader {
    private static let logger = Logger(subsystem: "local.oswidget.app", category: "widget")

    private let env: AppEnvironment
    private let now: @Sendable () -> Date
    private let requestReload: @MainActor (String) -> Void
    private var policy: WidgetReloadPolicy
    private var inbox: ActionInbox?
    private var timer: Task<Void, Never>?
    private var started = false

    init(
        env: AppEnvironment,
        policy: WidgetReloadPolicy = WidgetReloadPolicy(),
        now: @escaping @Sendable () -> Date = { Date() },
        requestReload: @escaping @MainActor (String) -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
    ) {
        self.env = env
        self.policy = policy
        self.now = now
        self.requestReload = requestReload
    }

    func start() {
        guard !started else { return }
        started = true
        guard let location = try? StoreLocation.appGroup() else {
            Self.logger.notice("widget.reload_disabled reason=no_container")
            return
        }
        inbox = ActionInbox(location: location)
        storeChanged()
    }

    func stop() {
        started = false
        timer?.cancel()
        timer = nil
    }

    private func observe() {
        withObservationTracking {
            _ = env.store.items
        } onChange: { [weak self] in
            Task { @MainActor in self?.storeChanged() }
        }
    }

    private func storeChanged() {
        guard started, let inbox else { return }
        // Tracking fires once per registration, so register again before doing anything else.
        observe()
        // Read the inbox before taking the time, so the time is close to when the log line is written.
        let pending = inbox.pending()
        let time = now()
        let snapshot = WidgetSnapshot.make(items: env.store.items, pending: pending, now: time)
        let gap = policy.lastReloadAt
        let firstReload = gap == nil
        switch policy.offer(snapshot, at: time) {
        case .reloadNow:
            policy.didReload(snapshot, at: time)
            perform(reason: firstReload ? "first" : "changed", since: gap, at: time)
        case .schedule(let due):
            Self.logger.debug("widget.reload_skipped reason=coalesced")
            arm(timerFor: due)
        case .skip:
            Self.logger.debug("widget.reload_skipped reason=\(self.policy.isWaiting ? "coalesced" : "unchanged", privacy: .public)")
        }
    }

    private func arm(timerFor due: Date) {
        timer?.cancel()
        let delay = max(due.timeIntervalSince(now()), 0)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.timerRang()
        }
    }

    private func timerRang() {
        timer = nil
        let time = now()
        let since = policy.lastReloadAt
        if policy.fire(at: time) {
            perform(reason: "trailing", since: since, at: time)
        } else {
            Self.logger.debug("widget.reload_skipped reason=unchanged")
        }
    }

    /// Logs before asking WidgetKit: the count script measures the gap between requests from the log
    /// timestamps, so they must track the policy's times and not how long the reload call takes.
    private func perform(reason: String, since previous: Date?, at time: Date) {
        let gapMs = previous.map { Int((time.timeIntervalSince($0) * 1000).rounded()) } ?? 0
        Self.logger.notice("widget.reload n_today=\(self.policy.reloadsToday, privacy: .public) reason=\(reason, privacy: .public) gap_ms=\(gapMs, privacy: .public)")
        requestReload(WidgetKind.items)
    }
}
