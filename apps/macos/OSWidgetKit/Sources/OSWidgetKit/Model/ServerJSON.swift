import Foundation

/// JSON coders for server responses and the store file.
///
/// Dates are ISO 8601 with or without fractional seconds, in any offset, as PostgREST returns them
/// (for example `2026-11-23T05:07:17.113585+00:00`). They are written back in UTC with six fractional
/// digits, so a date read from the server survives a save and reload unchanged.
public enum ServerJSON {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date")
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatDate(date))
        }
        return encoder
    }

    public static func parseDate(_ text: String) -> Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)
    }

    public static func formatDate(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        var seconds = interval.rounded(.down)
        var micros = Int(((interval - seconds) * 1_000_000).rounded())
        if micros >= 1_000_000 {
            seconds += 1
            micros -= 1_000_000
        }
        let whole = Date(timeIntervalSince1970: seconds).formatted(Date.ISO8601FormatStyle())
        let fraction = String(micros)
        return "\(whole.dropLast()).\(String(repeating: "0", count: 6 - fraction.count))\(fraction)Z"
    }
}
