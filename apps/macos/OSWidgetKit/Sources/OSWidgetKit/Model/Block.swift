import Foundation

/// One block of a `generic` item body (architecture §3.2). A block with an unknown `type`, or a known
/// `type` whose fields do not have the expected shape, becomes `.unsupported` and views skip it.
public enum Block: Sendable, Hashable {
    case heading(text: String)
    case text(markdown: String)
    case fields([Field])
    case list(items: [String], ordered: Bool)
    case image(url: String, alt: String?)
    case code(text: String, language: String?)
    case link(label: String, url: String)
    case unsupported(type: String?)

    public struct Field: Sendable, Hashable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public init(json: JSONValue) {
        let type = json["type"]?.stringValue
        self = Self.parse(type: type, json: json) ?? .unsupported(type: type)
    }

    private static func parse(type: String?, json: JSONValue) -> Block? {
        func string(_ key: String) -> String? { json[key]?.stringValue }
        func optionalString(_ key: String) -> String?? {
            switch json[key] {
            case nil, .null?: .some(nil)
            case .string(let value)?: .some(value)
            default: nil
            }
        }

        switch type {
        case "heading":
            return string("text").map { .heading(text: $0) }
        case "text":
            return string("markdown").map { .text(markdown: $0) }
        case "fields":
            guard let entries = json["items"]?.arrayValue else { return nil }
            var fields: [Field] = []
            for entry in entries {
                guard let label = entry["label"]?.stringValue, let value = entry["value"]?.stringValue else { return nil }
                fields.append(Field(label: label, value: value))
            }
            return .fields(fields)
        case "list":
            guard let entries = json["items"]?.arrayValue else { return nil }
            let items = entries.compactMap(\.stringValue)
            guard items.count == entries.count else { return nil }
            let ordered: Bool
            switch json["ordered"] {
            case nil, .null?: ordered = false
            case .bool(let value)?: ordered = value
            default: return nil
            }
            return .list(items: items, ordered: ordered)
        case "image":
            guard let url = string("url"), let alt = optionalString("alt") else { return nil }
            return .image(url: url, alt: alt)
        case "code":
            guard let text = string("text"), let language = optionalString("language") else { return nil }
            return .code(text: text, language: language)
        case "link":
            guard let label = string("label"), let url = string("url") else { return nil }
            return .link(label: label, url: url)
        default:
            return nil
        }
    }
}
