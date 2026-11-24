import SwiftUI

/// A `vocab` item: the word with its IPA, part of speech and a pronounce button, then numbered meanings,
/// the context sentence, synonyms and antonyms, source and time. Every text is shown as typed; nothing is
/// read as markdown or HTML.
///
/// Sound plays only when the button is pressed (FR-7).
public struct VocabCardView: View {
    /// The most meanings a card shows, so it stays short enough for the popup.
    nonisolated static let maxMeanings = 3
    /// The most examples shown under each meaning.
    nonisolated static let maxExamplesPerMeaning = 1

    let item: Item
    let vocab: VocabContent

    public init(item: Item, vocab: VocabContent) {
        self.item = item
        self.vocab = vocab
    }

    /// The meanings the card shows: at most `maxMeanings`, each with at most `maxExamplesPerMeaning`
    /// examples.
    nonisolated static func shownMeanings(_ meanings: [VocabContent.Meaning]) -> [VocabContent.Meaning] {
        meanings.prefix(maxMeanings).map {
            VocabContent.Meaning(definition: $0.definition, examples: Array($0.examples.prefix(maxExamplesPerMeaning)))
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            meanings
            if let context = vocab.context {
                Text(verbatim: context)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.tertiary).frame(width: 2)
                    }
            }
            WordList(label: "Đồng nghĩa", words: vocab.synonyms)
            WordList(label: "Trái nghĩa", words: vocab.antonyms)
            CardFooter(item: item)
        }
    }

    /// Word, IPA, part of speech and the pronounce button on one row when they fit; otherwise the IPA and
    /// part of speech move to a second row, so a long word never squeezes the IPA away.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                word.fixedSize()
                ipa.fixedSize()
                pos
                Spacer(minLength: 4)
                pronounceButton
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    word
                    Spacer(minLength: 4)
                    pronounceButton
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ipa
                    pos
                }
            }
        }
    }

    private var word: some View {
        Text(verbatim: vocab.word)
            .font(.title3)
            .fontWeight(item.isRead ? .regular : .semibold)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var ipa: some View {
        Text(verbatim: vocab.ipa)
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var pos: some View {
        Text(verbatim: vocab.pos)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
            .fixedSize()
    }

    private var pronounceButton: some View {
        Button {
            Pronouncer.shared.pronounce(word: vocab.word, audioURL: vocab.audioURL)
        } label: {
            Image(systemName: "speaker.wave.2")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Phát âm")
        .help("Phát âm")
    }

    private var meanings: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(Self.shownMeanings(vocab.meanings).enumerated()), id: \.offset) { index, meaning in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(index + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: meaning.definition)
                            .lineLimit(3)
                        ForEach(meaning.examples, id: \.self) { example in
                            Text(verbatim: example)
                                .italic()
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .font(.body)
            }
        }
    }
}

/// "Đồng nghĩa: a, b, c", hidden when there are no words.
private struct WordList: View {
    let label: String
    let words: [String]

    var body: some View {
        if !words.isEmpty {
            let name = Text(verbatim: "\(label): ").foregroundStyle(.secondary)
            let list = Text(verbatim: words.joined(separator: ", "))
            Text("\(name)\(list)")
                .font(.callout)
                .lineLimit(2)
        }
    }
}
