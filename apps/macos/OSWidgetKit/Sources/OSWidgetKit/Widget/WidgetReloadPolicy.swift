import Foundation

/// Decides when the app asks WidgetKit to reload the widget.
///
/// A reload is worth asking for only when the snapshot differs from the one the widget was last told
/// about, and no more often than `minimumInterval`: a change that arrives too soon after a reload is
/// held back and answered by one reload when the interval has passed, using the newest snapshot.
///
/// The policy is a pure value with no timers and no clock of its own. The caller passes the time in,
/// starts one timer when told to `.schedule`, and calls `fire(at:)` when it rings.
public struct WidgetReloadPolicy: Sendable {
    public enum Decision: Sendable, Equatable {
        /// Nothing to do: the widget already shows this, or a reload is already scheduled.
        case skip
        /// Ask for a reload now and report it with `didReload(_:at:)`.
        case reloadNow
        /// Call `fire(at:)` at this time. Returned once per waiting period.
        case schedule(at: Date)
    }

    public let minimumInterval: Duration

    /// The snapshot the widget was last asked to reload for. `nil` until the first reload, so the first
    /// offer after launch always reloads: the widget may still show data from the previous run.
    public private(set) var lastReloaded: WidgetSnapshot?
    public private(set) var lastReloadAt: Date?
    /// Reloads asked for since local midnight. Rolls over on the next `offer`, `fire` or `didReload`.
    public private(set) var reloadsToday = 0

    private var pending: WidgetSnapshot?
    private var timerArmed = false
    private var countedDay: Date?
    private let calendar: Calendar

    public init(minimumInterval: Duration = .seconds(5), calendar: Calendar = .current) {
        self.minimumInterval = minimumInterval
        self.calendar = calendar
    }

    /// Whether a scheduled reload is waiting for `fire(at:)`.
    public var isWaiting: Bool { timerArmed }

    public mutating func offer(_ snapshot: WidgetSnapshot, at now: Date) -> Decision {
        rollDay(at: now)
        if timerArmed {
            // The reload at the end of the wait uses whatever arrived last.
            pending = snapshot
            return .skip
        }
        guard snapshot != lastReloaded else { return .skip }
        guard let lastReloadAt, now.timeIntervalSince(lastReloadAt) < minimumInterval.seconds else {
            return .reloadNow
        }
        pending = snapshot
        timerArmed = true
        return .schedule(at: lastReloadAt.addingTimeInterval(minimumInterval.seconds))
    }

    /// Call when the timer from `.schedule` rings. Returns `true` when the newest waiting snapshot
    /// still differs from the last reloaded one; the reload is then counted as done and the caller asks
    /// WidgetKit for it.
    public mutating func fire(at now: Date) -> Bool {
        timerArmed = false
        defer { pending = nil }
        guard let snapshot = pending, snapshot != lastReloaded else { return false }
        didReload(snapshot, at: now)
        return true
    }

    /// Records a reload asked for after `.reloadNow`.
    public mutating func didReload(_ snapshot: WidgetSnapshot, at now: Date) {
        rollDay(at: now)
        lastReloaded = snapshot
        lastReloadAt = now
        reloadsToday += 1
    }

    private mutating func rollDay(at now: Date) {
        let day = calendar.startOfDay(for: now)
        if countedDay != day {
            countedDay = day
            reloadsToday = 0
        }
    }
}

extension Duration {
    /// The duration in seconds as a floating-point number.
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
