import SwiftUI

/// Shared size of a card, so the item list and the popup show cards the same way.
public enum CardMetrics {
    public static let width: CGFloat = 340
    public static let padding: CGFloat = 12
    public static let imageMaxHeight: CGFloat = 160
}

/// The view shown for an item. Adding a kind takes one `ItemContent` case, one `Variant` case and one
/// view.
public struct CardView: View {
    public let item: Item

    public init(item: Item) {
        self.item = item
    }

    /// Which view renders a given content. Unknown content, including kinds without a view yet such as
    /// `vocab`, uses the fallback card.
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

    public var body: some View {
        Group {
            switch item.content {
            case .notification(let text):
                NotificationCardView(item: item, text: text)
            case .generic(let blocks):
                GenericCardView(item: item, blocks: blocks)
            case .unknown:
                FallbackCardView(item: item)
            }
        }
        .padding(CardMetrics.padding)
        .frame(width: CardMetrics.width, alignment: .leading)
    }
}

/// Title row and footer shared by every card.
struct CardHeader: View {
    let item: Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.title)
                .font(.headline)
                .fontWeight(item.isRead ? .regular : .semibold)
                .lineLimit(2)
            Spacer(minLength: 4)
            if URLPolicy.openableURL(item.url) != nil {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Có liên kết")
            }
        }
    }
}

struct CardFooter: View {
    let item: Item

    var body: some View {
        HStack(spacing: 4) {
            Text(item.source)
            Text("·")
            Text(item.createdAt, format: .relative(presentation: .named))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

struct CardSummary: View {
    let item: Item

    var body: some View {
        if !item.summary.isEmpty {
            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}
