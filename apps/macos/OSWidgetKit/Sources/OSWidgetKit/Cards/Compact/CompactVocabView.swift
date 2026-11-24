import SwiftUI

/// A `vocab` item in compact form: the word with its pronunciation and part of speech, then the first
/// definition. When the row has spare lines it adds the first example, a few synonyms and the context.
/// There is no pronounce control: the widget never plays sound.
struct CompactVocabView: View {
    let item: Item
    let vocab: VocabContent
    let lines: Int

    /// What a row of a given height shows under the word line. The word line itself is not counted.
    struct Layout: Equatable {
        var definitionLines: Int
        var showsExample: Bool
        var synonyms: [String]
        var contextLines: Int
    }

    static let maxDefinitionLines = 2
    static let maxSynonyms = 3
    static let maxContextLines = 2

    /// Fills `lines` in priority order: the definition (up to two lines), the first example, the synonyms,
    /// then the context. A part with nothing to show costs no line, and the total never exceeds `lines`.
    nonisolated static func layout(for vocab: VocabContent, lines: Int) -> Layout {
        var remaining = max(lines, 0)
        let definitionLines = min(remaining, maxDefinitionLines)
        remaining -= definitionLines
        let showsExample = remaining >= 1 && example(of: vocab) != nil
        if showsExample { remaining -= 1 }
        let synonyms = remaining >= 1 ? Array(vocab.synonyms.prefix(maxSynonyms)) : []
        if !synonyms.isEmpty { remaining -= 1 }
        let contextLines = vocab.context == nil ? 0 : min(remaining, maxContextLines)
        return Layout(
            definitionLines: definitionLines, showsExample: showsExample,
            synonyms: synonyms, contextLines: contextLines
        )
    }

    private nonisolated static func example(of vocab: VocabContent) -> String? {
        vocab.meanings.first?.examples.first
    }

    var body: some View {
        let layout = Self.layout(for: vocab, lines: lines)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: vocab.word)
                    .font(.subheadline)
                    .fontWeight(item.isRead ? .regular : .bold)
                    .foregroundStyle(item.isRead ? .secondary : .primary)
                Text(verbatim: vocab.ipa)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: vocab.pos)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .lineLimit(1)
            if layout.definitionLines > 0, let definition = vocab.meanings.first?.definition {
                detailText(definition, lines: layout.definitionLines)
            }
            if layout.showsExample, let example = Self.example(of: vocab) {
                detailText(example, lines: 1, italic: true)
            }
            if !layout.synonyms.isEmpty {
                detailText(layout.synonyms.joined(separator: ", "), lines: 1)
            }
            if layout.contextLines > 0, let context = vocab.context {
                detailText(context, lines: layout.contextLines)
            }
            CompactCardFooter(item: item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailText(_ text: String, lines: Int, italic: Bool = false) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .italic(italic)
            .foregroundStyle(item.isRead ? .tertiary : .secondary)
            .lineLimit(lines)
    }
}
