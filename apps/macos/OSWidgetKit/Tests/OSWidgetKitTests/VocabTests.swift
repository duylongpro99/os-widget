import Foundation
import Testing
@testable import OSWidgetKit

@Suite("Vocab")
struct VocabTests {
    private static let full: [String: JSONValue] = [
        "word": .string("serendipity"),
        "ipa": .string("/ˌser.ənˈdɪp.ə.ti/"),
        "pos": .string("noun"),
        "audio_url": .string("https://example.com/serendipity.mp3"),
        "meanings": .array([
            .object(["definition": .string("finding good things by chance"), "examples": .array([.string("pure serendipity")])]),
            .object(["definition": .string("a happy accident")]),
        ]),
        "context": .string("It was serendipity that we met."),
        "synonyms": .array([.string("chance"), .string("fluke")]),
        "antonyms": .array([.string("misfortune")]),
    ]

    private static func content(_ body: [String: JSONValue]) -> ItemContent {
        ItemContent(kind: "vocab", body: .object(body))
    }

    private static func removing(_ key: String) -> [String: JSONValue] {
        var body = full
        body[key] = nil
        return body
    }

    // MARK: Decoding

    @Test func fixtureVocabDecodesWithItsFields() throws {
        let item = try #require(Fixture.items().items.first { $0.kind == "vocab" })
        #expect(item.content == .vocab(VocabContent(
            word: "serendipity",
            ipa: "/ˌser.ənˈdɪp.ə.ti/",
            pos: "noun",
            audioURL: nil,
            meanings: [.init(definition: "the fact of finding good things by chance", examples: ["pure serendipity"])],
            context: nil,
            synonyms: ["chance"],
            antonyms: []
        )))
    }

    @Test func fullBodyDecodesEveryField() {
        #expect(Self.content(Self.full) == .vocab(VocabContent(
            word: "serendipity",
            ipa: "/ˌser.ənˈdɪp.ə.ti/",
            pos: "noun",
            audioURL: "https://example.com/serendipity.mp3",
            meanings: [
                .init(definition: "finding good things by chance", examples: ["pure serendipity"]),
                .init(definition: "a happy accident", examples: []),
            ],
            context: "It was serendipity that we met.",
            synonyms: ["chance", "fluke"],
            antonyms: ["misfortune"]
        )))
    }

    @Test func missingRequiredFieldIsUnknown() {
        for key in ["word", "ipa", "pos", "meanings"] {
            #expect(Self.content(Self.removing(key)) == .unknown, "\(key)")
        }
        #expect(ItemContent(kind: "vocab", body: nil) == .unknown)
    }

    @Test func blankRequiredFieldIsUnknown() {
        for key in ["word", "ipa", "pos"] {
            var body = Self.full
            body[key] = .string("  ")
            #expect(Self.content(body) == .unknown, "\(key)")
        }
    }

    @Test func emptyMeaningsOrNoDefinitionIsUnknown() {
        var body = Self.full
        body["meanings"] = .array([])
        #expect(Self.content(body) == .unknown)
        body["meanings"] = .array([.object(["examples": .array([.string("x")])]), .object(["definition": .string(" ")])])
        #expect(Self.content(body) == .unknown)
    }

    @Test func optionalFieldsOfTheWrongTypeAreDropped() {
        var body = Self.full
        body["synonyms"] = .string("chance")
        body["antonyms"] = .array([.number(1), .string("misfortune")])
        body["audio_url"] = .number(3)
        body["context"] = .bool(true)
        guard case .vocab(let vocab) = Self.content(body) else {
            Issue.record("expected vocab content")
            return
        }
        #expect(vocab.synonyms.isEmpty)
        #expect(vocab.antonyms == ["misfortune"])
        #expect(vocab.audioURL == nil)
        #expect(vocab.context == nil)
        #expect(vocab.word == "serendipity" && vocab.meanings.count == 2)
    }
}
