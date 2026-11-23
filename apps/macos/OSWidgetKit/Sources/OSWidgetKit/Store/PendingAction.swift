import Foundation

/// A user action applied to the local store and waiting to be sent to the server.
public struct PendingAction: Codable, Sendable, Hashable, Identifiable {
    public enum Operation: Codable, Sendable, Hashable {
        /// `PATCH /items/{id}` with `{"read": value}`.
        case read(Bool)
        /// `DELETE /items/{id}`.
        case delete
    }

    public let id: UUID
    /// The item id exactly as the server returned it; never normalised.
    public let itemId: String
    public let operation: Operation
    public let createdAt: Date

    public init(id: UUID = UUID(), itemId: String, operation: Operation, createdAt: Date) {
        self.id = id
        self.itemId = itemId
        self.operation = operation
        self.createdAt = createdAt
    }

    /// Decides what happens to an action after one send attempt. `status` is the HTTP status code, or
    /// `nil` when the request failed before a response (network error, timeout).
    public static func outcome(for status: Int?) -> QueueOutcome {
        guard let status else { return .retry }
        switch status {
        case 200..<300, 404:
            // 404: the item was deleted elsewhere or purged, so there is nothing left to change.
            return .done
        case 401, 403:
            return .stop
        case 408, 429, 500...:
            return .retry
        case 400..<500:
            return .rejected
        default:
            return .retry
        }
    }
}

/// The fate of a sent action.
public enum QueueOutcome: Sendable, Hashable {
    /// Finished; remove the action.
    case done
    /// The server refused the request as malformed; remove the action and log an error.
    case rejected
    /// The token is missing, wrong or of the wrong kind; keep the action and stop sending until the
    /// settings change.
    case stop
    /// Temporary failure; keep the action and try again on a later sync.
    case retry

    /// True when the action leaves the queue.
    public var removesAction: Bool {
        self == .done || self == .rejected
    }
}
