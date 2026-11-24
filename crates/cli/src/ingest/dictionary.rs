//! Free Dictionary API: turning an answer into a `VocabBody`, and asking for it.
//!
//! `map_entry` is pure so fixtures can test it. `Dictionary` owns the request
//! pacing and the retries, and takes its transport and its sleeping as
//! closures so tests neither touch the network nor wait.

use std::fmt;
use std::time::{Duration, Instant};

use envelope::{Meaning, VocabBody};
use serde_json::Value;

pub const DEFAULT_URL: &str = "https://api.dictionaryapi.dev/api/v2/entries/en";
pub const USER_AGENT: &str = "os-widget-ingest";

/// Smallest gap between two requests to the API.
const MIN_GAP: Duration = Duration::from_millis(300);
/// Waits before each retry of a 429 or 5xx answer.
const RETRY_WAITS: [Duration; 3] = [
    Duration::from_secs(1),
    Duration::from_secs(2),
    Duration::from_secs(4),
];
const MAX_MEANINGS: usize = 3;
const MAX_RELATED: usize = 6;

/// Why a word is not stored. The text is what the report prints after `skip <word>`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SkipReason {
    NotFound,
    /// The API answered with this status after the retries.
    DictionaryStatus(u16),
    /// The request itself failed, for example a refused connection.
    DictionaryUnreachable(String),
    /// The answer is not the JSON shape the mapping expects.
    UnexpectedResponse,
    MissingIpa,
    NoDefinition,
    /// The mapped body fails the shared vocab rules.
    Invalid { field: String, message: String },
}

impl fmt::Display for SkipReason {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            SkipReason::NotFound => write!(f, "not found"),
            SkipReason::DictionaryStatus(status) => write!(f, "dictionary error {status}"),
            SkipReason::DictionaryUnreachable(why) => write!(f, "dictionary error: {why}"),
            SkipReason::UnexpectedResponse => write!(f, "unexpected dictionary response"),
            SkipReason::MissingIpa => write!(f, "missing ipa"),
            SkipReason::NoDefinition => write!(f, "no definition"),
            SkipReason::Invalid { field, message } => write!(f, "invalid {field}: {message}"),
        }
    }
}

/// Maps the API's answer for `word` (an array of entries) to a vocab body.
///
/// The API has no context sentence, so `context` stays unset.
pub fn map_entry(word: &str, json: &Value) -> Result<VocabBody, SkipReason> {
    let entries = json
        .as_array()
        .filter(|entries| entries.iter().all(Value::is_object))
        .ok_or(SkipReason::UnexpectedResponse)?;
    if entries.is_empty() {
        return Err(SkipReason::UnexpectedResponse);
    }

    let ipa = first_ipa(entries).ok_or(SkipReason::MissingIpa)?;
    let groups: Vec<&Value> = entries
        .iter()
        .flat_map(|entry| array(entry, "meanings"))
        .collect();
    let chosen = main_group(&groups).ok_or(SkipReason::NoDefinition)?;

    let meanings: Vec<Meaning> = array(chosen, "definitions")
        .filter_map(|definition| {
            Some(Meaning {
                definition: text(definition, "definition")?.to_owned(),
                examples: text(definition, "example")
                    .map(|example| vec![example.to_owned()])
                    .unwrap_or_default(),
            })
        })
        .take(MAX_MEANINGS)
        .collect();
    if meanings.is_empty() {
        return Err(SkipReason::NoDefinition);
    }

    let body = VocabBody {
        word: word.to_owned(),
        ipa,
        pos: chosen
            .get("partOfSpeech")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        audio_url: first_audio(entries),
        meanings,
        context: None,
        synonyms: related(chosen, &groups, "synonyms"),
        antonyms: related(chosen, &groups, "antonyms"),
    };
    envelope::check_vocab(&body, "").map_err(|e| SkipReason::Invalid {
        field: e.field,
        message: e.message,
    })?;
    Ok(body)
}

/// Items of the array under `key`, or nothing.
fn array<'a>(value: &'a Value, key: &str) -> impl Iterator<Item = &'a Value> {
    value
        .get(key)
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
}

/// A non-blank string under `key`, trimmed.
fn text<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|s| !s.is_empty())
}

/// The first non-blank `phonetic` of an entry, else the first non-blank
/// `phonetics[].text` of any entry.
fn first_ipa(entries: &[Value]) -> Option<String> {
    entries
        .iter()
        .find_map(|entry| text(entry, "phonetic"))
        .or_else(|| {
            entries
                .iter()
                .flat_map(|entry| array(entry, "phonetics"))
                .find_map(|p| text(p, "text"))
        })
        .map(str::to_owned)
}

/// The group with the most definitions; the earlier one wins a tie.
fn main_group<'a>(groups: &[&'a Value]) -> Option<&'a Value> {
    let mut best: Option<(&'a Value, usize)> = None;
    for group in groups {
        let count = array(group, "definitions").count();
        if count > 0 && best.is_none_or(|(_, most)| count > most) {
            best = Some((group, count));
        }
    }
    best.map(|(group, _)| group)
}

/// Synonyms or antonyms: the chosen group's own, then its definitions', then the
/// same for the other groups; no repeats, at most `MAX_RELATED`.
fn related(chosen: &Value, groups: &[&Value], key: &str) -> Vec<String> {
    let others = groups.iter().filter(|g| !std::ptr::eq(**g, chosen));
    let mut out: Vec<String> = Vec::new();
    for group in std::iter::once(chosen).chain(others.copied()) {
        let own = array(group, key);
        let nested = array(group, "definitions").flat_map(|d| array(d, key));
        for word in own.chain(nested).filter_map(Value::as_str) {
            let word = word.trim();
            if !word.is_empty() && !out.iter().any(|seen| seen == word) {
                out.push(word.to_owned());
            }
        }
    }
    out.truncate(MAX_RELATED);
    out
}

/// The first non-blank audio, preferring a US recording; `//host/x` becomes
/// `https://host/x`, and anything that is then not HTTPS is dropped.
fn first_audio(entries: &[Value]) -> Option<String> {
    let all: Vec<&str> = entries
        .iter()
        .flat_map(|entry| array(entry, "phonetics"))
        .filter_map(|p| text(p, "audio"))
        .collect();
    let chosen = all
        .iter()
        .find(|url| url.ends_with("-us.mp3"))
        .or_else(|| all.first())?;
    let url = match chosen.strip_prefix("//") {
        Some(rest) => format!("https://{rest}"),
        None => (*chosen).to_owned(),
    };
    url.starts_with("https://").then_some(url)
}

/// A looked-up answer: status and body text, or a transport error message.
pub type Fetched = Result<(u16, String), String>;

/// Asks the API for words one at a time, pacing and retrying as the API asks.
pub struct Dictionary<F, S> {
    base_url: String,
    fetch: F,
    sleep: S,
    last_request: Option<Instant>,
}

impl<F, S> Dictionary<F, S>
where
    F: FnMut(&str) -> Fetched,
    S: FnMut(Duration),
{
    pub fn new(base_url: &str, fetch: F, sleep: S) -> Self {
        Self {
            base_url: base_url.trim().trim_end_matches('/').to_owned(),
            fetch,
            sleep,
            last_request: None,
        }
    }

    /// Returns the parsed answer for an already normalized word.
    pub fn lookup(&mut self, word: &str) -> Result<Value, SkipReason> {
        let url = format!("{}/{}", self.base_url, url_segment(word));
        let mut retries = RETRY_WAITS.iter();
        loop {
            self.pace();
            let answer = (self.fetch)(&url);
            self.last_request = Some(Instant::now());
            let (status, body) = match answer {
                Ok(answer) => answer,
                Err(why) => return Err(SkipReason::DictionaryUnreachable(why)),
            };
            match status {
                200 => {
                    return serde_json::from_str(&body)
                        .map_err(|_| SkipReason::UnexpectedResponse);
                }
                404 => return Err(SkipReason::NotFound),
                429 | 500..=599 => match retries.next() {
                    Some(wait) => (self.sleep)(*wait),
                    None => return Err(SkipReason::DictionaryStatus(status)),
                },
                other => return Err(SkipReason::DictionaryStatus(other)),
            }
        }
    }

    /// Sleeps for whatever is left of the minimum gap since the last request.
    fn pace(&mut self) {
        if let Some(last) = self.last_request {
            let left = MIN_GAP.saturating_sub(last.elapsed());
            if !left.is_zero() {
                (self.sleep)(left);
            }
        }
    }
}

impl Dictionary<Box<dyn FnMut(&str) -> Fetched>, fn(Duration)> {
    /// The real thing: HTTPS requests and sleeping the thread.
    pub fn http(base_url: &str) -> Self {
        let agent: ureq::Agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .timeout_global(Some(Duration::from_secs(30)))
            .user_agent(USER_AGENT)
            .build()
            .into();
        let fetch = move |url: &str| -> Fetched {
            let mut response = agent.get(url).call().map_err(|e| e.to_string())?;
            let status = response.status().as_u16();
            let body = response
                .body_mut()
                .read_to_string()
                .map_err(|e| e.to_string())?;
            Ok((status, body))
        };
        Dictionary::new(base_url, Box::new(fetch), std::thread::sleep)
    }
}

/// Percent-encodes what a normalized word may contain beyond letters.
fn url_segment(word: &str) -> String {
    let mut out = String::with_capacity(word.len());
    for ch in word.chars() {
        if ch.is_ascii_alphanumeric() || ch == '-' {
            out.push(ch);
        } else {
            let mut buf = [0u8; 4];
            for byte in ch.encode_utf8(&mut buf).bytes() {
                out.push_str(&format!("%{byte:02X}"));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::VecDeque;
    use std::rc::Rc;

    fn fixture(name: &str) -> Value {
        let path = format!(
            "{}/tests/fixtures/dictionary/{name}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    fn mapped(word: &str) -> VocabBody {
        map_entry(word, &fixture(word)).unwrap()
    }

    #[test]
    fn serendipity_maps_every_field_the_api_has() {
        let body = mapped("serendipity");
        assert_eq!(body.word, "serendipity");
        assert_eq!(body.ipa, "/ˌsɛ.ɹən.ˈdɪ.pɪ.ti/");
        assert_eq!(body.pos, "noun");
        assert_eq!(
            body.audio_url.as_deref(),
            Some("https://api.dictionaryapi.dev/media/pronunciations/en/serendipity-us.mp3")
        );
        assert_eq!(body.meanings.len(), 2);
        assert_eq!(body.context, None);
        assert_eq!(body.synonyms, vec!["chance", "luck"]);
        assert_eq!(body.antonyms, vec!["Murphy's law", "perfect storm"]);
        envelope::check_vocab(&body, "").unwrap();
    }

    #[test]
    fn candid_takes_the_part_of_speech_with_most_definitions() {
        let body = mapped("candid");
        assert_eq!(body.pos, "adjective");
        assert_eq!(body.meanings.len(), 3);
        // The three adjective definitions, not the single noun one.
        let noun_definition = fixture("candid")[0]["meanings"][0]["definitions"][0]["definition"]
            .as_str()
            .unwrap()
            .to_owned();
        assert!(body.meanings.iter().all(|m| m.definition != noun_definition));
        assert_eq!(body.synonyms[..2], ["frank", "open"]);
    }

    #[test]
    fn resilient_is_skipped_for_missing_ipa() {
        let reason = map_entry("resilient", &fixture("resilient")).unwrap_err();
        assert_eq!(reason, SkipReason::MissingIpa);
        assert_eq!(reason.to_string(), "missing ipa");
        let reason = map_entry("lanterns", &fixture("lanterns")).unwrap_err();
        assert_eq!(reason, SkipReason::MissingIpa);
    }

    #[test]
    fn wandered_keeps_examples_and_synonyms() {
        let body = mapped("wandered");
        assert_eq!(body.pos, "verb");
        assert_eq!(body.meanings.len(), 3);
        assert_eq!(body.meanings[0].examples, vec!["to wander over the fields"]);
        assert_eq!(
            body.meanings[1].examples,
            vec!["A writer wanders from his subject."]
        );
        assert!(body.meanings[2].examples.is_empty());
        assert_eq!(body.synonyms, vec!["cheat", "drift", "err", "roam"]);
        assert!(body.antonyms.is_empty());
    }

    #[test]
    fn benevolent_without_audio_has_no_audio_url() {
        let body = mapped("benevolent");
        assert_eq!(body.audio_url, None);
        assert_eq!(body.antonyms, vec!["malevolent"]);
    }

    fn entry(json: Value) -> Value {
        Value::Array(vec![json])
    }

    #[test]
    fn ipa_prefers_phonetic_over_phonetics_text() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "phonetics": [{"text": "/b/"}],
            "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "d"}]}]
        }));
        assert_eq!(map_entry("w", &json).unwrap().ipa, "/a/");
    }

    #[test]
    fn ipa_falls_back_to_first_nonblank_phonetics_text() {
        let json = entry(serde_json::json!({
            "phonetic": " ",
            "phonetics": [{"text": ""}, {"text": "/b/"}, {"text": "/c/"}],
            "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "d"}]}]
        }));
        assert_eq!(map_entry("w", &json).unwrap().ipa, "/b/");
    }

    #[test]
    fn ipa_is_found_on_a_later_entry() {
        let json = serde_json::json!([
            {"phonetics": [], "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "d"}]}]},
            {"phonetic": "/z/", "phonetics": [], "meanings": []}
        ]);
        assert_eq!(map_entry("w", &json).unwrap().ipa, "/z/");
    }

    #[test]
    fn equal_definition_counts_pick_the_earlier_group() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "meanings": [
                {"partOfSpeech": "noun", "definitions": [{"definition": "n1"}, {"definition": "n2"}]},
                {"partOfSpeech": "verb", "definitions": [{"definition": "v1"}, {"definition": "v2"}]}
            ]
        }));
        assert_eq!(map_entry("w", &json).unwrap().pos, "noun");
    }

    #[test]
    fn meanings_are_capped_at_three() {
        let defs: Vec<Value> = (0..5)
            .map(|i| serde_json::json!({"definition": format!("d{i}")}))
            .collect();
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "meanings": [{"partOfSpeech": "noun", "definitions": defs}]
        }));
        let body = map_entry("w", &json).unwrap();
        let got: Vec<_> = body.meanings.iter().map(|m| m.definition.as_str()).collect();
        assert_eq!(got, ["d0", "d1", "d2"]);
    }

    #[test]
    fn related_words_dedupe_keep_order_and_stop_at_six() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "meanings": [
                {"partOfSpeech": "noun", "synonyms": ["a", "b"],
                 "definitions": [{"definition": "d", "synonyms": ["b", "c", "d"]}]},
                {"partOfSpeech": "verb", "synonyms": ["e", "a", "f", "g"],
                 "definitions": [{"definition": "d"}]}
            ]
        }));
        let body = map_entry("w", &json).unwrap();
        assert_eq!(body.synonyms, vec!["a", "b", "c", "d", "e", "f"]);
    }

    #[test]
    fn chosen_group_related_words_come_before_other_groups() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "meanings": [
                {"partOfSpeech": "noun", "synonyms": ["other"], "definitions": [{"definition": "d"}]},
                {"partOfSpeech": "verb", "synonyms": ["mine"],
                 "definitions": [{"definition": "d1"}, {"definition": "d2"}]}
            ]
        }));
        assert_eq!(map_entry("w", &json).unwrap().synonyms, vec!["mine", "other"]);
    }

    #[test]
    fn audio_prefers_us_and_gets_https() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "phonetics": [
                {"audio": ""},
                {"audio": "//x.example/w-uk.mp3"},
                {"audio": "//x.example/w-us.mp3"}
            ],
            "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "d"}]}]
        }));
        assert_eq!(
            map_entry("w", &json).unwrap().audio_url.as_deref(),
            Some("https://x.example/w-us.mp3")
        );
    }

    #[test]
    fn audio_that_is_not_https_is_dropped_but_the_word_is_kept() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "phonetics": [{"audio": "http://x.example/w.mp3"}],
            "meanings": [{"partOfSpeech": "noun", "definitions": [{"definition": "d"}]}]
        }));
        let body = map_entry("w", &json).unwrap();
        assert_eq!(body.audio_url, None);
    }

    #[test]
    fn an_answer_without_definitions_is_skipped() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "meanings": [{"partOfSpeech": "noun", "definitions": []}]
        }));
        assert_eq!(map_entry("w", &json).unwrap_err(), SkipReason::NoDefinition);
    }

    #[test]
    fn a_blank_part_of_speech_fails_the_shared_check() {
        let json = entry(serde_json::json!({
            "phonetic": "/a/",
            "meanings": [{"partOfSpeech": " ", "definitions": [{"definition": "d"}]}]
        }));
        let reason = map_entry("w", &json).unwrap_err();
        assert!(matches!(&reason, SkipReason::Invalid { field, .. } if field == "pos"));
        assert!(reason.to_string().starts_with("invalid pos:"));
    }

    #[test]
    fn a_surprising_shape_is_skipped_not_a_panic() {
        for json in [
            serde_json::json!({"title": "No Definitions Found"}),
            serde_json::json!([]),
            serde_json::json!([42]),
            serde_json::json!("nope"),
        ] {
            assert!(map_entry("w", &json).is_err(), "{json}");
        }
    }

    /// A dictionary whose answers are scripted and whose sleeps are recorded.
    struct Script {
        urls: Rc<RefCell<Vec<String>>>,
        sleeps: Rc<RefCell<Vec<Duration>>>,
    }

    fn scripted(
        base: &str,
        answers: Vec<Fetched>,
    ) -> (
        Dictionary<impl FnMut(&str) -> Fetched, impl FnMut(Duration)>,
        Script,
    ) {
        let urls = Rc::new(RefCell::new(Vec::new()));
        let sleeps = Rc::new(RefCell::new(Vec::new()));
        let mut answers: VecDeque<Fetched> = answers.into();
        let (u, s) = (urls.clone(), sleeps.clone());
        let dictionary = Dictionary::new(
            base,
            move |url: &str| {
                u.borrow_mut().push(url.to_owned());
                answers.pop_front().expect("more requests than answers")
            },
            move |d| s.borrow_mut().push(d),
        );
        (dictionary, Script { urls, sleeps })
    }

    fn ok(body: &str) -> Fetched {
        Ok((200, body.to_owned()))
    }

    fn status(code: u16) -> Fetched {
        Ok((code, String::new()))
    }

    #[test]
    fn lookup_requests_the_word_under_the_base_url() {
        let (mut dict, script) = scripted("http://dict.test/en/", vec![ok("[]")]);
        assert_eq!(dict.lookup("candid").unwrap(), serde_json::json!([]));
        assert_eq!(script.urls.borrow().as_slice(), ["http://dict.test/en/candid"]);
    }

    #[test]
    fn apostrophes_are_percent_encoded_in_the_url() {
        let (mut dict, script) = scripted("http://dict.test", vec![ok("[]")]);
        dict.lookup("o'clock").unwrap();
        assert_eq!(script.urls.borrow().as_slice(), ["http://dict.test/o%27clock"]);
    }

    #[test]
    fn not_found_is_a_skip_without_retries() {
        let (mut dict, script) = scripted("http://d", vec![status(404)]);
        assert_eq!(dict.lookup("zzz").unwrap_err(), SkipReason::NotFound);
        assert_eq!(script.urls.borrow().len(), 1);
        assert!(script.sleeps.borrow().is_empty());
    }

    #[test]
    fn rate_limit_and_server_errors_retry_after_1_2_and_4_seconds() {
        let (mut dict, script) = scripted(
            "http://d",
            vec![status(429), status(503), status(500), ok("[]")],
        );
        assert!(dict.lookup("w").is_ok());
        assert_eq!(script.urls.borrow().len(), 4);
        let waits: Vec<_> = script
            .sleeps
            .borrow()
            .iter()
            .copied()
            .filter(|d| *d >= Duration::from_secs(1))
            .collect();
        assert_eq!(
            waits,
            [
                Duration::from_secs(1),
                Duration::from_secs(2),
                Duration::from_secs(4)
            ]
        );
    }

    #[test]
    fn giving_up_after_three_retries_reports_the_status() {
        let (mut dict, script) = scripted(
            "http://d",
            vec![status(429), status(429), status(429), status(429)],
        );
        let reason = dict.lookup("w").unwrap_err();
        assert_eq!(reason, SkipReason::DictionaryStatus(429));
        assert_eq!(reason.to_string(), "dictionary error 429");
        assert_eq!(script.urls.borrow().len(), 4);
    }

    #[test]
    fn other_statuses_and_transport_errors_are_not_retried() {
        let (mut dict, script) = scripted("http://d", vec![status(403)]);
        assert_eq!(dict.lookup("w").unwrap_err(), SkipReason::DictionaryStatus(403));
        assert_eq!(script.urls.borrow().len(), 1);

        let (mut dict, _) = scripted("http://d", vec![Err("connection refused".into())]);
        assert_eq!(
            dict.lookup("w").unwrap_err().to_string(),
            "dictionary error: connection refused"
        );
    }

    #[test]
    fn a_200_that_is_not_json_is_unexpected() {
        let (mut dict, _) = scripted("http://d", vec![ok("<html>")]);
        assert_eq!(dict.lookup("w").unwrap_err(), SkipReason::UnexpectedResponse);
    }

    #[test]
    fn consecutive_lookups_are_spaced_by_at_least_300_ms() {
        let (mut dict, script) = scripted("http://d", vec![ok("[]"), ok("[]")]);
        dict.lookup("a").unwrap();
        assert!(script.sleeps.borrow().is_empty(), "the first request waits for nothing");
        dict.lookup("b").unwrap();
        let sleeps = script.sleeps.borrow();
        assert_eq!(sleeps.len(), 1);
        assert!(sleeps[0] > Duration::from_millis(250) && sleeps[0] <= MIN_GAP, "{sleeps:?}");
    }
}
