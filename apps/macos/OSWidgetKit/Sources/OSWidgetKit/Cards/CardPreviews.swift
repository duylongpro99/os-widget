#if DEBUG
import SwiftUI

/// Sample items shaped like the test fixtures, for checking cards in light and dark mode.
enum CardPreviewSamples {
    static let created = Date(timeIntervalSinceNow: -15 * 60)

    static let notification = Item(
        id: "preview-notification", kind: "notification", source: "deploy-bot",
        title: "Deploy xong", summary: "Worker os-widget đã lên bản mới",
        url: "https://example.com/deploy",
        body: .object(["text": .string("Bản **0.3** đã chạy. <b>HTML</b> hiện nguyên văn. [Chi tiết](https://example.com)")]),
        createdAt: created
    )

    static let generic = Item(
        id: "preview-generic", kind: "generic", source: "report-cron",
        title: "Báo cáo tuần", summary: "Tóm tắt số liệu",
        body: .object(["blocks": .array([
            .object(["type": .string("heading"), "text": .string("Tổng quan")]),
            .object(["type": .string("text"), "markdown": .string("Tuần này *ổn định*.")]),
            .object(["type": .string("fields"), "items": .array([
                .object(["label": .string("Mục"), "value": .string("42")]),
                .object(["label": .string("Lỗi"), "value": .string("0")]),
            ])]),
            .object(["type": .string("list"), "items": .array([.string("Một"), .string("Hai")]), "ordered": .bool(true)]),
            .object(["type": .string("code"), "text": .string("cargo test --workspace && swift test"), "language": .string("sh")]),
            .object(["type": .string("link"), "label": .string("Mở bảng"), "url": .string("https://example.com")]),
            .object(["type": .string("chart")]),
        ])]),
        createdAt: created, readAt: Date()
    )

    /// A `vocab` item whose body lacks required fields, so it shows the fallback card.
    static let fallback = Item(
        id: "preview-fallback", kind: "vocab", source: "vocab-cron", priority: "low",
        title: "serendipity", summary: "(n.) sự tình cờ may mắn",
        body: .object(["word": .string("serendipity")]),
        createdAt: created
    )

    /// A full `vocab` item that plays its `audio_url`.
    static let vocab = Item(
        id: "preview-vocab", kind: "vocab", source: "vocab-cron",
        title: "serendipity", summary: "(n.) sự tình cờ may mắn",
        body: .object([
            "word": .string("serendipity"),
            "ipa": .string("/ˌser.ənˈdɪp.ə.ti/"),
            "pos": .string("noun"),
            "audio_url": .string("https://api.dictionaryapi.dev/media/pronunciations/en/serendipity-us.mp3"),
            "meanings": .array([
                .object(["definition": .string("The fact of finding good things by chance."), "examples": .array([.string("Meeting her was pure serendipity.")])]),
                .object(["definition": .string("A happy accident.")]),
            ]),
            "context": .string("It was serendipity that brought them to the same café that morning."),
            "synonyms": .array([.string("chance"), .string("fluke"), .string("luck")]),
            "antonyms": .array([.string("misfortune")]),
        ]),
        createdAt: created
    )

    /// A long `vocab` item without `audio_url`, read by the speech synthesizer, to check the card keeps
    /// its width.
    static let vocabLong = Item(
        id: "preview-vocab-long", kind: "vocab", source: "book-ingest",
        title: "pneumonoultramicroscopicsilicovolcanoconiosis", summary: "(n.) bệnh bụi phổi",
        body: .object([
            "word": .string("pneumonoultramicroscopicsilicovolcanoconiosis"),
            "ipa": .string("/ˌnjuː.mə.noʊˌʌl.trə.maɪ.krəˈskɒp.ɪkˌsɪl.ɪ.koʊ.vɒlˌkeɪ.noʊ.koʊ.niˈoʊ.sɪs/"),
            "pos": .string("noun"),
            "meanings": .array((1...4).map { index in .object([
                "definition": .string("Meaning \(index): a lung disease caused by inhaling very fine silicate or quartz dust over many years."),
                "examples": .array([.string("An example sentence that is long enough to wrap onto a second line of the card."), .string("Hidden second example.")]),
            ]) }),
            "context": .string(String(repeating: "A long context sentence taken from the book, repeated to overflow the quote. ", count: 6)),
            "synonyms": .array((1...20).map { .string("synonym\($0)") }),
            "antonyms": .array((1...20).map { .string("antonym\($0)") }),
        ]),
        createdAt: created, readAt: Date()
    )
}

#Preview("Notification") { CardView(item: CardPreviewSamples.notification) }
#Preview("Notification, dark") { CardView(item: CardPreviewSamples.notification).preferredColorScheme(.dark) }
#Preview("Generic") { CardView(item: CardPreviewSamples.generic) }
#Preview("Generic, dark") { CardView(item: CardPreviewSamples.generic).preferredColorScheme(.dark) }
#Preview("Vocab, audio") { CardView(item: CardPreviewSamples.vocab) }
#Preview("Vocab, audio, dark") { CardView(item: CardPreviewSamples.vocab).preferredColorScheme(.dark) }
#Preview("Vocab, speech, long") { CardView(item: CardPreviewSamples.vocabLong) }
#Preview("Vocab, speech, long, dark") { CardView(item: CardPreviewSamples.vocabLong).preferredColorScheme(.dark) }
#Preview("Fallback") { CardView(item: CardPreviewSamples.fallback) }
#Preview("Fallback, dark") { CardView(item: CardPreviewSamples.fallback).preferredColorScheme(.dark) }
#endif
