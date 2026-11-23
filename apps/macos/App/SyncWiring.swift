/// Connects the sync engine to the app environment. Starting sync does nothing until the engine exists.
@MainActor
enum SyncWiring {
    static func start(env: AppEnvironment) {}
}
