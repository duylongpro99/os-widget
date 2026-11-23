import Foundation
import ServiceManagement
import os

/// Starts the app at login through `SMAppService.mainApp`. It is enabled on the first launch; after
/// that only the user's choice in the menu changes it.
@MainActor
enum LaunchAtLogin {
    private static let configuredKey = "launchAtLoginConfigured"
    private static let log = Logger(subsystem: "local.oswidget.app", category: "login")

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    /// Registers the app once, on the first launch. Later launches leave the user's choice alone.
    static func enableOnFirstLaunch(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: configuredKey) else { return }
        defaults.set(true, forKey: configuredKey)
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            log.info("login.set enabled=\(enabled, privacy: .public) status=\(String(describing: status), privacy: .public)")
        } catch {
            log.error("login.set_failed enabled=\(enabled, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
