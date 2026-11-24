import Foundation
import OSWidgetKit
import os
import WidgetKit

/// What the items widget draws at one point in time.
struct ItemsEntry: TimelineEntry {
    let date: Date
    /// `nil` when the shared store cannot be read: no App Group, no store yet, or an unreadable file.
    let snapshot: WidgetSnapshot?
}

/// Reads the store the app keeps in the App Group container, lays the actions still waiting in the
/// inbox over it, and hands WidgetKit one entry. It never writes anything.
struct ItemsProvider: TimelineProvider {
    private static let log = Logger(subsystem: "local.oswidget.app", category: "widget")

    func placeholder(in context: Context) -> ItemsEntry {
        ItemsEntry(date: Date(), snapshot: ItemsSamples.snapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (ItemsEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(Self.entry(size: WidgetSize(family: context.family), now: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ItemsEntry>) -> Void) {
        let size = WidgetSize(family: context.family)
        let entry = Self.entry(size: size, now: Date())
        let shown = entry.snapshot?.items ?? []
        Self.log.notice("widget.timeline family=\(size.rawValue, privacy: .public) items=\(shown.count, privacy: .public) unread=\(entry.snapshot?.unreadCount ?? 0, privacy: .public) top=\(shown.first?.id ?? "none", privacy: .public)")
        // An expiring item drops out when its time comes without the app asking for a reload.
        let policy: TimelineReloadPolicy = entry.snapshot?.nextExpiry.map { .after($0) } ?? .never
        completion(Timeline(entries: [entry], policy: policy))
    }

    /// The entry for `size` built from the shared store and the inbox.
    static func entry(size: WidgetSize, now: Date) -> ItemsEntry {
        let location: StoreLocation
        do {
            location = try StoreLocation.appGroup()
        } catch {
            log.error("widget.store_unavailable error=\(String(describing: error), privacy: .public)")
            return ItemsEntry(date: now, snapshot: nil)
        }
        guard let contents = StoreReader.read(location: location) else {
            return ItemsEntry(date: now, snapshot: nil)
        }
        let snapshot = WidgetSnapshot.make(
            items: contents.items,
            pending: ActionInbox(location: location).pending(),
            now: now,
            limit: size.rowLimit
        )
        return ItemsEntry(date: now, snapshot: snapshot)
    }
}

/// Fixed items for the widget gallery and placeholders, so neither reads a file.
enum ItemsSamples {
    static let snapshot: WidgetSnapshot = {
        let now = Date()
        let items = [
            Item(
                id: "sample-notification", kind: "notification", source: "deploy-bot",
                title: "Deploy xong", summary: "Worker đã lên bản mới",
                body: .object(["text": .string("Bản 0.3 đã chạy trên production.")]),
                createdAt: now.addingTimeInterval(-5 * 60)
            ),
            Item(
                id: "sample-generic", kind: "generic", source: "report-cron",
                title: "Báo cáo tuần", summary: "Tóm tắt số liệu",
                body: .object(["blocks": .array([
                    .object(["type": .string("heading"), "text": .string("Tuần này ổn định")]),
                ])]),
                createdAt: now.addingTimeInterval(-40 * 60)
            ),
            Item(
                id: "sample-vocab", kind: "vocab", source: "vocab-cron",
                title: "serendipity", summary: "(n.) sự tình cờ may mắn",
                createdAt: now.addingTimeInterval(-3 * 3600), readAt: now.addingTimeInterval(-3600)
            ),
        ]
        return WidgetSnapshot(items: items, unreadCount: 2, nextExpiry: nil)
    }()
}
