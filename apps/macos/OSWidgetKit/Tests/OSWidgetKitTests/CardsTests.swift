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

    @Test func unknownKindUsesFallbackCard() throws {
        let unknown = Item(id: "u", kind: "no-such-kind", source: "s", title: "T", summary: "S", body: .object(["x": .number(1)]), createdAt: Date())
        #expect(CardView.variant(for: unknown.content) == .fallback)
    }

    @Test func vocabUsesVocabCardAndBadVocabUsesFallback() throws {
        let vocab = try #require(Fixture.items().items.first { $0.kind == "vocab" })
        #expect(CardView.variant(for: vocab.content) == .vocab)
        let incomplete = Item(id: "v", kind: "vocab", source: "s", title: "T", summary: "S", body: .object(["word": .string("x")]), createdAt: Date())
        #expect(CardView.variant(for: incomplete.content) == .fallback)
    }

    @Test func vocabCardLimitsWhatItShows() {
        let meanings = (1...5).map { VocabContent.Meaning(definition: "d\($0)", examples: ["e\($0)a", "e\($0)b"]) }
        let shown = VocabCardView.shownMeanings(meanings)
        #expect(shown.map(\.definition) == ["d1", "d2", "d3"])
        #expect(shown.map(\.examples) == [["e1a"], ["e2a"], ["e3a"]])
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
        let longVocab = Item(
            id: "lv", kind: "vocab", source: "vocab-cron", title: "w", summary: "s",
            body: .object([
                "word": .string("pneumonoultramicroscopicsilicovolcanoconiosis"),
                "ipa": .string("/ˌnjuː.mə.noʊˌʌl.trə.maɪ.krəˈskɒp.ɪkˌsɪl.ɪ.koʊ.vɒlˌkeɪ.noʊ.koʊ.niˈoʊ.sɪs/"),
                "pos": .string("noun"),
                "audio_url": .string("https://example.com/a.mp3"),
                "meanings": .array((1...3).map { .object([
                    "definition": .string(String(repeating: "a lung disease caused by fine silica dust \($0) ", count: 6)),
                    "examples": .array([.string(String(repeating: "example sentence ", count: 12))]),
                ]) }),
                "context": .string(String(repeating: "a long context sentence taken from a book ", count: 20)),
                "synonyms": .array((1...30).map { .string("synonym\($0)") }),
                "antonyms": .array((1...30).map { .string("antonym\($0)") }),
            ]),
            createdAt: Date()
        )
        let samples = fixtures + [unknown, longVocab]
        #expect(Set(samples.map { CardView.variant(for: $0.content) }) == [.notification, .generic, .vocab, .fallback])
        for item in samples {
            let renderer = ImageRenderer(content: CardView(item: item))
            let image = try #require(renderer.cgImage, "\(item.kind)")
            #expect(CGFloat(image.width) / renderer.scale == CardMetrics.width, "\(item.kind)")
            #expect(image.height > 0, "\(item.kind)")
        }
    }

    // MARK: Card clicks

    @MainActor
    @Test func cardTapRunsWhenNoLinkOpened() {
        let gate = CardClickGate()
        #expect(gate.allowsTap(at: 10))
    }

    @MainActor
    @Test func cardTapIsDroppedForTheClickThatOpenedALink() {
        let gate = CardClickGate()
        gate.linkOpened(at: 10)
        #expect(!gate.allowsTap(at: 10))
        #expect(!gate.allowsTap(at: 10.2))
        #expect(!gate.allowsTap(at: 9.8))
    }

    @MainActor
    @Test func laterCardTapRunsAfterALinkOpened() {
        let gate = CardClickGate()
        gate.linkOpened(at: 10)
        #expect(gate.allowsTap(at: 10 + CardClickGate.linkWindow + 0.1))
    }

    @MainActor
    @Test func cardTapIsDroppedForTheClickHandledByAControl() {
        let gate = CardClickGate()
        gate.controlClicked(at: 10)
        #expect(!gate.allowsTap(at: 10))
        #expect(!gate.allowsTap(at: 9.9))
        #expect(gate.allowsTap(at: 10 + CardClickGate.linkWindow + 0.1))
    }
}
