import AppIntents
import Foundation
import OSWidgetKit
import os

/// Marks one item read from its widget row. Runs in the widget extension: it only leaves the action in
/// the shared inbox for the app to apply, and WidgetKit reloads the timeline once it returns.
struct MarkItemReadIntent: AppIntent {
    static let title: LocalizedStringResource = "Đánh dấu đã đọc"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Mục")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        try ItemIntentInbox.submit(itemID: itemID, operation: .markRead)
        return .result()
    }
}

/// Deletes one item from its widget row, through the shared inbox like `MarkItemReadIntent`.
struct DeleteItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Xoá"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Mục")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        try ItemIntentInbox.submit(itemID: itemID, operation: .delete)
        return .result()
    }
}

/// The one path both intents take to the inbox, so each tap leaves exactly one log line: a `notice`
/// that the action was written, or an error that it was not.
private enum ItemIntentInbox {
    private static let log = Logger(subsystem: "local.oswidget.app", category: "widget")

    static func submit(itemID: String, operation: WidgetAction.Operation) throws {
        let name = operation == .markRead ? "read" : "delete"
        do {
            let inbox = ActionInbox(location: try StoreLocation.appGroup())
            try inbox.submit(WidgetAction(itemId: itemID, operation: operation, createdAt: Date()))
        } catch {
            log.error("widget.intent_failed action=\(name, privacy: .public) id=\(itemID, privacy: .public) error=\(String(describing: error), privacy: .public)")
            throw error
        }
        log.notice("widget.intent action=\(name, privacy: .public) id=\(itemID, privacy: .public)")
    }
}
