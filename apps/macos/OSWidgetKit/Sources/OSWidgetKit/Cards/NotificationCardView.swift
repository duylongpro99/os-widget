import SwiftUI

/// A `notification` item: title, summary, optional inline-markdown text, source and time.
public struct NotificationCardView: View {
    let item: Item
    let text: String?

    public init(item: Item, text: String?) {
        self.item = item
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(item: item)
            CardSummary(item: item)
            if let text, !text.isEmpty {
                Text(Markdown.attributed(text))
                    .font(.body)
                    .lineLimit(8)
            }
            CardFooter(item: item)
        }
    }
}
