/// Applies the read and delete actions the widget writes to the shared inbox.
@MainActor
final class InboxWatcher {
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func start() {}
}
