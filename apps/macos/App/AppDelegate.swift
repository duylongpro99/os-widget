import AppKit

/// Entry point of the menu bar agent. It builds the shared environment and starts the parts of the app
/// (sync, widget wiring, menu bar, popup); everything else lives in those parts.
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
        app.mainMenu = EditMenu.makeMainMenu()
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.anotherInstanceIsRunning() {
            NSApp.terminate(nil)
            return
        }
        let env = AppEnvironment.live()
        SyncWiring.start(env: env)
        WidgetWiring.start(env: env)
        let menuBar = MenuBarController(env: env)
        popup = PopupController(
            env: env,
            anchor: { [weak menuBar] in menuBar?.anchorRect() },
            isListOpen: { [weak menuBar] in menuBar?.isListOpen ?? false }
        )
        self.menuBar = menuBar
        environment = env
    }

    /// True when an older instance is running. Comparing launch order means two instances started at
    /// the same moment do not both quit: only the newer one does.
    private static func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { other in
            other.processIdentifier != current.processIdentifier && !other.isTerminated
                && launchedEarlier(other, than: current)
        }
    }

    private static func launchedEarlier(_ other: NSRunningApplication, than current: NSRunningApplication) -> Bool {
        if let otherDate = other.launchDate, let currentDate = current.launchDate, otherDate != currentDate {
            return otherDate < currentDate
        }
        return other.processIdentifier < current.processIdentifier
    }
}
