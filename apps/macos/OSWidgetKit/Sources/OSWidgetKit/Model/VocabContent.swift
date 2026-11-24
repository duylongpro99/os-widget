import Foundation

/// The body of a `vocab` item (architecture §3.2): one word with its meanings.
///
/// Decoding is lenient where the server is strict: an optional field of the wrong type is dropped and the
/// rest still decodes. A missing or blank required field (`word`, `ipa`, `pos`, or no meaning with a
/// `definition`) makes the body undecodable, so the item shows with the fallback card.
public struct VocabContent: Sendable, Hashable {
    public struct Meaning: Sendable, Hashable {
        public var definition: String
        public var examples: [String]

        public init(definition: String, examples: [String] = []) {
            self.definition = definition
            self.examples = examples
        }
    }

    public var word: String
    public var ipa: String
    /// Part of speech, for example `noun`.
    public var pos: String
    /// Pronunciation audio as sent. It is checked with `URLPolicy` before it is loaded.
    public var audioURL: String?
    /// At least one meaning.
    public var meanings: [Meaning]
    public var context: String?
    public var synonyms: [String]
    public var antonyms: [String]

    public init(
        word: String,
        ipa: String,
        pos: String,
        audioURL: String? = nil,
        meanings: [Meaning],
        context: String? = nil,
        synonyms: [String] = [],
        antonyms: [String] = []
    ) {
        self.word = word
        self.ipa = ipa
        self.pos = pos
        self.audioURL = audioURL
        self.meanings = meanings
        self.context = context
        self.synonyms = synonyms
        self.antonyms = antonyms
    }

    /// The content of `body`, or `nil` when a required field is missing or blank.
    public init?(json body: JSONValue?) {
        guard let body,
              let word = Self.nonBlank(body["word"]),
              let ipa = Self.nonBlank(body["ipa"]),
              let pos = Self.nonBlank(body["pos"])
        else { return nil }
        let meanings = (body["meanings"]?.arrayValue ?? []).compactMap { meaning -> Meaning? in
            guard let definition = Self.nonBlank(meaning["definition"]) else { return nil }
            return Meaning(definition: definition, examples: Self.strings(meaning["examples"]))
        }
        guard !meanings.isEmpty else { return nil }
        self.init(
            word: word,
            ipa: ipa,
            pos: pos,
            audioURL: Self.nonBlank(body["audio_url"]),
            meanings: meanings,
            context: Self.nonBlank(body["context"]),
            synonyms: Self.strings(body["synonyms"]),
            antonyms: Self.strings(body["antonyms"])
        )
    }

    /// The trimmed string in `value`, or `nil` when it is not a string or is blank.
    private static func nonBlank(_ value: JSONValue?) -> String? {
        guard let string = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else { return nil }
        return string
    }

    /// The non-blank strings of an array. Anything that is not an array gives an empty list; elements that
    /// are not strings are skipped.
    private static func strings(_ value: JSONValue?) -> [String] {
        (value?.arrayValue ?? []).compactMap(nonBlank)
    }
}
