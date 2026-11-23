import Foundation
import OSWidgetKit

/// Connects the sync engine to the app environment: the API client reads the Worker URL and the
/// Keychain token on every call, the Realtime socket reads the Supabase URL and key on every connect,
/// and system events, user actions and Realtime signals trigger sync rounds. The popup needs no wiring:
/// it observes the store's announcements.
@MainActor
enum SyncWiring {
    private static var runtime: SyncRuntime?

    static func start(env: AppEnvironment) {
        guard runtime == nil else { return }
        let runtime = SyncRuntime(env: env)
        runtime.start()
        self.runtime = runtime
    }
}

/// Everything that must stay alive while the app syncs.
@MainActor
private final class SyncRuntime {
    /// A sleep longer than this may have outlived the 30 days of kept events, so the next round
    /// reconciles with `GET /items`.
    static let longSleep: TimeInterval = 24 * 60 * 60

    private let config: AppConfig
    private let engine: SyncEngine
    private let realtime: RealtimeSignal
    private let queueWatcher: QueueWatcher
    private var systemTriggers: SystemTriggers?
    private var listenTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var settings: Settings

    private struct Settings: Equatable {
        let workerURL: URL?
        let supabaseURL: URL?
        let publishableKey: String?

        init(_ config: AppConfig) {
            workerURL = config.workerURL
            supabaseURL = config.supabaseURL
            publishableKey = config.supabasePublishableKey
        }
    }

    init(env: AppEnvironment) {
        let config = env.config
        let tokenStore = env.tokenStore
        self.config = config
        settings = Settings(config)

        let api = APIClient(credentials: {
            guard let workerURL = config.workerURL,
                  let token = try? tokenStore.read(), !token.isEmpty
            else { return nil }
            return ServerCredentials(workerURL: workerURL, clientToken: token)
        })
        let engine = SyncEngine(api: api, store: env.store)
        self.engine = engine
        realtime = RealtimeSignal(connect: {
            guard let supabaseURL = config.supabaseURL,
                  let key = config.supabasePublishableKey,
                  let url = RealtimeSignal.socketURL(supabaseURL: supabaseURL, publishableKey: key)
            else { return nil }
            return URLSessionWebSocket(url: url)
        })
        queueWatcher = QueueWatcher(store: env.store) { engine.trigger() }
    }

    func start() {
        let engine = engine
        let realtime = realtime

        listenTask = Task { await engine.listen(to: realtime) }
        Task { await realtime.start() }
        queueWatcher.start()

        let triggers = SystemTriggers(
            onSync: { engine.trigger() },
            onWillSleep: { Task { await realtime.stop() } },
            onDidWake: { slept in
                Task {
                    if slept > Self.longSleep {
                        await engine.requestReconcile()
                    }
                    await realtime.start()
                    await engine.sync()
                }
            }
        )
        triggers.start()
        systemTriggers = triggers

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsMayHaveChanged() }
        }

        engine.trigger()
    }

    /// Reconnects Realtime and syncs when the operator changed a server setting.
    private func settingsMayHaveChanged() {
        let current = Settings(config)
        guard current != settings else { return }
        settings = current
        let engine = engine
        let realtime = realtime
        Task {
            await realtime.stop()
            await realtime.start()
            await engine.sync()
        }
    }
}
