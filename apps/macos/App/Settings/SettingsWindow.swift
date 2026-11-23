import AppKit
import OSWidgetKit
import SwiftUI

/// The settings window. Unlike the popup it activates the app, because the user opened it on purpose.
@MainActor
final class SettingsWindowController {
    private let environment: AppEnvironment
    private var window: NSWindow?

    init(env: AppEnvironment) {
        environment = env
    }

    func show() {
        let window: NSWindow
        if let existing = self.window {
            window = existing
            if !window.isVisible {
                // Reopening starts from the saved values: edits that were never saved, and the last
                // status message, are dropped with the old model.
                window.contentViewController = makeContent()
            }
        } else {
            window = makeWindow()
            self.window = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeContent() -> NSViewController {
        let model = SettingsModel(config: environment.config, tokenStore: environment.tokenStore)
        return NSHostingController(rootView: SettingsView(model: model))
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: makeContent())
        window.title = "Cài đặt OS Widget"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

@MainActor
@Observable
final class SettingsModel {
    var workerURL: String
    var token: String
    var supabaseURL: String
    var publishableKey: String
    private(set) var message: String?
    private(set) var isError = false

    private let config: AppConfig
    private let tokenStore: KeychainTokenStore

    init(config: AppConfig, tokenStore: KeychainTokenStore) {
        self.config = config
        self.tokenStore = tokenStore
        workerURL = config.workerURL?.absoluteString ?? ""
        supabaseURL = config.supabaseURL?.absoluteString ?? ""
        publishableKey = config.supabasePublishableKey ?? ""
        do {
            token = try tokenStore.read() ?? ""
        } catch {
            token = ""
            message = "Không đọc được token: \(error)"
            isError = true
        }
    }

    func save() {
        let worker = workerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let supabase = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard worker.isEmpty || AppConfig.parseServerURL(worker) != nil else {
            return fail("URL Worker phải là https://… (http chỉ dùng cho localhost).")
        }
        guard supabase.isEmpty || AppConfig.parseServerURL(supabase) != nil else {
            return fail("URL Supabase phải là https://… (http chỉ dùng cho localhost).")
        }
        do {
            try tokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return fail("Không lưu được token: \(error)")
        }
        config.workerURL = AppConfig.parseServerURL(worker)
        config.supabaseURL = AppConfig.parseServerURL(supabase)
        config.supabasePublishableKey = publishableKey
        message = "Đã lưu."
        isError = false
    }

    private func fail(_ text: String) {
        message = text
        isError = true
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            TextField("URL Worker", text: $model.workerURL, prompt: Text("https://…workers.dev"))
            SecureField("Token client", text: $model.token)
            TextField("URL Supabase", text: $model.supabaseURL, prompt: Text("https://….supabase.co"))
            TextField("Khoá publishable", text: $model.publishableKey, prompt: Text("sb_publishable_…"))
            HStack {
                if let message = model.message {
                    Text(message).foregroundStyle(model.isError ? .red : .secondary)
                }
                Spacer()
                Button("Lưu", action: model.save).keyboardShortcut(.defaultAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 460)
    }
}
