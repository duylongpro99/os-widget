import Foundation
import Synchronization
import Testing
@testable import OSWidgetKit

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func items() throws -> ItemsResponse {
        try ServerJSON.makeDecoder().decode(ItemsResponse.self, from: data("items"))
    }

    static func events() throws -> [ServerEvent] {
        try ServerJSON.makeDecoder().decode([ServerEvent].self, from: data("events"))
    }
}

/// A fresh directory under the system temporary directory, removed by `remove()`. Tests never use the
/// App Group container.
struct TempStoreDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appending(path: "oswidget-store-tests-\(UUID().uuidString)")
    }

    var location: StoreLocation { StoreLocation(baseDirectory: url) }
    var storeFile: URL { url.appending(path: ItemStore.fileName) }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A clock tests can move.
final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ date: Date = TestData.now) {
        current = Mutex(date)
    }

    var now: Date { current.withLock { $0 } }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }

    var function: @Sendable () -> Date { { [self] in now } }
}

enum TestData {
    static let now = ServerJSON.parseDate("2026-11-23T10:00:00.000000+00:00")!

    static func item(
        _ id: String,
        kind: String = "notification",
        createdSecondsAgo: TimeInterval = 60,
        expiresIn: TimeInterval? = 3600,
        read: Bool = false,
        deleted: Bool = false
    ) -> Item {
        let created = now.addingTimeInterval(-createdSecondsAgo)
        return Item(
            id: id,
            kind: kind,
            source: "test",
            title: "title \(id)",
            summary: "summary \(id)",
            createdAt: created,
            expiresAt: expiresIn.map { now.addingTimeInterval($0) },
            readAt: read ? created.addingTimeInterval(1) : nil,
            deletedAt: deleted ? created.addingTimeInterval(2) : nil
        )
    }

    static func created(_ seq: Int64, _ item: Item?, id: String? = nil) -> ServerEvent {
        ServerEvent(seq: seq, type: .created, itemId: item?.id ?? id ?? "missing", item: item, createdAt: item?.createdAt)
    }

    static func event(_ seq: Int64, _ type: ServerEvent.EventType, _ id: String) -> ServerEvent {
        ServerEvent(seq: seq, type: type, itemId: id, createdAt: now.addingTimeInterval(TimeInterval(seq) - 1000))
    }
}

/// Everything the store persists, for comparing two stores.
struct StoreSnapshot: Equatable {
    let items: [Item]
    let cursor: Int64?
    let queue: [PendingAction]
    let popupSettings: PopupSettings
    let lastFullSyncAt: Date?

    @MainActor
    init(_ store: ItemStore) {
        items = store.items.sorted { $0.id < $1.id }
        cursor = store.cursor
        queue = store.queue
        popupSettings = store.popupSettings
        lastFullSyncAt = store.lastFullSyncAt
    }
}
