import Foundation

/// The on-disk form of `store.json`.
///
/// `ItemStore` is the only writer; `StoreReader` reads the same file from another process. Items and
/// queued actions decode leniently: one malformed entry is dropped instead of losing the whole file.
/// The keys and `version` are a contract with every installed build of the app, so they never change
/// without a new version number.
struct StoreFile: Codable {
    static let fileName = "store.json"

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

    /// The file inside a store directory.
    static func url(in directory: URL) -> URL {
        directory.appending(path: fileName)
    }

    static func decode(_ data: Data) throws -> StoreFile {
        try ServerJSON.makeDecoder().decode(StoreFile.self, from: data)
    }

    func encoded() throws -> Data {
        try ServerJSON.makeEncoder().encode(self)
    }
}
