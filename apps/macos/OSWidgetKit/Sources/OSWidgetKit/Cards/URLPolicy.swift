import Foundation

/// Which URLs from item content the app may open or load. Content comes from senders and is treated as
/// data (architecture §7): the server only checks a URL's prefix, so `https://` with no host can reach
/// the client and is refused here.
public enum URLPolicy {
    /// True for an `http` or `https` URL with a non-empty host. Such a URL may be opened in the browser
    /// when the user clicks it.
    public static func isOpenable(_ url: URL) -> Bool {
        hasHost(url) && ["http", "https"].contains(url.scheme?.lowercased())
    }

    /// True for an `https` URL with a non-empty host. Only such a URL may be loaded (images).
    public static func isLoadable(_ url: URL) -> Bool {
        hasHost(url) && url.scheme?.lowercased() == "https"
    }

    /// The URL in `string` when it is openable, else `nil`.
    public static func openableURL(_ string: String?) -> URL? {
        parse(string).flatMap { isOpenable($0) ? $0 : nil }
    }

    /// The URL in `string` when it is loadable, else `nil`.
    public static func loadableURL(_ string: String?) -> URL? {
        parse(string).flatMap { isLoadable($0) ? $0 : nil }
    }

    private static func parse(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
        return URL(string: string)
    }

    private static func hasHost(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false) else { return false }
        return !host.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
