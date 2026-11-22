import AppKit
import WidgetKit

enum AppGroup {
    static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""
    static var defaults: UserDefaults? { UserDefaults(suiteName: id) }
    static let lastWriteKey = "lastWrite"
    static let reloadLogKey = "reloadLog"
}

@main
@MainActor
final class ProbeApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel?

    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Probe"
        let menu = NSMenu()
        menu.addItem(item("Ghi dữ liệu", #selector(writeData)))
        menu.addItem(item("Mở panel sau 10 giây", #selector(openPanelLater)))
        menu.addItem(item("Ghi log reload", #selector(logReload)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "App Group: \(AppGroup.id)", action: nil, keyEquivalent: ""))
        menu.addItem(item("Thoát", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private static func now() -> String {
        ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
    }

    @objc private func writeData() {
        AppGroup.defaults?.set(Self.now(), forKey: AppGroup.lastWriteKey)
        reload()
    }

    @objc private func logReload() {
        reload()
    }

    /// Reloads widget timelines and appends the time of the call to the App Group log.
    private func reload() {
        if let defaults = AppGroup.defaults {
            var log = defaults.stringArray(forKey: AppGroup.reloadLogKey) ?? []
            log.append(Self.now())
            defaults.set(log, forKey: AppGroup.reloadLogKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    @objc private func openPanelLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.showPanel()
        }
    }

    /// Shows a non-activating panel without activating the app, so keyboard focus stays where it was.
    private func showPanel() {
        let panel = self.panel ?? {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
                styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow],
                backing: .buffered, defer: false)
            p.title = "Probe panel"
            p.level = .floating
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "Panel mở lúc \(Self.now())")
            label.frame = NSRect(x: 20, y: 50, width: 280, height: 20)
            p.contentView?.addSubview(label)
            return p
        }()
        (panel.contentView?.subviews.first as? NSTextField)?.stringValue = "Panel mở lúc \(Self.now())"
        panel.center()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
