import Foundation
import os

/// One row of the server's `items` table (architecture §4.3).
///
/// `kind` stays a plain string so an item of a kind this client does not know still decodes and shows
/// its `title` and `summary`. The raw `body` is kept as sent; `content` is what views render from it.
/// Only a missing or malformed field the row cannot do without (`id`, `kind`, `source`, `title`,
/// `summary`, `created_at`) makes the item fail to decode.
public struct Item: Sendable, Hashable, Identifiable {
    public let id: String
    public var kind: String
    public var source: String
    public var priority: String
    public var title: String
    public var summary: String
    public var url: String?
    public var body: JSONValue?
    public var dedupeKey: String?
    public var createdAt: Date
    public var expiresAt: Date?
    public var readAt: Date?
    public var deletedAt: Date?

    public init(
        id: String,
        kind: String,
        source: String,
        priority: String = "normal",
        title: String,
        summary: String,
        url: String? = nil,
        body: JSONValue? = nil,
        dedupeKey: String? = nil,
        createdAt: Date,
        expiresAt: Date? = nil,
        readAt: Date? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.source = source
        self.priority = priority
        self.title = title
        self.summary = summary
        self.url = url
        self.body = body
        self.dedupeKey = dedupeKey
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.readAt = readAt
        self.deletedAt = deletedAt
    }

    /// What a view renders for this item, decoded from `kind` and `body`.
    public var content: ItemContent {
        ItemContent(kind: kind, body: body)
    }

    public var isRead: Bool { readAt != nil }
    public var isDeleted: Bool { deletedAt != nil }

    public func isExpired(at now: Date) -> Bool {
        expiresAt.map { $0 <= now } ?? false
    }

    /// Shown in lists and counted as unread: not deleted and not expired.
    public func isVisible(at now: Date) -> Bool {
        !isDeleted && !isExpired(at: now)
    }
}

extension Item: Codable {
    enum CodingKeys: String, CodingKey {
        case id, kind, source, priority, title, summary, url, body
        case dedupeKey = "dedupe_key"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case readAt = "read_at"
        case deletedAt = "deleted_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(String.self, forKey: .kind)
        source = try c.decode(String.self, forKey: .source)
        priority = try c.decodeIfPresent(String.self, forKey: .priority) ?? "normal"
        title = try c.decode(String.self, forKey: .title)
        summary = try c.decode(String.self, forKey: .summary)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        body = try c.decodeIfPresent(JSONValue.self, forKey: .body).flatMap { $0.isNull ? nil : $0 }
        dedupeKey = try? c.decodeIfPresent(String.self, forKey: .dedupeKey)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(source, forKey: .source)
        try c.encode(priority, forKey: .priority)
        try c.encode(title, forKey: .title)
        try c.encode(summary, forKey: .summary)
        try c.encode(url, forKey: .url)
        try c.encode(body, forKey: .body)
        try c.encode(dedupeKey, forKey: .dedupeKey)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(expiresAt, forKey: .expiresAt)
        try c.encode(readAt, forKey: .readAt)
        try c.encode(deletedAt, forKey: .deletedAt)
    }
}

/// The renderable content of an item.
///
/// `vocab` decodes to `.unknown` until a vocab view exists. A body that does not match its kind also
/// becomes `.unknown`, so the item still shows with its `title` and `summary`.
public enum ItemContent: Sendable, Hashable {
    case notification(text: String?)
    case generic(blocks: [Block])
    case unknown

    public init(kind: String, body: JSONValue?) {
        switch kind {
        case "notification":
            switch body {
            case nil:
                self = .notification(text: nil)
            case .object(let object)?:
                switch object["text"] {
                case nil, .null?: self = .notification(text: nil)
                case .string(let text)?: self = .notification(text: text)
                default: self = .unknown
                }
            default:
                self = .unknown
            }
        case "generic":
            if let blocks = body?["blocks"]?.arrayValue {
                self = .generic(blocks: blocks.map(Block.init(json:)))
            } else {
                self = .unknown
            }
        default:
            self = .unknown
        }
    }
}

/// The body of `GET /items`. An item that fails to decode is dropped and logged; the rest still load.
public struct ItemsResponse: Decodable, Sendable {
    public let seq: Int64
    public let items: [Item]

    public init(seq: Int64, items: [Item]) {
        self.seq = seq
        self.items = items
    }

    enum CodingKeys: String, CodingKey { case seq, items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seq = try c.decode(Int64.self, forKey: .seq)
        items = try c.decode(LossyArray<Item>.self, forKey: .items).elements
    }
}

/// Decodes an array element by element, skipping and logging elements that fail.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(JSONValue.self)
                Log.model.error("model.decode_skipped type=\(String(describing: Element.self), privacy: .public) index=\(container.currentIndex - 1, privacy: .public) error=\(Self.describe(error), privacy: .public)")
            }
        }
        self.elements = elements
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return "\(type(of: error))" }
        switch error {
        case .keyNotFound(let key, _): return "missing \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "bad \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        @unknown default: return "decoding error"
        }
    }
}

enum Log {
    static let model = Logger(subsystem: "local.oswidget.app", category: "model")
    static let store = Logger(subsystem: "local.oswidget.app", category: "store")
    static let widget = Logger(subsystem: "local.oswidget.app", category: "widget")
}
