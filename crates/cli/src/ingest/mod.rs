//! `os-widget ingest`: fill the vocabulary from outside sources.
//!
//! `words` looks each word up in the Free Dictionary API, drops the ones the API
//! cannot complete, and sends the rest in batches to `POST /vocab/words`. Words
//! stored by an earlier batch stay stored when a later one fails; ingesting again
//! is safe because the server upserts.

pub mod dictionary;

use std::io::Write;
use std::time::Duration;

use envelope::VocabBody;
use serde_json::{Value, json};

use crate::{Report, WordsArgs, read_input, resolve_server, resolve_token, snippet};
use dictionary::{Dictionary, Fetched};

pub const DEFAULT_ORIGIN: &str = "dictionaryapi.dev";

/// Words per request to the server.
const BATCH_SIZE: usize = 25;
/// The server refuses an `origin` longer than this.
const MAX_ORIGIN_CHARS: usize = 200;
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// A word list after normalizing: what to look up and what was never a word.
#[derive(Debug, Default, PartialEq, Eq)]
struct WordList {
    words: Vec<String>,
    rejected: Vec<String>,
}

/// One word per line; blank lines and `#` comments are ignored, words are
/// lower-cased and trimmed, repeats are dropped, and anything other than letters,
/// apostrophes and hyphens is rejected.
fn parse_word_list(text: &str) -> WordList {
    let mut list = WordList::default();
    for line in text.trim_start_matches('\u{feff}').lines() {
        let word = line.trim().to_lowercase();
        if word.is_empty() || word.starts_with('#') {
            continue;
        }
        let is_word = word.chars().any(char::is_alphabetic)
            && word
                .chars()
                .all(|c| c.is_alphabetic() || c == '\'' || c == '-');
        let seen = if is_word {
            &mut list.words
        } else {
            &mut list.rejected
        };
        if !seen.contains(&word) {
            seen.push(word);
        }
    }
    list
}

/// Where batches go.
#[derive(Debug, PartialEq, Eq)]
struct Target {
    words_url: String,
    token: String,
}

/// Sends one batch and returns how many words the server says it stored.
fn post_batch(target: &Target, origin: &str, batch: &[VocabBody]) -> Result<u64, Report> {
    let body = serde_json::to_vec(&json!({ "origin": origin, "words": batch }))
        .map_err(|e| Report::failure(format!("cannot serialize words: {e}")))?;
    // Status codes are answers to map, not transport errors.
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_global(Some(REQUEST_TIMEOUT))
        .build()
        .into();
    let mut response = agent
        .post(&target.words_url)
        .header("Authorization", format!("Bearer {}", target.token))
        .header("Content-Type", "application/json")
        .send(&body[..])
        .map_err(|e| Report::failure(format!("request to {} failed: {e}", target.words_url)))?;
    let status = response.status().as_u16();
    let text = response.body_mut().read_to_string().map_err(|e| {
        Report::failure(format!(
            "HTTP {status}: cannot read response from {}: {e}",
            target.words_url
        ))
    })?;
    interpret_batch_response(status, &text)
}

/// Turns the server's answer to `POST /vocab/words` into a stored count, or the
/// report to exit with.
fn interpret_batch_response(status: u16, body: &str) -> Result<u64, Report> {
    if status != 200 {
        return Err(crate::error_report("vocab", status, body));
    }
    serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|v| v.get("stored").and_then(Value::as_u64))
        .ok_or_else(|| {
            Report::failure(format!(
                "HTTP 200: response has no stored count: {}",
                snippet(body)
            ))
        })
}

/// Looks every word up, reports each on `progress`, and sends the valid ones
/// unless `target` is `None` (a dry run).
fn run_words<F, S>(
    list: &WordList,
    dictionary: &mut Dictionary<F, S>,
    origin: &str,
    target: Option<&Target>,
    progress: &mut dyn Write,
) -> Report
where
    F: FnMut(&str) -> Fetched,
    S: FnMut(Duration),
{
    let mut skipped = 0usize;
    let mut sink = Sink {
        origin,
        target,
        pending: Vec::new(),
        dry_run_bodies: Vec::new(),
        stored: 0,
    };

    for word in &list.rejected {
        let _ = writeln!(progress, "skip {word} invalid characters");
        skipped += 1;
    }
    for word in &list.words {
        let looked_up = dictionary
            .lookup(word)
            .and_then(|json| dictionary::map_entry(word, &json));
        match looked_up {
            Ok(body) => {
                let _ = writeln!(progress, "ok {word}");
                sink.pending.push(body);
            }
            Err(reason) => {
                let _ = writeln!(progress, "skip {word} {reason}");
                skipped += 1;
            }
        }
        if let Err(failed) = flush(&mut sink, BATCH_SIZE) {
            return with_summary(failed, sink.stored, skipped);
        }
    }
    if let Err(failed) = flush(&mut sink, 1) {
        return with_summary(failed, sink.stored, skipped);
    }

    match target {
        Some(_) => Report::ok(format!("stored {}, skipped {skipped}", sink.stored)),
        None => Report {
            stdout: Some(
                serde_json::to_string_pretty(&sink.dry_run_bodies).unwrap_or_else(|_| "[]".into()),
            ),
            stderr: Some(format!(
                "dry run: would store {}, skipped {skipped}",
                sink.dry_run_bodies.len()
            )),
            code: 0,
        },
    }
}

/// Words waiting to be sent, and what has been stored so far.
struct Sink<'a> {
    origin: &'a str,
    /// `None` in a dry run.
    target: Option<&'a Target>,
    pending: Vec<VocabBody>,
    /// Every body of a dry run, kept for printing.
    dry_run_bodies: Vec<VocabBody>,
    stored: u64,
}

/// Sends the pending words once there are at least `min` of them (or, in a dry
/// run, sets them aside for printing).
fn flush(sink: &mut Sink, min: usize) -> Result<(), Report> {
    if sink.pending.is_empty() || sink.pending.len() < min {
        return Ok(());
    }
    match sink.target {
        Some(target) => sink.stored += post_batch(target, sink.origin, &sink.pending)?,
        None => sink.dry_run_bodies.append(&mut sink.pending),
    }
    sink.pending.clear();
    Ok(())
}

/// A failed run still says how much was stored before it stopped.
fn with_summary(mut failed: Report, stored: u64, skipped: usize) -> Report {
    failed.stdout = Some(format!("stored {stored}, skipped {skipped}"));
    failed
}

/// `os-widget ingest words`.
pub fn words(args: WordsArgs) -> Report {
    let origin = args.origin.trim();
    if origin.is_empty() || origin.chars().count() > MAX_ORIGIN_CHARS {
        return Report {
            stdout: None,
            stderr: Some(format!(
                "invalid vocab: origin: must be 1 to {MAX_ORIGIN_CHARS} characters"
            )),
            code: crate::EXIT_INVALID,
        };
    }
    let target = if args.dry_run {
        None
    } else {
        let server = resolve_server(args.server.clone(), std::env::var(crate::SERVER_ENV).ok());
        let token = resolve_token(std::env::var(crate::TOKEN_ENV).ok());
        match (server, token) {
            (Ok(server), Ok(token)) => Some(Target {
                words_url: format!("{server}/vocab/words"),
                token,
            }),
            (Err(message), _) | (_, Err(message)) => return Report::failure(message),
        }
    };
    let text = match read_input(&args.path) {
        Ok(bytes) => match String::from_utf8(bytes) {
            Ok(text) => text,
            Err(_) => return Report::failure(format!("{} is not valid UTF-8 text", args.path)),
        },
        Err(e) => return Report::failure(format!("cannot read {}: {e}", args.path)),
    };

    let list = parse_word_list(&text);
    let mut dictionary = dictionary::http(&args.dictionary_url);
    run_words(
        &list,
        &mut dictionary,
        origin,
        target.as_ref(),
        &mut std::io::stderr(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read as _;
    use std::net::{TcpListener, TcpStream};
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::{Arc, Mutex};
    use std::thread::JoinHandle;

    // --- word list ---

    #[test]
    fn word_list_normalizes_and_dedupes() {
        let text = "\n# a comment\n  Serendipity  \nCANDID\n\ncandid\nserendipity\n   \n# more\nResilient\n";
        let list = parse_word_list(text);
        assert_eq!(list.words, ["serendipity", "candid", "resilient"]);
        assert!(list.rejected.is_empty());
    }

    #[test]
    fn word_list_rejects_anything_but_letters_apostrophes_and_hyphens() {
        let list =
            parse_word_list("ice cream\nwell-known\no'clock\nwi-fi2\n---\n'\nnaïve\nfoo.bar\n");
        assert_eq!(list.words, ["well-known", "o'clock", "naïve"]);
        assert_eq!(
            list.rejected,
            ["ice cream", "wi-fi2", "---", "'", "foo.bar"]
        );
    }

    #[test]
    fn word_list_ignores_a_byte_order_mark_and_crlf() {
        let list = parse_word_list("\u{feff}candid\r\nlucid\r\n");
        assert_eq!(list.words, ["candid", "lucid"]);
    }

    // --- server answers ---

    #[test]
    fn stored_count_comes_from_a_200() {
        assert_eq!(interpret_batch_response(200, r#"{"stored":3}"#).unwrap(), 3);
    }

    #[test]
    fn a_200_without_a_count_is_a_failure() {
        let report = interpret_batch_response(200, "{}").unwrap_err();
        assert_eq!(report.code, 1);
    }

    #[test]
    fn server_400_names_the_field_and_exits_2() {
        let body =
            r#"{"error":"invalid vocab","field":"words[3].ipa","message":"must not be empty"}"#;
        let report = interpret_batch_response(400, body).unwrap_err();
        assert_eq!(report.code, 2);
        assert_eq!(
            report.stderr.as_deref(),
            Some("invalid vocab: words[3].ipa: must not be empty")
        );
    }

    #[test]
    fn server_400_without_details_still_exits_2() {
        let report = interpret_batch_response(400, "Bad Request").unwrap_err();
        assert_eq!(report.code, 2);
        assert_eq!(
            report.stderr.as_deref(),
            Some("invalid vocab: HTTP 400: Bad Request")
        );
    }

    #[test]
    fn unauthorized_forbidden_and_server_errors_exit_1() {
        let unauthorized =
            interpret_batch_response(401, r#"{"error":"unauthorized"}"#).unwrap_err();
        assert_eq!(unauthorized.code, 1);
        assert_eq!(
            unauthorized.stderr.as_deref(),
            Some("HTTP 401: unauthorized (check OS_WIDGET_PUBLISH_TOKEN)")
        );
        let forbidden = interpret_batch_response(403, r#"{"error":"forbidden"}"#).unwrap_err();
        assert_eq!(forbidden.code, 1);
        assert!(forbidden.stderr.unwrap().contains("not a publish token"));
        let down = interpret_batch_response(502, "bad gateway").unwrap_err();
        assert_eq!(down.code, 1);
        assert_eq!(down.stderr.as_deref(), Some("HTTP 502: bad gateway"));
    }

    // --- a local server standing in for the dictionary and the Worker ---

    #[derive(Debug, Clone)]
    struct Recorded {
        method: String,
        path: String,
        authorization: Option<String>,
        user_agent: Option<String>,
        body: String,
    }

    struct FakeServer {
        url: String,
        requests: Arc<Mutex<Vec<Recorded>>>,
        stop: Arc<AtomicBool>,
        handle: Option<JoinHandle<()>>,
    }

    impl FakeServer {
        fn start(handler: impl Fn(&Recorded) -> (u16, String) + Send + 'static) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let url = format!("http://{}", listener.local_addr().unwrap());
            let requests = Arc::new(Mutex::new(Vec::new()));
            let stop = Arc::new(AtomicBool::new(false));
            let (log, halt) = (requests.clone(), stop.clone());
            let handle = std::thread::spawn(move || {
                for stream in listener.incoming() {
                    if halt.load(Ordering::SeqCst) {
                        break;
                    }
                    let Ok(mut stream) = stream else { continue };
                    let Some(request) = read_request(&mut stream) else {
                        continue;
                    };
                    let (status, body) = handler(&request);
                    log.lock().unwrap().push(request);
                    let response = format!(
                        "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    );
                    let _ = stream.write_all(response.as_bytes());
                }
            });
            Self {
                url,
                requests,
                stop,
                handle: Some(handle),
            }
        }

        fn requests(&self) -> Vec<Recorded> {
            self.requests.lock().unwrap().clone()
        }

        fn posts(&self) -> Vec<Recorded> {
            self.requests()
                .into_iter()
                .filter(|r| r.method == "POST")
                .collect()
        }
    }

    impl Drop for FakeServer {
        fn drop(&mut self) {
            self.stop.store(true, Ordering::SeqCst);
            let _ = TcpStream::connect(self.url.trim_start_matches("http://"));
            if let Some(handle) = self.handle.take() {
                let _ = handle.join();
            }
        }
    }

    fn read_request(stream: &mut TcpStream) -> Option<Recorded> {
        let mut data = Vec::new();
        let mut chunk = [0u8; 4096];
        let split = loop {
            let n = stream.read(&mut chunk).ok()?;
            if n == 0 {
                return None;
            }
            data.extend_from_slice(&chunk[..n]);
            if let Some(i) = data.windows(4).position(|w| w == b"\r\n\r\n") {
                break i + 4;
            }
        };
        let head = String::from_utf8_lossy(&data[..split]).into_owned();
        let header = |name: &str| {
            head.lines().find_map(|l| {
                let (k, v) = l.split_once(':')?;
                k.eq_ignore_ascii_case(name).then(|| v.trim().to_owned())
            })
        };
        let length: usize = header("content-length")
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        while data.len() < split + length {
            let n = stream.read(&mut chunk).ok()?;
            if n == 0 {
                break;
            }
            data.extend_from_slice(&chunk[..n]);
        }
        let mut first = head.lines().next()?.split_whitespace();
        Some(Recorded {
            method: first.next()?.to_owned(),
            path: first.next()?.to_owned(),
            authorization: header("authorization"),
            user_agent: header("user-agent"),
            body: String::from_utf8_lossy(&data[split..]).into_owned(),
        })
    }

    fn fixture_text(word: &str) -> Option<String> {
        let path = format!(
            "{}/tests/fixtures/dictionary/{word}.json",
            env!("CARGO_MANIFEST_DIR")
        );
        std::fs::read_to_string(path).ok()
    }

    /// The API for fixture words, 404 for `unknownword`, and a generic complete
    /// answer for any other word; the Worker answers `stored` with the batch size.
    fn worker_and_dictionary(worker_status: u16, worker_body: Option<&'static str>) -> FakeServer {
        FakeServer::start(move |r| {
            if r.method == "POST" {
                if worker_status != 200 {
                    return (worker_status, worker_body.unwrap_or("{}").to_owned());
                }
                let sent: Value = serde_json::from_str(&r.body).unwrap();
                let n = sent["words"].as_array().unwrap().len();
                return (200, json!({ "stored": n }).to_string());
            }
            let word = r.path.rsplit('/').next().unwrap();
            if word == "unknownword" {
                return (404, r#"{"title":"No Definitions Found"}"#.into());
            }
            match fixture_text(word) {
                Some(text) => (200, text),
                None => (
                    200,
                    json!([{ "phonetic": "/x/", "meanings": [
                        { "partOfSpeech": "noun", "definitions": [{ "definition": format!("about {word}") }] }
                    ]}])
                    .to_string(),
                ),
            }
        })
    }

    /// `n` different words made of letters only, one per line.
    fn distinct_words(n: usize) -> String {
        (0..n)
            .map(|i| {
                let (hi, lo) = (b'a' + (i / 26) as u8, b'a' + (i % 26) as u8);
                format!("w{}{}\n", hi as char, lo as char)
            })
            .collect()
    }

    fn run(server: &FakeServer, text: &str, send: bool) -> (Report, String) {
        let list = parse_word_list(text);
        let mut dictionary = Dictionary::new(
            &format!("{}/dict", server.url),
            dictionary::http_fetch(),
            |_| {},
        );
        let target = Target {
            words_url: format!("{}/vocab/words", server.url),
            token: "secret-token".into(),
        };
        let mut progress = Vec::new();
        let report = run_words(
            &list,
            &mut dictionary,
            DEFAULT_ORIGIN,
            send.then_some(&target),
            &mut progress,
        );
        (report, String::from_utf8(progress).unwrap())
    }

    #[test]
    fn five_sample_words_store_four_and_skip_the_one_without_ipa() {
        let server = worker_and_dictionary(200, None);
        let (report, progress) = run(
            &server,
            "serendipity\ncandid\nresilient\nwandered\nbenevolent\n",
            true,
        );
        assert_eq!(report.code, 0, "{report:?}");
        assert_eq!(report.stdout.as_deref(), Some("stored 4, skipped 1"));
        assert_eq!(
            progress,
            "ok serendipity\nok candid\nskip resilient missing ipa\nok wandered\nok benevolent\n"
        );
        let posts = server.posts();
        assert_eq!(posts.len(), 1);
        assert_eq!(posts[0].path, "/vocab/words");
        assert_eq!(
            posts[0].authorization.as_deref(),
            Some("Bearer secret-token")
        );
        let sent: Value = serde_json::from_str(&posts[0].body).unwrap();
        assert_eq!(sent["origin"], "dictionaryapi.dev");
        let words: Vec<_> = sent["words"]
            .as_array()
            .unwrap()
            .iter()
            .map(|w| w["word"].as_str().unwrap())
            .collect();
        assert_eq!(words, ["serendipity", "candid", "wandered", "benevolent"]);
        // Every body is one the Worker will accept.
        for word in sent["words"].as_array().unwrap() {
            envelope::parse_vocab(word).unwrap();
        }
    }

    #[test]
    fn lookups_send_the_ingest_user_agent_and_hit_the_dictionary_path() {
        let server = worker_and_dictionary(200, None);
        run(&server, "candid\n", true);
        let first = &server.requests()[0];
        assert_eq!(
            (first.method.as_str(), first.path.as_str()),
            ("GET", "/dict/candid")
        );
        assert_eq!(first.user_agent.as_deref(), Some("os-widget-ingest"));
    }

    #[test]
    fn dry_run_prints_the_bodies_and_never_posts() {
        let server = worker_and_dictionary(200, None);
        let (report, progress) = run(
            &server,
            "serendipity\ncandid\nresilient\nwandered\nbenevolent\n",
            false,
        );
        assert_eq!(report.code, 0);
        let bodies: Value = serde_json::from_str(report.stdout.as_deref().unwrap()).unwrap();
        assert_eq!(bodies.as_array().unwrap().len(), 4);
        assert_eq!(
            report.stderr.as_deref(),
            Some("dry run: would store 4, skipped 1")
        );
        assert!(progress.contains("skip resilient missing ipa"));
        assert!(server.posts().is_empty());
    }

    #[test]
    fn words_are_sent_in_batches_of_25() {
        let server = worker_and_dictionary(200, None);
        let text = distinct_words(60);
        let (report, _) = run(&server, &text, true);
        assert_eq!(report.stdout.as_deref(), Some("stored 60, skipped 0"));
        let sizes: Vec<usize> = server
            .posts()
            .iter()
            .map(|p| {
                serde_json::from_str::<Value>(&p.body).unwrap()["words"]
                    .as_array()
                    .unwrap()
                    .len()
            })
            .collect();
        assert_eq!(sizes, [25, 25, 10]);
    }

    #[test]
    fn a_word_the_dictionary_does_not_know_is_skipped_as_not_found() {
        let server = worker_and_dictionary(200, None);
        let (report, progress) = run(&server, "unknownword\ncandid\n", true);
        assert_eq!(report.stdout.as_deref(), Some("stored 1, skipped 1"));
        assert!(
            progress.starts_with("skip unknownword not found\n"),
            "{progress}"
        );
    }

    #[test]
    fn rejected_lines_are_reported_as_skipped_without_a_lookup() {
        let server = worker_and_dictionary(200, None);
        let (report, progress) = run(&server, "ice cream\ncandid\n", true);
        assert_eq!(report.stdout.as_deref(), Some("stored 1, skipped 1"));
        assert!(
            progress.contains("skip ice cream invalid characters"),
            "{progress}"
        );
        assert!(server.requests().iter().all(|r| !r.path.contains("ice")));
    }

    #[test]
    fn an_empty_list_stores_nothing_and_succeeds() {
        let server = worker_and_dictionary(200, None);
        let (report, _) = run(&server, "# nothing\n\n", true);
        assert_eq!(report.code, 0);
        assert_eq!(report.stdout.as_deref(), Some("stored 0, skipped 0"));
        assert!(server.requests().is_empty());
    }

    #[test]
    fn server_400_stops_with_exit_2_and_the_field() {
        let server = worker_and_dictionary(
            400,
            Some(
                r#"{"error":"invalid vocab","field":"words[0].ipa","message":"must not be empty"}"#,
            ),
        );
        let (report, _) = run(&server, "candid\n", true);
        assert_eq!(report.code, 2);
        assert_eq!(
            report.stderr.as_deref(),
            Some("invalid vocab: words[0].ipa: must not be empty")
        );
    }

    #[test]
    fn server_401_stops_with_exit_1() {
        let server = worker_and_dictionary(401, Some(r#"{"error":"unauthorized"}"#));
        let (report, _) = run(&server, "candid\n", true);
        assert_eq!(report.code, 1);
        assert!(report.stderr.unwrap().starts_with("HTTP 401"));
    }

    #[test]
    fn a_failed_batch_keeps_what_earlier_batches_stored() {
        let count = Arc::new(Mutex::new(0));
        let c = count.clone();
        let server = FakeServer::start(move |r| {
            if r.method == "POST" {
                let mut n = c.lock().unwrap();
                *n += 1;
                return if *n == 1 {
                    (200, r#"{"stored":25}"#.into())
                } else {
                    (500, "boom".into())
                };
            }
            (200, json!([{ "phonetic": "/x/", "meanings": [{ "partOfSpeech": "noun", "definitions": [{ "definition": "d" }] }] }]).to_string())
        });
        let (report, _) = run(&server, &distinct_words(30), true);

        assert_eq!(report.code, 1);
        assert_eq!(report.stdout.as_deref(), Some("stored 25, skipped 0"));
        assert!(report.stderr.unwrap().starts_with("HTTP 500"));
    }
}
