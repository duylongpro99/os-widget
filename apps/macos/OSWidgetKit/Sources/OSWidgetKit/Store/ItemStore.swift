import Foundation
import Observation

/// The local item store observed by the menu bar list and the popup.
///
/// It holds the items, the event cursor, the queue of user actions not yet sent, the popup settings and
/// the time of the last full sync, and persists them to one `store.json` in the `StoreLocation`
/// directory after every change. Every way of applying server state is idempotent (architecture §5):
/// applying the same or an overlapping page of events again gives the same result. After each one, the
/// actions still queued are applied again so unsent user actions are not overwritten by older server
/// state.
@MainActor
@Observable
public final class ItemStore {
    public nonisolated static let fileName = "store.json"

    /// Every stored item, including deleted ones not yet dropped by a full sync. Views use
    /// `visibleItems`.
    public private(set) var items: [Item] = []
    /// `seq` of the newest event applied, or `nil` before the first full sync.
    public private(set) var cursor: Int64?
    /// User actions applied locally and waiting to be sent, oldest first.
    public private(set) var queue: [PendingAction] = []
    public private(set) var popupSettings: PopupSettings = .default
    public private(set) var lastFullSyncAt: Date?
    /// The latest batch of new items for the popup. Not persisted.
    public private(set) var announcement: Announcement?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Creates a store backed by `store.json` in `location`, loading it when present. A file that cannot
    /// be read starts an empty store with no cursor, so the next sync starts from scratch. With a `nil`
    /// location the store keeps everything in memory only.
    public init(location: StoreLocation?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        guard let location else {
            fileURL = nil
            return
        }
        do {
            fileURL = try location.directory().appending(path: Self.fileName)
        } catch {
            Log.store.error("store.directory_failed error=\(String(describing: error), privacy: .public)")
            fileURL = nil
            return
        }
        load()
    }

    /// An in-memory store.
    public convenience init() {
        self.init(location: nil)
    }

    /// The store the running app uses, in the App Group container. When the container is unavailable
    /// the store runs in memory and syncs from scratch on every launch.
    public static func live() -> ItemStore {
        do {
            return ItemStore(location: try StoreLocation.appGroup())
        } catch {
            Log.store.error("store.location_unavailable error=\(String(describing: error), privacy: .public)")
            return ItemStore(location: nil)
        }
    }

    // MARK: - Reading

    /// Items to show: not deleted, not expired, newest first.
    public var visibleItems: [Item] {
        let now = now()
        return items.filter { $0.isVisible(at: now) }.sorted(by: Self.newestFirst)
    }

    public var unreadCount: Int {
        let now = now()
        return items.count(where: { $0.isVisible(at: now) && !$0.isRead })
    }

    public func item(id: String) -> Item? {
        items.first { $0.id == id }
    }

    // MARK: - Applying server state

    /// Applies one page of `GET /events` in order and returns the items that are new to the store and,
    /// after the whole page, still unread and visible, newest first. An item created and then read or
    /// deleted within the page is not returned. Events for unknown items (other than `item.created`) and
    /// events of unknown types are ignored; `item.created` without an item is ignored. The cursor only
    /// moves forward, to the largest `seq` in the page.
    @discardableResult
    public func apply(events: [ServerEvent]) -> [Item] {
        guard !events.isEmpty else { return [] }
        let knownBefore = Set(items.map(\.id))
        var created: Set<String> = []
        var index = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })

        for event in events.sorted(by: { $0.seq < $1.seq }) {
            switch event.type {
            case .created:
                guard let item = event.item else { continue }
                if let position = index[item.id] {
                    items[position] = item
                } else {
                    index[item.id] = items.count
                    items.append(item)
                }
                created.insert(item.id)
            case .read:
                guard let position = index[event.itemId], items[position].readAt == nil else { continue }
                items[position].readAt = event.createdAt ?? now()
            case .unread:
                guard let position = index[event.itemId] else { continue }
                items[position].readAt = nil
            case .deleted:
                guard let position = index[event.itemId], items[position].deletedAt == nil else { continue }
                items[position].deletedAt = event.createdAt ?? now()
            case .other:
                continue
            }
        }

        if let maxSeq = events.map(\.seq).max() {
            cursor = max(cursor ?? maxSeq, maxSeq)
        }
        reapplyQueue()

        let now = now()
        let fresh = items.filter {
            created.contains($0.id) && !knownBefore.contains($0.id) && $0.isVisible(at: now) && !$0.isRead
        }
        save()
        return fresh.sorted(by: Self.newestFirst)
    }

    /// Replaces the stored items with the full list from `GET /items` (first sync and periodic
    /// reconciliation). Items missing from the list are dropped; the others take the server's state.
    /// The cursor becomes `max(cursor, seq)`. Nothing is returned for the popup.
    public func replaceAll(items serverItems: [Item], seq: Int64) {
        var seen: Set<String> = []
        items = serverItems.filter { seen.insert($0.id).inserted }
        cursor = max(cursor ?? seq, seq)
        lastFullSyncAt = now()
        reapplyQueue()
        save()
    }

    /// Publishes new items for the popup. Called once per sync round; an empty list is ignored.
    public func announce(_ newItems: [Item]) {
        guard !newItems.isEmpty else { return }
        announcement = Announcement(
            serial: (announcement?.serial ?? 0) + 1,
            items: newItems.sorted(by: Self.newestFirst)
        )
    }

    // MARK: - User actions

    public func markRead(_ id: String) {
        enqueue(itemId: id, operation: .read(true))
    }

    public func markUnread(_ id: String) {
        enqueue(itemId: id, operation: .read(false))
    }

    public func delete(_ id: String) {
        enqueue(itemId: id, operation: .delete)
    }

    /// Records the result of sending `action`. Done and rejected actions leave the queue; an action that
    /// was replaced while it was being sent is left alone.
    public func complete(_ action: PendingAction, outcome: QueueOutcome) {
        if outcome == .rejected {
            Log.store.error("store.action_rejected id=\(action.itemId, privacy: .public)")
        }
        guard outcome.removesAction, let position = queue.firstIndex(where: { $0.id == action.id }) else { return }
        queue.remove(at: position)
        save()
    }

    // MARK: - Popup settings

    public func setPopup(kind: String, enabled: Bool) {
        popupSettings.setKind(kind, enabled: enabled)
        save()
    }

    public func setQuietMode(_ on: Bool) {
        popupSettings.quietMode = on
        save()
    }

    // MARK: - Queue

    private func enqueue(itemId: String, operation: PendingAction.Operation) {
        guard item(id: itemId) != nil else { return }
        let pending = queue.filter { $0.itemId == itemId }
        switch operation {
        case .delete:
            if pending.contains(where: { $0.operation == .delete }) { return }
            queue.removeAll { $0.itemId == itemId }
        case .read:
            // Delete wins over read: nothing to send after a delete.
            if pending.contains(where: { $0.operation == .delete }) { return }
            queue.removeAll { $0.itemId == itemId }
        }
        queue.append(PendingAction(itemId: itemId, operation: operation, createdAt: now()))
        reapplyQueue()
        save()
    }

    private func reapplyQueue() {
        for action in queue {
            guard let position = items.firstIndex(where: { $0.id == action.itemId }) else { continue }
            switch action.operation {
            case .read(true):
                if items[position].readAt == nil { items[position].readAt = action.createdAt }
            case .read(false):
                items[position].readAt = nil
            case .delete:
                if items[position].deletedAt == nil { items[position].deletedAt = action.createdAt }
            }
        }
    }

    // MARK: - Persistence

    private struct StoreFile: Codable {
        var version = 1
        var cursor: Int64?
        var items: [Item]
        var queue: [PendingAction]
        var popupSettings: PopupSettings
        var lastFullSyncAt: Date?

        enum CodingKeys: String, CodingKey {
            case version, cursor, items, queue
            case popupSettings = "popup_settings"
            case lastFullSyncAt = "last_full_sync_at"
        }

        init(cursor: Int64?, items: [Item], queue: [PendingAction], popupSettings: PopupSettings, lastFullSyncAt: Date?) {
            self.cursor = cursor
            self.items = items
            self.queue = queue
            self.popupSettings = popupSettings
            self.lastFullSyncAt = lastFullSyncAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decode(Int.self, forKey: .version)
            cursor = try c.decodeIfPresent(Int64.self, forKey: .cursor)
            items = try c.decode(LossyArray<Item>.self, forKey: .items).elements
            queue = try c.decode(LossyArray<PendingAction>.self, forKey: .queue).elements
            popupSettings = try c.decodeIfPresent(PopupSettings.self, forKey: .popupSettings) ?? .default
            lastFullSyncAt = try c.decodeIfPresent(Date.self, forKey: .lastFullSyncAt)
        }
    }

    private func load() {
        guard let fileURL else { return }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return
        } catch {
            Log.store.error("store.read_failed error=\(String(describing: error), privacy: .public)")
            return
        }
        do {
            let file = try ServerJSON.makeDecoder().decode(StoreFile.self, from: data)
            items = file.items
            cursor = file.cursor
            queue = file.queue
            popupSettings = file.popupSettings
            lastFullSyncAt = file.lastFullSyncAt
        } catch {
            Log.store.error("store.file_corrupt starting_empty=true")
        }
    }

    /// Writes the store atomically. Expired items are dropped from memory and file first.
    private func save() {
        let now = now()
        items.removeAll { $0.isExpired(at: now) }
        guard let fileURL else { return }
        let file = StoreFile(cursor: cursor, items: items, queue: queue, popupSettings: popupSettings, lastFullSyncAt: lastFullSyncAt)
        do {
            let data = try ServerJSON.makeEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.store.error("store.write_failed error=\(String(describing: error), privacy: .public)")
        }
    }

    private static func newestFirst(_ a: Item, _ b: Item) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id > b.id
    }
}

/// A batch of new items for the popup. `serial` grows with every announcement so observers can tell two
/// announcements with the same items apart.
public struct Announcement: Sendable, Hashable {
    public let serial: Int
    /// Newest first.
    public let items: [Item]

    public init(serial: Int, items: [Item]) {
        self.serial = serial
        self.items = items
    }
}
