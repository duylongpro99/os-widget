import Foundation

/// One entry of `GET /events` (architecture §4.1, §4.3).
///
/// `item` is present only on `item.created`, and is `nil` when the item has since been purged. An
/// `item` that fails to decode is treated the same way, so one bad row never blocks the cursor.
public struct ServerEvent: Sendable, Hashable {
    public enum EventType: Sendable, Hashable {
        case created
        case read
        case unread
        case deleted
        /// A type this client does not know; applying it changes nothing.
        case other(String)

        public init(rawValue: String) {
            switch rawValue {
            case "item.created": self = .created
            case "item.read": self = .read
            case "item.unread": self = .unread
            case "item.deleted": self = .deleted
            default: self = .other(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .created: "item.created"
            case .read: "item.read"
            case .unread: "item.unread"
            case .deleted: "item.deleted"
            case .other(let value): value
            }
        }
    }

    public let seq: Int64
    public let type: EventType
    public let itemId: String
    public let item: Item?
    /// When the server recorded the event; used as the read time of `item.read`.
    public let createdAt: Date?

    public init(seq: Int64, type: EventType, itemId: String, item: Item? = nil, createdAt: Date? = nil) {
        self.seq = seq
        self.type = type
        self.itemId = itemId
        self.item = item
        self.createdAt = createdAt
    }
}

extension ServerEvent: Decodable {
    enum CodingKeys: String, CodingKey {
        case seq, type, item
        case itemId = "item_id"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int64.self, forKey: .seq)
        type = EventType(rawValue: try c.decode(String.self, forKey: .type))
        itemId = try c.decode(String.self, forKey: .itemId)
        createdAt = try? c.decodeIfPresent(Date.self, forKey: .createdAt)
        do {
            item = try c.decodeIfPresent(Item.self, forKey: .item)
        } catch {
            let (seq, itemId) = (seq, itemId)
            Log.model.error("model.event_item_unreadable seq=\(seq, privacy: .public) id=\(itemId, privacy: .public)")
            item = nil
        }
    }
}
