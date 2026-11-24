/// Connects the widget to the app environment: one object asks WidgetKit to reload when the widget's
/// content changes, the other applies the actions the widget leaves in the shared inbox. Both live as
/// long as the app.
@MainActor
enum WidgetWiring {
    private static var reloader: WidgetReloader?
    private static var inboxWatcher: InboxWatcher?

    static func start(env: AppEnvironment) {
        guard reloader == nil else { return }
        let reloader = WidgetReloader(env: env)
        let inboxWatcher = InboxWatcher(env: env)
        reloader.start()
        inboxWatcher.start()
        self.reloader = reloader
        self.inboxWatcher = inboxWatcher
    }
}
