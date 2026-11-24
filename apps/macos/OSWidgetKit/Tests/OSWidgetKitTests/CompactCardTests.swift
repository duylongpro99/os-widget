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
        #expect(CompactCardView.variant(for: .unknown) == .fallback)
    }

    @Test func fixtureKindsMapToVariants() throws {
        #expect(CompactCardView.variant(for: try fixture(kind: "notification").content) == .notification)
        #expect(CompactCardView.variant(for: try fixture(kind: "generic").content) == .generic)
        #expect(CompactCardView.variant(for: try fixture(kind: "vocab").content) == .fallback)
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
        #expect(Set(fixtures.map { CompactCardView.variant(for: $0.content) }) == [.notification, .generic, .fallback])
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
