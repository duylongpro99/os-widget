import SwiftUI

/// The small view of an item, for the widget: a title, one short plain-text detail, the source and the
/// time. It never loads images and never renders markdown, so it stays cheap to draw.
///
/// Adding a kind takes one `ItemContent` case, one `Variant` case and one view in this folder.
public struct CompactCardView: View {
    public let item: Item
    /// The most lines the detail text may use.
    public let lines: Int

    public init(item: Item, lines: Int = 2) {
        self.item = item
        self.lines = lines
    }

    /// Which compact view renders a given content. Unknown content, including kinds without a compact
    /// view yet such as `vocab`, uses the fallback.
    public enum Variant: Sendable, Hashable {
        case notification
        case generic
        case fallback
    }

    public nonisolated static func variant(for content: ItemContent) -> Variant {
        switch content {
        case .notification: .notification
        case .generic: .generic
        case .unknown: .fallback
        }
    }

    /// The plain-text detail line shown under the title, or `nil` when there is nothing to show.
    ///
    /// - `notification`: the first non-empty line of `text`, else the summary.
    /// - `generic`: the text of the first `heading` or `text` block, else the summary. Other blocks are
    ///   skipped.
    /// - anything else: the summary.
    ///
    /// Markdown is returned as typed, never interpreted.
    public nonisolated static func detail(for item: Item) -> String? {
        let candidate: String? = switch item.content {
        case .notification(let text):
            text.flatMap { $0.split(whereSeparator: \.isNewline).lazy.map(Self.trimmed).first { !$0.isEmpty } }
        case .generic(let blocks):
            blocks.lazy.compactMap { block -> String? in
                switch block {
                case .heading(let text): Self.trimmed(text[...])
                case .text(let markdown): Self.trimmed(markdown[...])
                default: nil
                }
            }.first { !$0.isEmpty }
        case .unknown:
            nil
        }
        if let candidate, !candidate.isEmpty { return candidate }
        let summary = trimmed(item.summary[...])
        return summary.isEmpty ? nil : summary
    }

    private nonisolated static func trimmed(_ text: Substring) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        switch Self.variant(for: item.content) {
        case .notification:
            CompactNotificationView(item: item, lines: lines)
        case .generic:
            CompactGenericView(item: item, lines: lines)
        case .fallback:
            CompactFallbackView(item: item, lines: lines)
        }
    }
}

/// The layout every compact view shares: title, optional detail, then source and time. Read items use
/// the secondary colour and a regular weight.
struct CompactCardLayout: View {
    let item: Item
    let detail: String?
    let lines: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: item.title)
                .font(.subheadline)
                .fontWeight(item.isRead ? .regular : .semibold)
                .foregroundStyle(item.isRead ? .secondary : .primary)
                .lineLimit(1)
            if let detail, lines > 0 {
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(item.isRead ? .tertiary : .secondary)
                    .lineLimit(lines)
            }
            CompactCardFooter(item: item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Source and time. The time is drawn by the system as a relative date, so it stays current without a
/// widget reload.
struct CompactCardFooter: View {
    let item: Item

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: item.source)
            Text(verbatim: "·")
            Text(item.createdAt, style: .relative)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
}
