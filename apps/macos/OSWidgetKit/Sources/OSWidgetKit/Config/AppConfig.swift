import Foundation

/// Server settings the operator enters in the settings window: the Worker URL, the Supabase URL and the
/// Supabase publishable key. They live in the app's `UserDefaults`; the client token does not (see
/// `KeychainTokenStore`). Setting a value to `nil` removes it.
public struct AppConfig: @unchecked Sendable {
    enum Key {
        static let workerURL = "workerURL"
        static let supabaseURL = "supabaseURL"
        static let supabasePublishableKey = "supabasePublishableKey"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var workerURL: URL? {
        get { url(forKey: Key.workerURL) }
        nonmutating set { set(newValue?.absoluteString, forKey: Key.workerURL) }
    }

    public var supabaseURL: URL? {
        get { url(forKey: Key.supabaseURL) }
        nonmutating set { set(newValue?.absoluteString, forKey: Key.supabaseURL) }
    }

    public var supabasePublishableKey: String? {
        get { string(forKey: Key.supabasePublishableKey) }
        nonmutating set { set(newValue, forKey: Key.supabasePublishableKey) }
    }

    /// True when every value the sync engine needs from `UserDefaults` is present.
    public var isComplete: Bool {
        workerURL != nil && supabaseURL != nil && supabasePublishableKey != nil
    }

    /// Parses a URL typed by the user. Only `https` URLs with a host are accepted, plus `http` to this
    /// machine for a local server: the client token is sent to this URL and must not cross the network
    /// in clear text.
    public static func parseServerURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        switch scheme {
        case "https":
            return url
        case "http":
            return loopbackHosts.contains(host) ? url : nil
        default:
            return nil
        }
    }

    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

    private func string(forKey key: String) -> String? {
        guard let value = defaults.string(forKey: key), !value.isEmpty else { return nil }
        return value
    }

    private func url(forKey key: String) -> URL? {
        string(forKey: key).flatMap(URL.init(string:))
    }

    private func set(_ value: String?, forKey key: String) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
