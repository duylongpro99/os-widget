import AppKit
import OSWidgetKit

/// The right-click menu of the menu bar icon: popup switches per kind, quiet mode, launch at login,
/// settings and quit. It is rebuilt every time it opens, so it always shows the current state.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    /// Kinds always listed, even before any item of that kind arrives.
    static let knownKinds = ["notification", "generic", "vocab"]

    let menu = NSMenu()
    private let store: ItemStore
    private let openSettings: () -> Void

    init(store: ItemStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
    }

    /// The known kinds, then every other kind of a stored item that is not deleted, sorted.
    static func kinds(in items: [Item]) -> [String] {
        let others = Set(items.filter { !$0.isDeleted }.map(\.kind)).subtracting(knownKinds)
        return knownKinds + others.sorted()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = store.popupSettings

        menu.addItem(.sectionHeader(title: "Popup tự mở"))
        for kind in Self.kinds(in: store.items) {
            let entry = item(kind, #selector(togglePopupKind(_:)))
            entry.representedObject = kind
            entry.state = settings.isEnabled(kind: kind) ? .on : .off
            entry.indentationLevel = 1
            menu.addItem(entry)
        }
        let quiet = item("Chế độ yên lặng", #selector(toggleQuietMode))
        quiet.state = settings.quietMode ? .on : .off
        menu.addItem(quiet)

        menu.addItem(.separator())
        let login = item("Mở khi đăng nhập", #selector(toggleLaunchAtLogin))
        switch LaunchAtLogin.status {
        case .enabled: login.state = .on
        case .requiresApproval: login.state = .mixed
        default: login.state = .off
        }
        menu.addItem(login)
        menu.addItem(item("Cài đặt…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Thoát OS Widget", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePopupKind(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? String else { return }
        store.setPopup(kind: kind, enabled: !store.popupSettings.isEnabled(kind: kind))
    }

    @objc private func toggleQuietMode() {
        store.setQuietMode(!store.popupSettings.quietMode)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.setEnabled(LaunchAtLogin.status != .enabled)
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
