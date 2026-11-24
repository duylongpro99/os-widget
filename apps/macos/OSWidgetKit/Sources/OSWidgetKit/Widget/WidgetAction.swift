import Foundation

/// A tap on a widget button, handed from the widget to the app.
///
/// The type knows nothing about how it travels, so the same value can go through the action inbox or
/// any other channel between the two processes.
public struct WidgetAction: Codable, Sendable, Hashable, Identifiable {
    public enum Operation: String, Codable, Sendable, Hashable {
        case markRead = "mark_read"
        case delete
    }

    public let id: UUID
    /// The item id exactly as the server returned it; never normalised.
    public let itemId: String
    public let operation: Operation
    /// When the user tapped the button.
    public let createdAt: Date

    public init(id: UUID = UUID(), itemId: String, operation: Operation, createdAt: Date) {
        self.id = id
        self.itemId = itemId
        self.operation = operation
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, operation
        case itemId = "item_id"
        case createdAt = "created_at"
    }
}
