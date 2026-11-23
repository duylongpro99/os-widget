import SwiftUI

/// A `generic` item rendered block by block. Unsupported blocks are skipped; an image whose URL is not
/// loadable shows its alt text instead, and a link whose URL is not openable shows its label as text.
public struct GenericCardView: View {
    let item: Item
    let blocks: [Block]

    public init(item: Item, blocks: [Block]) {
        self.item = item
        self.blocks = blocks
    }

    /// The blocks that produce a view, in order.
    public nonisolated static func renderedBlocks(_ blocks: [Block]) -> [Block] {
        blocks.filter {
            switch $0 {
            case .unsupported: false
            case .image(let url, let alt): URLPolicy.loadableURL(url) != nil || !(alt ?? "").isEmpty
            default: true
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(item: item)
            CardSummary(item: item)
            ForEach(Array(Self.renderedBlocks(blocks).enumerated()), id: \.offset) { _, block in
                BlockView(block: block)
            }
            CardFooter(item: item)
        }
    }
}

struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .heading(let text):
            Text(text).font(.title3).fontWeight(.semibold)
        case .text(let markdown):
            Text(Markdown.attributed(markdown)).font(.body)
        case .fields(let fields):
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 2) {
                ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                    GridRow {
                        Text(field.label).foregroundStyle(.secondary)
                        Text(field.value)
                    }
                }
            }
            .font(.callout)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(index + 1)." : "•").monospacedDigit()
                        Text(Markdown.attributed(text))
                    }
                }
            }
            .font(.callout)
        case .image(let url, let alt):
            if let url = URLPolicy.loadableURL(url) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else if phase.error != nil {
                        Text(alt ?? "").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: CardMetrics.imageMaxHeight, alignment: .leading)
                .accessibilityLabel(alt ?? "")
            } else if let alt, !alt.isEmpty {
                Text(alt).font(.caption).foregroundStyle(.secondary)
            }
        case .code(let text, _):
            ScrollView(.horizontal) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(6)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        case .link(let label, let url):
            if let url = URLPolicy.openableURL(url) {
                Link(destination: url) {
                    Label(label, systemImage: "arrow.up.right.square")
                }
            } else {
                Text(label)
            }
        case .unsupported:
            EmptyView()
        }
    }
}
