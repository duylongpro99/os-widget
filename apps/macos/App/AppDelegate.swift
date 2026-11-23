import AppKit

/// Entry point of the menu bar agent. It builds the shared environment and starts the three parts of
/// the app (sync, menu bar, popup); everything else lives in those parts.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var menuBar: MenuBarController?
    private var popup: PopupController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.anotherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }
        let env = AppEnvironment.live()
        SyncWiring.start(env: env)
        let menuBar = MenuBarController(env: env)
        popup = PopupController(
            env: env,
            anchor: { [weak menuBar] in menuBar?.anchorRect() },
            isListOpen: { [weak menuBar] in menuBar?.isListOpen ?? false }
        )
        self.menuBar = menuBar
        environment = env
    }

    private static func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != current }
    }
}
