import Foundation

/// Inline markdown from item content.
///
/// Only inline syntax is interpreted and whitespace is kept. Raw HTML is never rendered: it stays in the
/// text as typed. A link survives only when `URLPolicy.isOpenable` accepts it, and it opens only when
/// the user clicks it. Markdown images are never loaded; their alt text stays as plain text.
public enum Markdown {
    public static func attributed(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var result = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        for run in result.runs {
            if let link = run.link, !URLPolicy.isOpenable(link) {
                result[run.range].link = nil
            }
            if run.imageURL != nil {
                result[run.range].imageURL = nil
            }
        }
        return result
    }
}
