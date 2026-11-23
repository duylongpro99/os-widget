import Foundation
import Security

/// Reads, writes and deletes the client token as a generic password in the Keychain.
/// The token never goes to `UserDefaults` or to disk.
public struct KeychainTokenStore: Sendable {
    public static let defaultService = "local.oswidget.app"
    public static let defaultAccount = "client-token"

    public let service: String
    public let account: String

    public init(service: String = defaultService, account: String = defaultAccount) {
        self.service = service
        self.account = account
    }

    /// Returns the stored token, or `nil` when there is none.
    public func read() throws(KeychainError) -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainError(status: errSecDecode)
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// Stores `token`, replacing any previous value. An empty token deletes the item.
    public func save(_ token: String) throws(KeychainError) {
        guard !token.isEmpty else { return try delete() }
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        default:
            throw KeychainError(status: update)
        }
    }

    /// Deletes the stored token. Deleting a missing token is not an error.
    public func delete() throws(KeychainError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public struct KeychainError: Error, Equatable, CustomStringConvertible {
    public let status: OSStatus

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}
