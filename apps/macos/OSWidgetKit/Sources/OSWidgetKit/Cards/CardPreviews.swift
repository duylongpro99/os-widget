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

    static let vocab = Item(
        id: "preview-vocab", kind: "vocab", source: "vocab-cron", priority: "low",
        title: "serendipity", summary: "(n.) sự tình cờ may mắn",
        body: .object(["word": .string("serendipity")]),
        createdAt: created
    )
}

#Preview("Notification") { CardView(item: CardPreviewSamples.notification) }
#Preview("Notification, dark") { CardView(item: CardPreviewSamples.notification).preferredColorScheme(.dark) }
#Preview("Generic") { CardView(item: CardPreviewSamples.generic) }
#Preview("Generic, dark") { CardView(item: CardPreviewSamples.generic).preferredColorScheme(.dark) }
#Preview("Fallback") { CardView(item: CardPreviewSamples.vocab) }
#Preview("Fallback, dark") { CardView(item: CardPreviewSamples.vocab).preferredColorScheme(.dark) }
#endif
