import AppKit

/// Owns the menu bar icon. For now its menu only opens settings and quits; the item list comes later.
@MainActor
final class MenuBarController: NSObject {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private lazy var settingsWindow = SettingsWindowController(env: environment)

    /// True while the item list is showing. The popup stays closed while it is.
    private(set) var isListOpen = false

    init(env: AppEnvironment) {
        environment = env
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "OS Widget")
        let menu = NSMenu()
        menu.addItem(item("Cài đặt…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Thoát OS Widget", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    /// The icon's frame in screen coordinates, or `nil` when the button is not on screen.
    func anchorRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
