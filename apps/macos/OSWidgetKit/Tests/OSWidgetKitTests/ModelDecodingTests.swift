import Foundation
import Testing
@testable import OSWidgetKit

@Suite("Model decoding")
struct ModelDecodingTests {
    private func item(_ id: String, in response: ItemsResponse) throws -> Item {
        try #require(response.items.first { $0.id == id })
    }

    @Test func itemWithoutSummaryIsDroppedAndTheRestLoad() throws {
        let response = try Fixture.items()
        #expect(response.seq == 392)
        #expect(response.items.count == 6)
        #expect(!response.items.contains { $0.title == "Thiếu summary" })
    }

    @Test func serverItemDecodesWithMicrosecondDates() throws {
        let response = try Fixture.items()
        let item = try #require(response.items.first { $0.source == "acceptance" })
        #expect(item.content == .notification(text: nil))
        #expect(item.title.hasPrefix("default ttl acceptance-"))
        #expect(item.createdAt == ServerJSON.parseDate("2026-11-23T08:50:33.342978+00:00"))
        #expect(item.createdAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) > 0.3429)
        #expect(item.expiresAt == ServerJSON.parseDate("2026-11-30T08:50:33.31+00:00"))
        #expect(item.readAt == nil && item.deletedAt == nil && item.body == nil)
    }

    @Test func notificationTextDecodes() throws {
        let item = try item("3eb15c94-6f70-4182-9dce-4f5a6b7c8d93", in: Fixture.items())
        #expect(item.content == .notification(text: "Họp lúc **15:00**"))
        #expect(item.isRead)
    }

    @Test func genericKeepsKnownBlocksAndMarksUnknownOnesUnsupported() throws {
        let item = try item("2da04b83-5e6f-4071-8cbd-3e4f5a6b7c82", in: Fixture.items())
        #expect(item.priority == "high")
        #expect(item.url == "https://example.com/deploys/42")
        #expect(item.content == .generic(blocks: [
            .heading(text: "api v1.4.2"),
            .text(markdown: "Đã deploy **thành công**."),
            .fields([.init(label: "Thời gian", value: "42s"), .init(label: "Commit", value: "abc1234")]),
            .list(items: ["migrate", "restart"], ordered: true),
            .list(items: ["no order flag"], ordered: false),
            .image(url: "https://example.com/chart.png", alt: "biểu đồ"),
            .code(text: "cargo test", language: "sh"),
            .link(label: "Xem log", url: "https://example.com/logs/42"),
            .unsupported(type: "chart"),
            .unsupported(type: "heading"),
            .text(markdown: "Kết thúc."),
        ]))
    }

    @Test func vocabDecodesAndKeepsTitleAndSummary() throws {
        let item = try item("1c9f3a72-4d5e-4f60-9bac-2d3e4f5a6b71", in: Fixture.items())
        #expect(item.kind == "vocab")
        guard case .vocab = item.content else {
            Issue.record("expected vocab content, got \(item.content)")
            return
        }
        #expect(item.title == "serendipity")
        #expect(item.summary == "(n.) sự tình cờ may mắn")
        #expect(item.body?["word"]?.stringValue == "serendipity")
    }

    @Test func unknownKindIsUnknownButKeepsTitleAndSummary() throws {
        let item = try item("0b8e2f61-3c4d-4e5f-8a9b-1c2d3e4f5a60", in: Fixture.items())
        #expect(item.kind == "weather")
        #expect(item.content == .unknown)
        #expect(item.title == "Hà Nội 18°C")
        #expect(item.summary == "Trời nhiều mây, chiều có mưa nhỏ")
    }

    @Test func brokenBodyFallsBackToUnknownWithoutLosingTheItem() throws {
        let item = try item("4fc26da5-7081-4293-aedf-5a6b7c8d9ea4", in: Fixture.items())
        #expect(item.content == .unknown)
        #expect(item.title == "Body hỏng")
        #expect(ItemContent(kind: "notification", body: .string("oops")) == .unknown)
        #expect(ItemContent(kind: "generic", body: .object(["blocks": .string("x")])) == .unknown)
        #expect(ItemContent(kind: "generic", body: nil) == .unknown)
    }

    @Test func eventsPageDecodes() throws {
        let events = try Fixture.events()
        #expect(events.count == 12)
        #expect(events.map(\.seq) == Array(383...394))
        #expect(events.filter { $0.type == .created && $0.item != nil }.count == 4)
        #expect(events.compactMap(\.item).allSatisfy { $0.source == "acceptance" })
        #expect(events.contains { $0.type == .read } && events.contains { $0.type == .unread })
        #expect(events.filter { $0.type == .deleted }.count == 4)

        let purged = try #require(events.first { $0.seq == 393 })
        #expect(purged.type == .created && purged.item == nil)
        #expect(try #require(events.first { $0.seq == 394 }).type == .other("item.pinned"))
        #expect(events[0].createdAt == ServerJSON.parseDate("2026-11-23T08:50:22.521951+00:00"))
    }

    @Test func unreadableEventItemBecomesNil() throws {
        let json = #"[{"seq": 7, "type": "item.created", "item_id": "a", "created_at": "2026-11-23T08:50:22.521951+00:00", "item": {"id": "a"}}]"#
        let events = try ServerJSON.makeDecoder().decode([ServerEvent].self, from: Data(json.utf8))
        #expect(events == [ServerEvent(seq: 7, type: .created, itemId: "a", item: nil, createdAt: ServerJSON.parseDate("2026-11-23T08:50:22.521951Z"))])
    }

    @Test(arguments: [
        "2026-11-23T05:07:17.113585+00:00",
        "2026-11-23T05:07:31.31+00:00",
        "2026-11-23T05:07:30.503+00:00",
        "2026-11-23T05:07:30+00:00",
        "2026-11-23T12:07:30.000001+07:00",
    ])
    func datesSurviveFormatting(text: String) throws {
        let date = try #require(ServerJSON.parseDate(text))
        let formatted = ServerJSON.formatDate(date)
        #expect(formatted.hasSuffix("Z"))
        #expect(ServerJSON.parseDate(formatted) == date)
    }

    @Test func itemRoundTripsThroughTheStoreEncoding() throws {
        let items = try Fixture.items().items
        let data = try ServerJSON.makeEncoder().encode(items)
        let decoded = try ServerJSON.makeDecoder().decode([Item].self, from: data)
        #expect(decoded == items)
    }
}
