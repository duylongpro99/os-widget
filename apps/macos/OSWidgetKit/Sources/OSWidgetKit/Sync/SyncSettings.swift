import Foundation

/// The server settings a running sync depends on. Comparing the settings before and after the operator
/// saves them tells what the change calls for. The token is kept only in memory and never logged.
public struct SyncSettings: Equatable, Sendable {
    public var workerURL: URL?
    public var clientToken: String?
    public var supabaseURL: URL?
    public var publishableKey: String?

    public init(workerURL: URL?, clientToken: String?, supabaseURL: URL?, publishableKey: String?) {
        self.workerURL = workerURL
        self.clientToken = clientToken
        self.supabaseURL = supabaseURL
        self.publishableKey = publishableKey
    }

    public enum Change: Equatable, Sendable {
        case none
        /// The Worker URL or the client token changed: a round should run now, for example to send the
        /// actions kept after a 401.
        case sync
        /// The Supabase URL or key changed: Realtime connects again, then a round runs.
        case reconnectAndSync
    }

    /// What moving from these settings to `new` calls for.
    public func change(to new: SyncSettings) -> Change {
        if supabaseURL != new.supabaseURL || publishableKey != new.publishableKey {
            return .reconnectAndSync
        }
        if workerURL != new.workerURL || clientToken != new.clientToken {
            return .sync
        }
        return .none
    }
}
