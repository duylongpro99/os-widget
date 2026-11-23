import AppKit
import Observation
import OSWidgetKit
import SwiftUI
import os

/// Shows new items in a non-activating panel under the menu bar icon.
///
/// It watches `store.announcement` only. Each new announcement goes through `PopupPolicy`; a shown
/// popup closes after 30 seconds without the pointer inside it, when the list opens, or when the user
/// clicks it. Closing without clicking the card leaves the item unread. `anchor` returns the icon's
/// frame on screen and `isListOpen` whether the item list is showing; both come from
/// `MenuBarController`.
@MainActor
final class PopupController {
    private let environment: AppEnvironment
    private let anchor: () -> NSRect?
    private let isListOpen: () -> Bool
    private let log = Logger(subsystem: "local.oswidget.app", category: "popup")

    private lazy var panel = PopupPanel { [weak self] inside in self?.pointerInside(inside) }
    /// What the panel shows, or `nil` when it is closed.
    private var showing: PopupDecision?
    private var countdown: PopupCountdown?
    private var closeTimer: Timer?
    /// Whether the pointer is inside the panel, from its tracking area.
    private var pointerIsInside = false
    private var lastSerial: Int?
    private var popoverObserver: NSObjectProtocol?

    init(env: AppEnvironment, anchor: @escaping () -> NSRect?, isListOpen: @escaping () -> Bool) {
        environment = env
        self.anchor = anchor
        self.isListOpen = isListOpen
        // The only popover in the app is the item list, so a popover about to show means the list is opening.
        popoverObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.willShowNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(reason: "list") }
        }
        observeAnnouncements()
        #if DEBUG
        scheduleDebugAnnouncement()
        #endif
    }

    // MARK: - Announcements

    private func observeAnnouncements() {
        let announcement = withObservationTracking {
            environment.store.announcement
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAnnouncements() }
        }
        handle(announcement)
    }

    private func handle(_ announcement: Announcement?) {
        guard let announcement, announcement.serial != lastSerial else { return }
        lastSerial = announcement.serial
        let now = Date()
        let decision = PopupPolicy.decide(
            items: announcement.items,
            settings: environment.store.popupSettings,
            isListOpen: isListOpen(),
            now: now
        )
        switch decision {
        case .none(let reason):
            if reason != .nothingNew {
                log.info("popup.suppressed reason=\(reason.rawValue, privacy: .public)")
            }
        case .show:
            show(PopupPolicy.merge(current: showing, incoming: decision), now: now)
        }
    }

    // MARK: - Showing and closing

    private func show(_ decision: PopupDecision, now: Date) {
        guard case .show(let item, let othersCount) = decision else { return }
        showing = decision
        panel.setContent(AnyView(PopupContentView(
            item: item,
            othersCount: othersCount,
            card: { PopupPlainCard(item: $0) },
            onOpenItem: { [weak self] in self?.openItem(item) },
            onShowList: { [weak self] in self?.showList() },
            onClose: { [weak self] in self?.close(reason: "button") }
        )))
        panel.place(under: anchor())
        panel.orderFrontRegardless()
        startCountdown(at: now)
        let latency = Int((now.timeIntervalSince(item.createdAt) * 1000).rounded())
        log.info("popup.shown id=\(item.id, privacy: .public) others=\(othersCount, privacy: .public) latency_ms=\(latency, privacy: .public)")
    }

    private func close(reason: String) {
        guard showing != nil else { return }
        showing = nil
        countdown = nil
        closeTimer?.invalidate()
        closeTimer = nil
        // A hidden panel reports no exit, so the pointer counts as outside from here on.
        pointerIsInside = false
        panel.orderOut(nil)
        log.info("popup.closed reason=\(reason, privacy: .public)")
    }

    /// Clicking the card reads the item, opens its link when it is safe to open, and closes the popup.
    private func openItem(_ item: Item) {
        environment.store.markRead(item.id)
        if let link = item.url, Self.isOpenable(link), let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
        close(reason: "click")
    }

    /// "+N" closes the popup and asks the menu bar to open the item list.
    private func showList() {
        close(reason: "list")
        requestItemList()
    }

    /// Asks the menu bar to open the item list. The menu bar does not listen for this yet.
    private func requestItemList() {}

    /// Only `http` and `https` links with a host are opened.
    private static func isOpenable(_ link: String) -> Bool {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return !(url.host() ?? "").isEmpty
    }

    // MARK: - Countdown

    private func startCountdown(at now: Date) {
        countdown = PopupCountdown(startingAt: now)
        // New content while the pointer is inside: the fresh countdown waits until the pointer leaves.
        if pointerIsInside {
            countdown?.pause(at: now)
        }
        scheduleCloseTimer(now: now)
    }

    private func pointerInside(_ inside: Bool) {
        pointerIsInside = inside
        guard showing != nil else { return }
        let now = Date()
        if inside {
            countdown?.pause(at: now)
        } else {
            countdown?.resume(at: now)
        }
        scheduleCloseTimer(now: now)
    }

    private func scheduleCloseTimer(now: Date) {
        closeTimer?.invalidate()
        closeTimer = nil
        guard let countdown, !countdown.isPaused else { return }
        closeTimer = Timer.scheduledTimer(withTimeInterval: countdown.remaining(at: now), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeTimerFired() }
        }
    }

    private func closeTimerFired() {
        let now = Date()
        guard let countdown else { return }
        if countdown.isExpired(at: now) {
            close(reason: "timeout")
        } else {
            scheduleCloseTimer(now: now)
        }
    }

    // MARK: - Debug

    #if DEBUG
    /// With `OSWIDGET_DEBUG_ANNOUNCE=<seconds>` set, announces one sample item after that many seconds,
    /// so the popup can be checked without the sync engine.
    private func scheduleDebugAnnouncement() {
        guard let value = ProcessInfo.processInfo.environment["OSWIDGET_DEBUG_ANNOUNCE"],
              let seconds = TimeInterval(value), seconds >= 0 else { return }
        Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                let now = Date()
                let item = Item(
                    id: "debug-\(UUID().uuidString.lowercased())",
                    kind: "notification",
                    source: "debug",
                    title: "Mục thử popup",
                    summary: "Mục mẫu do OSWIDGET_DEBUG_ANNOUNCE tạo.",
                    createdAt: now,
                    expiresAt: now.addingTimeInterval(3600)
                )
                self?.environment.store.announce([item])
            }
        }
    }
    #endif
}
