import AppKit
import OSWidgetKit
import SwiftUI
import os

extension Notification.Name {
    /// Posted on the main queue to show the item list, for example from the popup's "+N" row.
    static let openItemListRequested = Notification.Name("local.oswidget.open-item-list")
}

/// Owns the menu bar icon. A left click toggles the item list in a popover; a right click (or
/// control-click) opens the status menu. The icon shows `tray.full` while there are unread items.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let listModel = ItemListModel()
    private lazy var settingsWindow = SettingsWindowController(env: environment)
    private lazy var statusMenu = StatusMenu(store: environment.store) { [weak self] in
        self?.settingsWindow.show()
    }
    private var lastAnnouncementSerial: Int?
    private var openListObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    /// Watches clicks in other apps while the list shows; `nil` while it is closed.
    private var outsideClickMonitor: Any?
    private let log = Logger(subsystem: "local.oswidget.app", category: "menu")

    /// True while the item list is showing. The popup stays closed while it is.
    var isListOpen: Bool { popover.isShown }

    init(env: AppEnvironment) {
        environment = env
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        lastAnnouncementSerial = env.store.announcement?.serial

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let hosting = NSHostingController(rootView: ItemListView(store: env.store, model: listModel))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        openListObserver = NotificationCenter.default.addObserver(
            forName: .openItemListRequested, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.showList() }
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeList(.resignActive) }
        }
        observeStore()
        LaunchAtLogin.enableOnFirstLaunch()
    }

    /// The icon's frame in screen coordinates, or `nil` when the button is not on screen.
    func anchorRect() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    // MARK: - Clicks

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else if popover.isShown {
            closeList(.icon)
        } else {
            showList()
        }
    }

    private func showMenu() {
        closeList(.menu)
        statusItem.menu = statusMenu.menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func showList() {
        guard !popover.isShown, let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        log.info("list.shown active=\(NSApp.isActive, privacy: .public)")
        // A global monitor only sees events sent to other apps, so clicks in the list, the popup
        // and the settings window never reach it.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let iconFrame = self.anchorRect()
                if ItemListDismissal.closesList(clickAt: NSEvent.mouseLocation, iconFrame: iconFrame) {
                    self.closeList(.outsideClick)
                }
            }
        }
    }

    private func closeList(_ reason: ItemListDismissal.Reason) {
        guard popover.isShown else { return }
        log.info("list.closed reason=\(reason.rawValue, privacy: .public)")
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        listModel.clear()
    }

    // MARK: - Store observation

    /// Re-renders the icon when the unread count changes, and highlights items announced while the list
    /// is open. Observation fires once per registration, so each change registers again.
    private func observeStore() {
        let store = environment.store
        let (unread, announcement) = withObservationTracking {
            (store.unreadCount, store.announcement)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
        updateIcon(hasUnread: unread > 0)
        if let announcement, announcement.serial != lastAnnouncementSerial {
            lastAnnouncementSerial = announcement.serial
            if popover.isShown {
                listModel.highlight(announcement.items.map(\.id))
            }
        }
    }

    private func updateIcon(hasUnread: Bool) {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: hasUnread ? "tray.full" : "tray",
            accessibilityDescription: hasUnread ? "OS Widget, có mục chưa đọc" : "OS Widget"
        )
        image?.isTemplate = true
        button.image = image
    }
}
