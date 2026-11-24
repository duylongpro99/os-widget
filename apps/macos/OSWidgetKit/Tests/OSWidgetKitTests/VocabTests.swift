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

    // MARK: Pronunciation source

    @Test func httpsAudioWithHostIsPlayed() throws {
        let url = try #require(URL(string: "https://example.com/serendipity.mp3"))
        #expect(PronunciationSource.choose(word: "serendipity", audioURL: "https://example.com/serendipity.mp3") == .audio(url))
    }

    @Test func otherAudioURLsFallBackToSpeech() {
        for audioURL in [nil, "", "http://example.com/a.mp3", "https://", "https:///a.mp3", "file:///tmp/a.mp3"] {
            #expect(PronunciationSource.choose(word: "serendipity", audioURL: audioURL) == .speech("serendipity"), "\(audioURL ?? "nil")")
        }
    }

    // MARK: Pronouncer

    @MainActor
    @Test func wordWithoutAudioIsSpoken() {
        let (pronouncer, audio, speech) = Self.pronouncer()
        pronouncer.pronounce(word: "serendipity", audioURL: nil)
        #expect(audio.played.isEmpty)
        #expect(speech.spoken == ["serendipity"])
    }

    @MainActor
    @Test func audioIsPlayedAndNotSpokenWhenItStarts() async throws {
        let (pronouncer, audio, speech) = Self.pronouncer(timeout: .milliseconds(50))
        pronouncer.pronounce(word: "serendipity", audioURL: "https://example.com/a.mp3")
        #expect(audio.played.map(\.absoluteString) == ["https://example.com/a.mp3"])
        audio.send(.started)
        try await Task.sleep(for: .milliseconds(200))
        #expect(speech.spoken.isEmpty)
    }

    @MainActor
    @Test func failedAudioIsSpokenOnce() {
        let (pronouncer, audio, speech) = Self.pronouncer()
        pronouncer.pronounce(word: "serendipity", audioURL: "https://example.com/a.mp3")
        audio.send(.failed(reason: "load"))
        audio.send(.failed(reason: "play"))
        #expect(speech.spoken == ["serendipity"])
        #expect(audio.stopCount >= 2)
    }

    @MainActor
    @Test func audioThatDoesNotStartInTimeIsSpoken() async throws {
        let (pronouncer, audio, speech) = Self.pronouncer(timeout: .milliseconds(50))
        pronouncer.pronounce(word: "serendipity", audioURL: "https://example.com/a.mp3")
        try await Task.sleep(for: .milliseconds(300))
        #expect(speech.spoken == ["serendipity"])
        audio.send(.started)
        #expect(speech.spoken == ["serendipity"])
    }

    @MainActor
    @Test func pronouncingAgainStopsAndRestarts() {
        let (pronouncer, audio, speech) = Self.pronouncer()
        pronouncer.pronounce(word: "serendipity", audioURL: "https://example.com/a.mp3")
        let stopsBefore = audio.stopCount
        pronouncer.pronounce(word: "serendipity", audioURL: "https://example.com/a.mp3")
        #expect(audio.played.count == 2)
        #expect(audio.stopCount > stopsBefore && speech.stopCount >= 2)
        // A failure reported for the first request is ignored; only the current one may fall back.
        audio.sendToFirst(.failed(reason: "load"))
        #expect(speech.spoken.isEmpty)
        audio.send(.failed(reason: "load"))
        #expect(speech.spoken == ["serendipity"])
    }

    @MainActor
    private static func pronouncer(timeout: Duration = .seconds(60)) -> (Pronouncer, FakeAudio, FakeSpeech) {
        let audio = FakeAudio()
        let speech = FakeSpeech()
        return (Pronouncer(audio: audio, speech: speech, audioTimeout: timeout), audio, speech)
    }
}

@MainActor
private final class FakeAudio: AudioPlayback {
    var played: [URL] = []
    var stopCount = 0
    private var handlers: [@MainActor (AudioPlaybackEvent) -> Void] = []

    func play(_ url: URL, onEvent: @escaping @MainActor (AudioPlaybackEvent) -> Void) {
        played.append(url)
        handlers.append(onEvent)
    }

    func stop() {
        stopCount += 1
    }

    /// Reports an event for the latest `play`.
    func send(_ event: AudioPlaybackEvent) {
        handlers.last?(event)
    }

    /// Reports an event for the first `play`, as a late callback of a replaced file would.
    func sendToFirst(_ event: AudioPlaybackEvent) {
        handlers.first?(event)
    }
}

@MainActor
private final class FakeSpeech: SpeechPlayback {
    var spoken: [String] = []
    var stopCount = 0

    func speak(_ word: String) {
        spoken.append(word)
    }

    func stop() {
        stopCount += 1
    }
}
