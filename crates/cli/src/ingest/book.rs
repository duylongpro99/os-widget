//! Choosing words to learn from a plain-text book, each with the sentence it
//! first appears in. Everything here is pure: text in, `(word, context)` out.

use std::collections::{HashMap, HashSet};

use super::stopwords::is_stopword;

/// Longest context sentence kept whole; longer ones are cut around the word.
const MAX_CONTEXT_CHARS: usize = 240;
/// Shorter sentences are fragments (`Yes.`, `Chapter 1.`), not context.
const MIN_CONTEXT_CHARS: usize = 20;
/// A word must appear at least this often to be worth learning.
const MIN_OCCURRENCES: usize = 2;
/// The most frequent words of a book are too common to learn, up to this many.
const COMMON_WORDS: usize = 300;
/// ...but never more than one in this many of the book's distinct words, so a
/// short text does not rule out everything it contains.
const COMMON_SHARE: usize = 10;
/// Abbreviations whose period does not end a sentence.
const ABBREVIATIONS: &[&str] = &["mr", "mrs", "ms", "dr", "st", "jr", "sr", "messrs"];

/// A chosen word and the sentence that gives it context.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub word: String,
    pub context: String,
}

/// What the book does with one word, spelled in lower case.
#[derive(Debug, Default)]
struct Usage {
    count: usize,
    /// Position among all tokens of the first appearance, in any case.
    first: usize,
    /// Position of the first appearance in lower case, if there is one.
    first_lower: Option<usize>,
    /// Index of the first sentence that has the word in lower case.
    first_lower_sentence: Option<usize>,
}

/// Up to `max` words of at least `min_length` letters, in order of first
/// appearance, each with its context.
///
/// A word qualifies when it is not a function word, not among the book's most
/// common words, appears at least twice and at least once in lower case (which
/// leaves out names), and has a sentence of useful length to quote.
pub fn candidates(text: &str, min_length: usize, max: usize) -> Vec<Candidate> {
    let sentences = sentences(&clean(text));
    let usage = count_words(&sentences);
    let common = common_words(&usage);

    let mut chosen: Vec<(usize, Candidate)> = Vec::new();
    for (word, used) in &usage {
        let (Some(position), Some(_)) = (used.first_lower, used.first_lower_sentence) else {
            continue;
        };
        if word.len() < min_length
            || used.count < MIN_OCCURRENCES
            || is_stopword(word)
            || common.contains(word.as_str())
        {
            continue;
        }
        if let Some(context) = context_for(&sentences, word) {
            chosen.push((
                position,
                Candidate {
                    word: word.clone(),
                    context,
                },
            ));
        }
    }
    chosen.sort_by_key(|(position, _)| *position);
    chosen.into_iter().take(max).map(|(_, c)| c).collect()
}

fn count_words(sentences: &[String]) -> HashMap<String, Usage> {
    let mut usage: HashMap<String, Usage> = HashMap::new();
    let mut position = 0usize;
    for (index, sentence) in sentences.iter().enumerate() {
        for token in tokens(sentence) {
            let lower = token.to_ascii_lowercase();
            let is_lower = token == lower;
            let used = usage.entry(lower).or_insert_with(|| Usage {
                first: position,
                ..Usage::default()
            });
            used.count += 1;
            if is_lower {
                used.first_lower.get_or_insert(position);
                used.first_lower_sentence.get_or_insert(index);
            }
            position += 1;
        }
    }
    usage
}

/// The book's most frequent words (ties go to the one seen first). A word seen
/// no more often than a candidate must be is never "common", so on a short text
/// the cut does not fall among words that are all equally rare.
fn common_words(usage: &HashMap<String, Usage>) -> HashSet<&str> {
    let keep = COMMON_WORDS.min(usage.len() / COMMON_SHARE);
    let mut ranked: Vec<(&str, &Usage)> = usage.iter().map(|(w, u)| (w.as_str(), u)).collect();
    ranked.sort_by(|(_, a), (_, b)| b.count.cmp(&a.count).then(a.first.cmp(&b.first)));
    ranked
        .into_iter()
        .take(keep)
        .filter(|(_, used)| used.count > MIN_OCCURRENCES)
        .map(|(w, _)| w)
        .collect()
}

/// The first sentence long enough to quote that has `word` in lower case, cut
/// down around the word when it is too long.
fn context_for(sentences: &[String], word: &str) -> Option<String> {
    sentences
        .iter()
        .filter(|s| s.chars().count() >= MIN_CONTEXT_CHARS)
        .find(|s| tokens(s).any(|token| token == word))
        .map(|s| shorten_around(s, word))
}

/// Only the body of a Project Gutenberg text, hyphenated line breaks joined,
/// curly quotes straightened and `_italic_` marks dropped. Paragraph breaks
/// (blank lines) survive; other whitespace runs become one space.
fn clean(text: &str) -> String {
    let body = gutenberg_body(text.trim_start_matches('\u{feff}'));
    let mut joined = String::with_capacity(body.len());
    let mut lines = body.lines().peekable();
    while let Some(line) = lines.next() {
        let line = line.trim_end();
        match (line.strip_suffix('-'), lines.peek()) {
            // `lan-` then `terns` is one word; `--` is a dash, not a break.
            (Some(stem), Some(next))
                if !stem.ends_with('-') && next.starts_with(|c: char| c.is_alphabetic()) =>
            {
                joined.push_str(stem);
            }
            _ => {
                joined.push_str(line);
                joined.push('\n');
            }
        }
    }
    joined
        .chars()
        .filter(|&c| c != '_')
        .map(|c| match c {
            '\u{2018}' | '\u{2019}' => '\'',
            '\u{201c}' | '\u{201d}' => '"',
            other => other,
        })
        .collect()
}

/// The text between the `*** START OF` and `*** END OF` lines, or all of it
/// when either marker is missing.
fn gutenberg_body(text: &str) -> &str {
    let mut start = 0;
    let mut end = text.len();
    let mut offset = 0;
    let mut seen_start = false;
    for line in text.split_inclusive('\n') {
        let next = offset + line.len();
        if !seen_start && line.trim_start().starts_with("*** START OF") {
            seen_start = true;
            start = next;
        } else if seen_start && line.trim_start().starts_with("*** END OF") {
            end = offset;
            break;
        }
        offset = next;
    }
    &text[start..end]
}

/// Splits at `.`, `!` and `?` followed by whitespace (closing quotes stay with
/// the sentence), and at blank lines. Each sentence is on one line.
fn sentences(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    for paragraph in text.split("\n\n").flat_map(|p| p.split("\n\r\n")) {
        let flat = paragraph.split_whitespace().collect::<Vec<_>>().join(" ");
        let chars: Vec<char> = flat.chars().collect();
        let mut start = 0;
        let mut i = 0;
        while i < chars.len() {
            if matches!(chars[i], '.' | '!' | '?') {
                let mut end = i + 1;
                while end < chars.len() && matches!(chars[end], '"' | '\'' | ')' | ']') {
                    end += 1;
                }
                let at_break = end == chars.len() || chars[end] == ' ';
                if at_break && !(chars[i] == '.' && is_abbreviation(&chars[start..i])) {
                    push_sentence(&mut out, &chars[start..end]);
                    start = end;
                    i = end;
                    continue;
                }
            }
            i += 1;
        }
        push_sentence(&mut out, &chars[start..]);
    }
    out
}

fn push_sentence(out: &mut Vec<String>, chars: &[char]) {
    let sentence: String = chars.iter().collect();
    let sentence = sentence.trim();
    if !sentence.is_empty() {
        out.push(sentence.to_owned());
    }
}

/// Whether the text before a period ends in an abbreviation such as `Mr`.
fn is_abbreviation(before: &[char]) -> bool {
    let tail: String = before
        .iter()
        .rev()
        .take_while(|c| c.is_ascii_alphabetic())
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();
    ABBREVIATIONS.contains(&tail.to_ascii_lowercase().as_str())
}

/// Runs of ASCII letters; a run joined to an apostrophe (`don't`, `Elizabeth's`)
/// is not a word and is left out whole.
fn tokens(sentence: &str) -> impl Iterator<Item = &str> {
    sentence
        .split(|c: char| !(c.is_ascii_alphabetic() || c == '\''))
        .filter(|t| !t.is_empty() && !t.contains('\''))
}

/// `sentence` when it is short enough, else a window of it around `word`,
/// trimmed to whole words and marked with `…` where it was cut.
fn shorten_around(sentence: &str, word: &str) -> String {
    let chars: Vec<char> = sentence.chars().collect();
    if chars.len() <= MAX_CONTEXT_CHARS {
        return sentence.to_owned();
    }
    let at = find_word(&chars, word).unwrap_or(0);
    // Room for the two ellipses.
    let room = MAX_CONTEXT_CHARS - 2;
    let mut start = at.saturating_sub(room.saturating_sub(word.len()) / 2);
    let mut end = (start + room).min(chars.len());
    start = end.saturating_sub(room).min(start);
    if start > 0 {
        while start < at && chars[start - 1] != ' ' {
            start += 1;
        }
    }
    if end < chars.len() {
        while end > at + word.len() && chars[end] != ' ' {
            end -= 1;
        }
    }
    let body: String = chars[start..end].iter().collect();
    let body = body.trim();
    let lead = if start > 0 { "…" } else { "" };
    let trail = if end < chars.len() { "…" } else { "" };
    format!("{lead}{body}{trail}")
}

/// Char index of the first whole-word, lower-case appearance of `word`.
fn find_word(chars: &[char], word: &str) -> Option<usize> {
    let target: Vec<char> = word.chars().collect();
    let is_letter = |c: char| c.is_ascii_alphabetic() || c == '\'';
    (0..chars.len().saturating_sub(target.len() - 1)).find(|&i| {
        chars[i..i + target.len()] == target[..]
            && (i == 0 || !is_letter(chars[i - 1]))
            && chars.get(i + target.len()).is_none_or(|&c| !is_letter(c))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = include_str!("../../tests/fixtures/book/sample.txt");

    fn words(found: &[Candidate]) -> Vec<&str> {
        found.iter().map(|c| c.word.as_str()).collect()
    }

    fn context<'a>(found: &'a [Candidate], word: &str) -> &'a str {
        &found.iter().find(|c| c.word == word).unwrap().context
    }

    #[test]
    fn the_sample_yields_its_words_in_order_of_first_appearance() {
        let found = candidates(SAMPLE, 5, 50);
        assert_eq!(
            words(&found),
            [
                "harbours",
                "lanterns",
                "wandered",
                "gardens",
                "theory",
                "extraordinary",
                "quiet"
            ]
        );
    }

    #[test]
    fn text_outside_the_gutenberg_markers_is_ignored() {
        let found = candidates(SAMPLE, 5, 50);
        // Each repeats in the header or the footer, and nowhere in the body.
        for ignored in ["provenance", "licensing"] {
            assert!(!words(&found).contains(&ignored), "{ignored}");
        }
    }

    #[test]
    fn without_markers_the_whole_text_is_used() {
        let found = candidates("The provenance of it. A provenance again, truly.", 5, 50);
        assert_eq!(words(&found), ["provenance"]);
    }

    #[test]
    fn a_word_split_across_lines_by_a_hyphen_is_joined() {
        let found = candidates(SAMPLE, 5, 50);
        assert!(words(&found).contains(&"lanterns"));
        assert!(!words(&found).contains(&"terns"));
        assert_eq!(
            context(&found, "lanterns"),
            "The lanterns swayed above the pier while the tide came in slowly over the stones."
        );
    }

    #[test]
    fn a_dash_at_the_end_of_a_line_is_not_a_hyphenated_word() {
        let cleaned = clean("It was late --\nso they left.\nwell-\nknown now.");
        assert!(cleaned.contains("late --\nso"), "{cleaned:?}");
        assert!(cleaned.contains("wellknown now."), "{cleaned:?}");
    }

    #[test]
    fn names_that_are_only_ever_capitalized_are_left_out() {
        let found = candidates(SAMPLE, 5, 50);
        // `Wanderley` appears twice, always with a capital.
        assert!(!words(&found).contains(&"wanderley"));
    }

    #[test]
    fn a_word_seen_once_is_left_out() {
        let found = candidates(SAMPLE, 5, 50);
        assert!(!words(&found).contains(&"singular"));
    }

    #[test]
    fn contractions_are_not_split_into_words() {
        let found = candidates("They don't mind. Why don't they, truly? They don't.", 3, 50);
        assert!(!words(&found).contains(&"don"));
    }

    #[test]
    fn function_words_are_left_out() {
        let found = candidates(
            "Which road? Which one? Perhaps that one, perhaps not.",
            4,
            50,
        );
        assert!(found.is_empty(), "{found:?}");
    }

    #[test]
    fn the_most_common_words_of_a_long_book_are_left_out() {
        // Over 30 distinct words, so the cut keeps the 3 most frequent: `the`,
        // `river` (12 times) and `stones` (8). `quiet` appears 2 times.
        let mut text = String::new();
        for _ in 0..6 {
            text.push_str("The river ran past the old river bridge. ");
        }
        for _ in 0..4 {
            text.push_str("The stones near the old stones were wet. ");
        }
        text.push_str("A quiet hour came and a quiet hour went away from here. ");
        for i in 0..20 {
            text.push_str(&format!(
                "Filler{} sentence number {}. ",
                "x".repeat(i),
                "y".repeat(i)
            ));
        }
        let found = candidates(&text, 5, 50);
        let found = words(&found);
        assert!(!found.contains(&"river"), "{found:?}");
        assert!(found.contains(&"quiet"), "{found:?}");
    }

    #[test]
    fn minimum_length_counts_letters() {
        let found = candidates(SAMPLE, 8, 50);
        assert_eq!(
            words(&found),
            ["harbours", "lanterns", "wandered", "extraordinary"]
        );
        assert!(words(&found).iter().all(|w| w.len() >= 8));
    }

    #[test]
    fn max_limits_the_number_of_words_keeping_the_earliest() {
        let found = candidates(SAMPLE, 5, 3);
        assert_eq!(words(&found), ["harbours", "lanterns", "wandered"]);
        assert!(candidates(SAMPLE, 5, 0).is_empty());
    }

    #[test]
    fn the_context_is_the_first_sentence_with_the_word_in_lower_case() {
        let found = candidates(SAMPLE, 5, 50);
        // The sentence before the one with `wandered` names `Wanderley` only.
        assert_eq!(
            context(&found, "wandered"),
            "Wanderley was a man who wandered; he had wandered through every harbour on the coast."
        );
        // `Gardens` opens the sentence; the lower-case use is in the same one.
        assert!(context(&found, "gardens").starts_with("Gardens grew"));
    }

    #[test]
    fn a_fragment_is_never_the_context() {
        let found = candidates(SAMPLE, 5, 50);
        // `Quiet harbours.` is 15 characters, so the second sentence is quoted.
        assert_eq!(
            context(&found, "harbours"),
            "By morning the harbours were busy again, and nobody remembered the singular quiet of the night before."
        );
    }

    #[test]
    fn a_word_with_no_sentence_long_enough_is_left_out() {
        assert!(candidates("Quiet harbours. Quiet harbours.", 5, 50).is_empty());
    }

    #[test]
    fn a_long_sentence_is_cut_around_the_word_with_ellipses() {
        let found = candidates(SAMPLE, 5, 50);
        let quoted = context(&found, "extraordinary");
        assert!(quoted.starts_with('…') && quoted.ends_with('…'), "{quoted}");
        assert!(quoted.chars().count() <= MAX_CONTEXT_CHARS, "{quoted}");
        assert!(quoted.contains("extraordinary"));
        // Cut at word boundaries, not inside a word.
        let inner = quoted.trim_matches('…');
        assert!(!inner.starts_with(' ') && !inner.ends_with(' '));
        assert!(inner.split(' ').all(|w| !w.is_empty()));
    }

    #[test]
    fn a_long_sentence_cut_at_one_end_has_one_ellipsis() {
        let sentence = format!("{} lanterns", "word ".repeat(80));
        let shortened = shorten_around(&sentence, "lanterns");
        assert!(shortened.starts_with('…'), "{shortened}");
        assert!(shortened.ends_with("lanterns"), "{shortened}");
        assert!(shortened.chars().count() <= MAX_CONTEXT_CHARS);
        let sentence = format!("lanterns {}", "word ".repeat(80));
        let shortened = shorten_around(sentence.trim_end(), "lanterns");
        assert!(shortened.starts_with("lanterns") && shortened.ends_with('…'));
        assert!(shortened.chars().count() <= MAX_CONTEXT_CHARS);
    }

    #[test]
    fn a_sentence_within_the_limit_is_kept_whole() {
        let sentence = "The lanterns swayed above the pier.";
        assert_eq!(shorten_around(sentence, "lanterns"), sentence);
    }

    #[test]
    fn a_title_does_not_end_a_sentence() {
        let found = sentences("Mr. Darcy bowed. Mrs. Bennet and Dr. Jones smiled! Done? Yes.");
        assert_eq!(
            found,
            [
                "Mr. Darcy bowed.",
                "Mrs. Bennet and Dr. Jones smiled!",
                "Done?",
                "Yes."
            ]
        );
    }

    #[test]
    fn a_closing_quote_stays_with_its_sentence_and_blank_lines_split() {
        let found = sentences("\"Go now.\" She left.\n\nChapter Two\n\nIt rained.");
        assert_eq!(
            found,
            ["\"Go now.\"", "She left.", "Chapter Two", "It rained."]
        );
    }

    #[test]
    fn curly_quotes_become_straight_and_italic_marks_go() {
        let cleaned = clean("\u{201c}It\u{2019}s _very_ odd,\u{201d} she said.");
        assert_eq!(cleaned.trim_end(), "\"It's very odd,\" she said.");
    }

    #[test]
    fn a_byte_order_mark_and_crlf_line_endings_are_handled() {
        let text = "\u{feff}*** START OF X ***\r\nThe lanterns swayed above the pier.\r\n\r\nThe lanterns glowed all night long.\r\n*** END OF X ***\r\n";
        let found = candidates(text, 5, 50);
        assert_eq!(words(&found), ["lanterns"]);
        assert_eq!(
            context(&found, "lanterns"),
            "The lanterns swayed above the pier."
        );
    }
}
