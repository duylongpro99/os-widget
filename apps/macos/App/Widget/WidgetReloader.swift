/// Asks WidgetKit to reload the items widget when what the widget shows has changed.
@MainActor
final class WidgetReloader {
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func start() {}
}
