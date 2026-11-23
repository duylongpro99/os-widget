import SwiftUI

/// An item whose kind has no view, or whose body does not match its kind: title, summary, source and
/// time. It never reports an error.
public struct FallbackCardView: View {
    let item: Item

    public init(item: Item) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(item: item)
            CardSummary(item: item)
            CardFooter(item: item)
        }
    }
}
