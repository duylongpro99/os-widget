import Foundation

/// What the popup should do with a batch of new items.
public enum PopupDecision: Sendable, Hashable {
    /// Show nothing. `reason` says why, for the `popup.suppressed` log line.
    case none(reason: PopupPolicy.SuppressReason)
    /// Show `newest`, with `othersCount` more items behind it ("+N").
    case show(newest: Item, othersCount: Int)
}

/// Decides when the popup opens and what it shows. Pure functions only, so every rule is testable
/// without a window.
public enum PopupPolicy {
    /// How long the popup stays open without the pointer inside it.
    public static let displayDuration: TimeInterval = 30

    public enum SuppressReason: String, Sendable, Hashable {
        /// Every new item has `priority: low`.
        case low
        /// Every new item is of a kind whose popup is turned off.
        case kind
        /// Quiet mode is on.
        case quiet
        /// The item list is showing; it highlights new items itself.
        case listOpen = "list_open"
        /// Nothing new to show: the items were already read, deleted or expired.
        case nothingNew = "nothing_new"
    }

    /// Decides whether `items` (one announcement) open the popup. The list being open wins over quiet
    /// mode, which wins over the per-item filters. Items that are read, deleted or expired are dropped
    /// silently; then `low` items and items of a disabled kind. When nothing is left, the reason is the
    /// one that removed the newest remaining candidate.
    public static func decide(
        items: [Item],
        settings: PopupSettings,
        isListOpen: Bool,
        now: Date
    ) -> PopupDecision {
        if isListOpen { return .none(reason: .listOpen) }
        if settings.quietMode { return .none(reason: .quiet) }

        let candidates = items
            .filter { $0.isVisible(at: now) && !$0.isRead }
            .sorted(by: newestFirst)
        guard let newestCandidate = candidates.first else { return .none(reason: .nothingNew) }

        let shown = candidates.filter { suppressReason(for: $0, settings: settings) == nil }
        guard let newest = shown.first else {
            return .none(reason: suppressReason(for: newestCandidate, settings: settings) ?? .nothingNew)
        }
        return .show(newest: newest, othersCount: shown.count - 1)
    }

    /// Combines what the popup shows now with a new decision. A new `.show` replaces the content with
    /// its newest item and counts the item shown before, and its others, as others too. A `.none`
    /// leaves the current content alone. An incoming item already showing is not counted twice.
    public static func merge(current: PopupDecision?, incoming: PopupDecision) -> PopupDecision {
        guard case .show(let incomingNewest, let incomingOthers) = incoming else { return current ?? incoming }
        guard case .show(let currentNewest, let currentOthers) = current else { return incoming }
        if currentNewest.id == incomingNewest.id {
            return .show(newest: incomingNewest, othersCount: max(currentOthers, incomingOthers))
        }
        return .show(newest: incomingNewest, othersCount: currentOthers + 1 + incomingOthers)
    }

    private static func suppressReason(for item: Item, settings: PopupSettings) -> SuppressReason? {
        if item.priority == "low" { return .low }
        if !settings.isEnabled(kind: item.kind) { return .kind }
        return nil
    }

    private static func newestFirst(_ a: Item, _ b: Item) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id > b.id
    }
}

/// The popup's close timer: it runs for `duration`, pauses while the pointer is inside the popup and
/// resumes with the time left when the pointer leaves. A new item starts a fresh countdown.
public struct PopupCountdown: Sendable, Hashable {
    public let duration: TimeInterval
    private var remainingWhenPaused: TimeInterval
    /// When the running countdown reaches zero; `nil` while paused.
    public private(set) var deadline: Date?

    /// A countdown of `duration` running from `now`.
    public init(duration: TimeInterval = PopupPolicy.displayDuration, startingAt now: Date) {
        self.duration = duration
        remainingWhenPaused = duration
        deadline = now.addingTimeInterval(duration)
    }

    public var isPaused: Bool { deadline == nil }

    /// Seconds left at `now`, never negative.
    public func remaining(at now: Date) -> TimeInterval {
        guard let deadline else { return remainingWhenPaused }
        return max(0, deadline.timeIntervalSince(now))
    }

    public func isExpired(at now: Date) -> Bool {
        !isPaused && remaining(at: now) <= 0
    }

    /// Stops the countdown, keeping the time left. Pausing twice changes nothing.
    public mutating func pause(at now: Date) {
        guard !isPaused else { return }
        remainingWhenPaused = remaining(at: now)
        deadline = nil
    }

    /// Continues the countdown with the time left when it was paused. Resuming a running countdown
    /// changes nothing.
    public mutating func resume(at now: Date) {
        guard isPaused else { return }
        deadline = now.addingTimeInterval(remainingWhenPaused)
    }
}
