import AppKit
import OSWidgetKit
import SwiftUI

/// Items that arrived while the list was open, shown with an accent background for a few seconds.
@MainActor
@Observable
final class ItemListModel {
    static let highlightDuration: Duration = .seconds(4)

    private(set) var highlighted: Set<String> = []
    @ObservationIgnored private var clearTasks: [String: Task<Void, Never>] = [:]

    func highlight(_ ids: [String]) {
        for id in ids {
            highlighted.insert(id)
            clearTasks[id]?.cancel()
            clearTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: Self.highlightDuration)
                guard !Task.isCancelled else { return }
                self?.highlighted.remove(id)
                self?.clearTasks[id] = nil
            }
        }
    }

    func clear() {
        clearTasks.values.forEach { $0.cancel() }
        clearTasks = [:]
        highlighted = []
    }
}

/// The item list in the menu bar popover: newest first, unread items bold with a dot, read items dimmed.
/// Every action goes through the store; the sync engine sends the queued action.
struct ItemListView: View {
    static let height: CGFloat = 480

    let store: ItemStore
    let model: ItemListModel

    var body: some View {
        let items = store.visibleItems
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                Text("Chưa có mục nào")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            ItemRow(item: item, isHighlighted: model.highlighted.contains(item.id), store: store)
                            Divider()
                        }
                    }
                    .animation(.default, value: items.map(\.id))
                }
                .frame(height: Self.height)
            }
        }
        .frame(width: CardMetrics.width + 24)
    }

    private var header: some View {
        HStack {
            Text("OS Widget").font(.headline)
            Spacer()
            let unread = store.unreadCount
            if unread > 0 {
                Text("\(unread) chưa đọc").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ItemRow: View {
    let item: Item
    let isHighlighted: Bool
    let store: ItemStore

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Circle()
                .fill(item.isRead ? Color.clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, CardMetrics.padding + 5)
                .accessibilityLabel(item.isRead ? "" : "Chưa đọc")
            VStack(alignment: .leading, spacing: 0) {
                CardView(item: item)
                    .opacity(item.isRead ? 0.6 : 1)
                    .onCardClick(tap: open, link: openLink)
                HStack(spacing: 12) {
                    Spacer()
                    if !item.isRead {
                        Button("Đã đọc") { store.markRead(item.id) }
                    }
                    Button("Xoá", role: .destructive) { store.delete(item.id) }
                }
                .buttonStyle(.link)
                .font(.caption)
                .padding(.horizontal, CardMetrics.padding)
                .padding(.bottom, 8)
            }
        }
        .padding(.leading, 4)
        .background(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
        .animation(.easeOut(duration: 0.6), value: isHighlighted)
    }

    /// Clicking a card marks it read and opens its link when the link is allowed.
    private func open() {
        markRead()
        if let url = URLPolicy.openableURL(item.url) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Clicking a link inside the card marks it read and opens only that link, not the item's own url.
    private func openLink(_ url: URL) {
        markRead()
        NSWorkspace.shared.open(url)
    }

    private func markRead() {
        if !item.isRead {
            store.markRead(item.id)
        }
    }
}
