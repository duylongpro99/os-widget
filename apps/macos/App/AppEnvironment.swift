import OSWidgetKit

/// Shared objects handed to every part of the app: server settings, the Keychain token store and the
/// local item store.
@MainActor
final class AppEnvironment {
    let config: AppConfig
    let tokenStore: KeychainTokenStore
    let store: ItemStore

    init(config: AppConfig, tokenStore: KeychainTokenStore, store: ItemStore) {
        self.config = config
        self.tokenStore = tokenStore
        self.store = store
    }

    static func live() -> AppEnvironment {
        AppEnvironment(config: AppConfig(), tokenStore: KeychainTokenStore(), store: .live())
    }
}
