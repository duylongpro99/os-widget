import Foundation
import SwiftUI
import Testing
@testable import OSWidgetKit

@Suite("Compact cards")
struct CompactCardTests {
    private func fixture(kind: String) throws -> Item {
        try #require(Fixture.items().items.first { $0.kind == kind })
    }

    private func item(kind: String, summary: String = "Tóm tắt", body: JSONValue?) -> Item {
        Item(id: "i", kind: kind, source: "s", title: "Tiêu đề", summary: summary, body: body, createdAt: Date())
    }

    // MARK: Variant

    @Test func variantFollowsContent() {
        #expect(CompactCardView.variant(for: .notification(text: nil)) == .notification)
        #expect(CompactCardView.variant(for: .generic(blocks: [])) == .generic)
        #expect(CompactCardView.variant(for: .vocab(Self.vocab())) == .vocab)
        #expect(CompactCardView.variant(for: .unknown) == .fallback)
    }

    private static func vocab(
        examples: [String] = ["pure serendipity"],
        synonyms: [String] = ["chance", "luck", "fortune", "fluke"],
        context: String? = "A moment of serendipity."
    ) -> VocabContent {
        VocabContent(
            word: "serendipity", ipa: "/ˌser.ənˈdɪp.ə.ti/", pos: "noun",
            meanings: [.init(definition: "finding good things by chance", examples: examples)],
            context: context, synonyms: synonyms
        )
    }

    @Test func vocabMissingIpaUsesFallback() {
        let body: JSONValue = .object([
            "word": .string("serendipity"), "pos": .string("noun"),
            "meanings": .array([.object(["definition": .string("chance")])]),
        ])
        let content = item(kind: "vocab", body: body).content
        #expect(CompactCardView.variant(for: content) == .fallback)
    }

    @Test func vocabLayoutFitsTheLineBudget() {
        let full = Self.vocab()
        for lines in 0...6 {
            let layout = CompactVocabView.layout(for: full, lines: lines)
            let used = layout.definitionLines + (layout.showsExample ? 1 : 0)
                + (layout.synonyms.isEmpty ? 0 : 1) + layout.contextLines
            #expect(used <= lines, "lines \(lines)")
        }
    }

    @Test func vocabLayoutPerRow() {
        let one = CompactVocabView.layout(for: Self.vocab(), lines: WidgetSize.medium.rowLines)
        #expect(one == .init(definitionLines: 1, showsExample: false, synonyms: [], contextLines: 0))
        let lead = CompactVocabView.layout(for: Self.vocab(), lines: WidgetSize.medium.leadRowLines)
        #expect(lead == .init(definitionLines: 2, showsExample: false, synonyms: [], contextLines: 0))
        let large = CompactVocabView.layout(for: Self.vocab(), lines: WidgetSize.large.leadRowLines)
        #expect(large == .init(definitionLines: 2, showsExample: true, synonyms: ["chance", "luck", "fortune"], contextLines: 0))
    }

    @Test func vocabLayoutUsesSpareLinesForContext() {
        let bare = Self.vocab(examples: [], synonyms: [])
        let layout = CompactVocabView.layout(for: bare, lines: WidgetSize.large.leadRowLines)
        #expect(layout == .init(definitionLines: 2, showsExample: false, synonyms: [], contextLines: 2))
        #expect(CompactVocabView.layout(for: Self.vocab(synonyms: [], context: nil), lines: 4).contextLines == 0)
    }

    @Test func fixtureKindsMapToVariants() throws {
        #expect(CompactCardView.variant(for: try fixture(kind: "notification").content) == .notification)
        #expect(CompactCardView.variant(for: try fixture(kind: "generic").content) == .generic)
        #expect(CompactCardView.variant(for: try fixture(kind: "vocab").content) == .vocab)
        #expect(CompactCardView.variant(for: try fixture(kind: "weather").content) == .fallback)
    }

    // MARK: Detail line

    @Test func genericUsesFirstHeadingOrTextAndSkipsOtherBlocks() throws {
        #expect(CompactCardView.detail(for: try fixture(kind: "generic")) == "api v1.4.2")

        let textFirst = item(kind: "generic", body: .object(["blocks": .array([
            .object(["type": .string("chart"), "series": .array([.number(1)])]),
            .object(["type": .string("image"), "url": .string("https://example.com/a.png"), "alt": .string("ảnh")]),
            .object(["type": .string("code"), "text": .string("cargo test")]),
            .object(["type": .string("list"), "items": .array([.string("một")])]),
            .object(["type": .string("text"), "markdown": .string("Đã deploy **thành công**.")]),
            .object(["type": .string("heading"), "text": .string("Sau")]),
        ])]))
        #expect(CompactCardView.detail(for: textFirst) == "Đã deploy **thành công**.")
    }

    @Test func genericWithoutTextBlocksUsesSummary() {
        let noText = item(kind: "generic", body: .object(["blocks": .array([
            .object(["type": .string("heading"), "text": .string("   ")]),
            .object(["type": .string("chart")]),
        ])]))
        #expect(CompactCardView.detail(for: noText) == "Tóm tắt")
    }

    @Test func notificationUsesFirstLineOfTextAsTyped() throws {
        #expect(CompactCardView.detail(for: try fixture(kind: "notification")) == "Họp lúc **15:00**")
        let multiline = item(kind: "notification", body: .object(["text": .string("\n  [Chi tiết](https://example.com) <b>x</b>\nDòng hai")]))
        #expect(CompactCardView.detail(for: multiline) == "[Chi tiết](https://example.com) <b>x</b>")
    }

    @Test func notificationWithoutTextUsesSummary() {
        #expect(CompactCardView.detail(for: item(kind: "notification", body: nil)) == "Tóm tắt")
        #expect(CompactCardView.detail(for: item(kind: "notification", body: .object(["text": .string(" \n ")]))) == "Tóm tắt")
    }

    @Test func fallbackUsesSummaryOrNothing() throws {
        #expect(CompactCardView.detail(for: try fixture(kind: "vocab")) == "(n.) sự tình cờ may mắn")
        #expect(CompactCardView.detail(for: try fixture(kind: "weather")) == "Trời nhiều mây, chiều có mưa nhỏ")
        #expect(CompactCardView.detail(for: item(kind: "weather", summary: "", body: nil)) == nil)
    }

    // MARK: Sizes

    @Test func rowLimitsPerSize() {
        #expect(WidgetSize.medium.rowLimit == 3)
        #expect(WidgetSize.large.rowLimit == 6)
        for size in WidgetSize.allCases {
            #expect(size.rowLimit <= WidgetSnapshot.maxItems, "\(size)")
            #expect(size.leadRowLines >= size.rowLines, "\(size)")
        }
        #expect(WidgetSize.large.leadRowLines > WidgetSize.medium.leadRowLines)
    }

    // MARK: Rendering

    @MainActor
    @Test func everyFixtureItemRenders() throws {
        let fixtures = try Fixture.items().items
        #expect(Set(fixtures.map { CompactCardView.variant(for: $0.content) }) == [.notification, .generic, .vocab, .fallback])
        for item in fixtures {
            for lines in [1, 4] {
                let renderer = ImageRenderer(content: CompactCardView(item: item, lines: lines).frame(width: 280))
                let image = try #require(renderer.cgImage, "\(item.kind)")
                #expect(CGFloat(image.width) / renderer.scale == 280, "\(item.kind)")
                #expect(image.height > 0, "\(item.kind)")
            }
        }
    }
}
