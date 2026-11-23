import Foundation
import SwiftUI
import Testing
@testable import OSWidgetKit

@Suite("Cards")
struct CardsTests {
    // MARK: URL policy

    @Test func httpsWithoutHostIsRefused() {
        for string in ["https://", "https:///path", "https:", "http://", "https://%20/x"] {
            #expect(URLPolicy.openableURL(string) == nil, "\(string)")
            #expect(URLPolicy.loadableURL(string) == nil, "\(string)")
        }
    }

    @Test func unsafeSchemesAreRefused() {
        for string in ["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com/x", "data:text/html,hi", "mailto:a@example.com"] {
            #expect(URLPolicy.openableURL(string) == nil, "\(string)")
            #expect(URLPolicy.loadableURL(string) == nil, "\(string)")
        }
    }

    @Test func httpOpensButDoesNotLoad() throws {
        let url = try #require(URL(string: "http://example.com"))
        #expect(URLPolicy.isOpenable(url))
        #expect(!URLPolicy.isLoadable(url))
    }

    @Test func httpsWithHostOpensAndLoads() throws {
        let url = try #require(URL(string: "HTTPS://example.com/a.png"))
        #expect(URLPolicy.isOpenable(url))
        #expect(URLPolicy.isLoadable(url))
        #expect(URLPolicy.openableURL("  https://example.com ") != nil)
    }

    @Test func missingOrEmptyStringIsRefused() {
        #expect(URLPolicy.openableURL(nil) == nil)
        #expect(URLPolicy.openableURL("") == nil)
        #expect(URLPolicy.loadableURL("   ") == nil)
    }

    // MARK: Markdown

    @Test func rawHTMLShowsAsTypedText() {
        let source = "trước <script>alert(1)</script> <b>đậm</b> sau"
        #expect(String(Markdown.attributed(source).characters) == source)
    }

    @Test func inlineMarkdownIsInterpreted() {
        let result = Markdown.attributed("a **b** `c`\nd")
        #expect(String(result.characters) == "a b c\nd")
    }

    @Test func onlyOpenableLinksSurvive() {
        let result = Markdown.attributed("[x](javascript:alert(1)) [f](file:///etc/hosts) [e](https://) [ok](https://example.com) [h](http://example.com)")
        let links = result.runs.compactMap(\.link).map(\.absoluteString)
        #expect(links == ["https://example.com", "http://example.com"])
    }

    @Test func markdownImagesAreNotLoaded() {
        let result = Markdown.attributed("![ảnh](https://example.com/a.png)")
        #expect(result.runs.allSatisfy { $0.imageURL == nil })
        #expect(String(result.characters) == "ảnh")
    }

    // MARK: Card selection

    @Test func cardVariantFollowsContent() throws {
        #expect(CardView.variant(for: .notification(text: nil)) == .notification)
        #expect(CardView.variant(for: .generic(blocks: [])) == .generic)
        #expect(CardView.variant(for: .unknown) == .fallback)
    }

    @Test func unknownKindAndVocabUseFallbackCard() throws {
        let unknown = Item(id: "u", kind: "no-such-kind", source: "s", title: "T", summary: "S", body: .object(["x": .number(1)]), createdAt: Date())
        #expect(CardView.variant(for: unknown.content) == .fallback)
        let vocab = try #require(Fixture.items().items.first { $0.kind == "vocab" })
        #expect(CardView.variant(for: vocab.content) == .fallback)
    }

    @Test func unsupportedBlocksAreSkipped() {
        let blocks: [Block] = [
            .heading(text: "H"),
            .unsupported(type: "chart"),
            .unsupported(type: nil),
            .text(markdown: "t"),
        ]
        #expect(GenericCardView.renderedBlocks(blocks) == [.heading(text: "H"), .text(markdown: "t")])
    }

    @Test func imageBlockNeedsLoadableURLOrAltText() {
        let blocks: [Block] = [
            .image(url: "https://example.com/a.png", alt: nil),
            .image(url: "http://example.com/a.png", alt: nil),
            .image(url: "https://", alt: "mô tả"),
        ]
        #expect(GenericCardView.renderedBlocks(blocks) == [
            .image(url: "https://example.com/a.png", alt: nil),
            .image(url: "https://", alt: "mô tả"),
        ])
    }

    // MARK: Rendering

    @MainActor
    @Test func everyCardRendersAtCardWidth() throws {
        let fixtures = try Fixture.items().items
        let unknown = Item(id: "u", kind: "no-such-kind", source: "s", title: "Tiêu đề", summary: "Tóm tắt", createdAt: Date())
        let samples = fixtures + [unknown]
        #expect(Set(samples.map { CardView.variant(for: $0.content) }) == [.notification, .generic, .fallback])
        for item in samples {
            let renderer = ImageRenderer(content: CardView(item: item))
            let image = try #require(renderer.cgImage, "\(item.kind)")
            #expect(CGFloat(image.width) / renderer.scale == CardMetrics.width, "\(item.kind)")
            #expect(image.height > 0, "\(item.kind)")
        }
    }
}
