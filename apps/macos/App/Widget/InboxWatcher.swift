import Foundation
import OSLog
import OSWidgetKit

/// Applies the read and delete actions the widget writes to the shared inbox.
///
/// It drains once at start for taps made while the app was not running, then on every change to the
/// inbox directory's file list (each action lands there by a rename), and every 60 s in case an event
/// was missed. Events within 200 ms of each other drain once. Draining goes through
/// `ItemStore.drain`, so the actions take the same queue rules as the app's own buttons and
/// `QueueWatcher` sends them on the next sync round.
@MainActor
final class InboxWatcher {
    private static let logger = Logger(subsystem: "local.oswidget.app", category: "widget")
    private static let coalesceWindow: Duration = .milliseconds(200)
    private static let sweepInterval: Duration = .seconds(60)

    private let env: AppEnvironment
    private var inbox: ActionInbox?
    private var source: DispatchSourceFileSystemObject?
    private var pendingDrain: Task<Void, Never>?
    private var sweep: Task<Void, Never>?
    private var started = false

    init(env: AppEnvironment) {
        self.env = env
    }

    func start() {
        guard !started else { return }
        started = true
        // Without the App Group container the store lives in memory and the widget has no inbox to write.
        guard let location = try? StoreLocation.appGroup() else {
            Self.logger.notice("widget.inbox_disabled reason=no_container")
            return
        }
        let inbox = ActionInbox(location: location)
        self.inbox = inbox
        drain()
        watch(inbox.directory)
        sweep = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sweepInterval)
                guard !Task.isCancelled, let self else { return }
                self.drain()
            }
        }
    }

    // Cancelling the source is what closes its file descriptor, so a watcher that goes away without
    // `stop()` must still cancel it.
    isolated deinit {
        stop()
    }

    func stop() {
        started = false
        source?.cancel()
        source = nil
        pendingDrain?.cancel()
        pendingDrain = nil
        sweep?.cancel()
        sweep = nil
    }

    /// Watches the directory itself: a file renamed into it changes the directory and fires `.write`.
    private func watch(_ directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("widget.inbox_watch_failed reason=create error=\(String(describing: error), privacy: .public)")
            return
        }
        let descriptor = open(directory.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            Self.logger.error("widget.inbox_watch_failed reason=open errno=\(errno, privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.directoryChanged() }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }

    /// The first event opens a 200 ms window; events inside it ride along with the one drain at its end.
    private func directoryChanged() {
        guard pendingDrain == nil else { return }
        pendingDrain = Task { [weak self] in
            try? await Task.sleep(for: Self.coalesceWindow)
            guard !Task.isCancelled else { return }
            self?.pendingDrain = nil
            self?.drain()
        }
    }

    private func drain() {
        guard started, let inbox else { return }
        let count = env.store.drain(inbox)
        if count > 0 {
            Self.logger.notice("widget.inbox_drained count=\(count, privacy: .public)")
        }
    }
}
