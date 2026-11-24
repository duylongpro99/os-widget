//! `os-widget ingest`: fill the vocabulary from outside sources.
//!
//! `words` looks each word up in the Free Dictionary API, drops the ones the API
//! cannot complete, and sends the rest in batches to `POST /vocab/words`. Words
//! stored by an earlier batch stay stored when a later one fails; ingesting again
//! is safe because the server upserts. `book` picks the words and their context
//! sentences from a plain-text book, then goes through the same lookup and batches.

pub mod book;
pub mod dictionary;
mod stopwords;

use std::collections::HashMap;
use std::io::Write;
use std::time::Duration;

use envelope::VocabBody;
use serde_json::{Value, json};

use crate::{BookArgs, Report, WordsArgs, read_input, resolve_server, resolve_token, snippet};
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
/// unless `target` is `None` (a dry run). A word with an entry in `contexts` is
/// stored with that sentence as its context.
fn run_words<F, S>(
    list: &WordList,
    dictionary: &mut Dictionary<F, S>,
    contexts: &HashMap<String, String>,
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
            Ok(mut body) => {
                body.context = contexts.get(word).cloned();
                sink.pending.push((word.clone(), body));
            }
            Err(reason) => {
                let _ = writeln!(progress, "skip {word} {reason}");
                skipped += 1;
            }
        }
        if let Err(failed) = flush(&mut sink, BATCH_SIZE, progress) {
            return with_summary(failed, sink.stored, skipped);
        }
    }
    if let Err(failed) = flush(&mut sink, 1, progress) {
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
    /// Looked-up words with their bodies; reported `ok` once their batch is out.
    pending: Vec<(String, VocabBody)>,
    /// Every body of a dry run, kept for printing.
    dry_run_bodies: Vec<VocabBody>,
    stored: u64,
}

/// Sends the pending words once there are at least `min` of them (or, in a dry
/// run, sets them aside for printing) and reports each as `ok` only after that
/// succeeded, so a failed batch leaves no word reported as stored.
fn flush(sink: &mut Sink, min: usize, progress: &mut dyn Write) -> Result<(), Report> {
    if sink.pending.is_empty() || sink.pending.len() < min {
        return Ok(());
    }
    let (words, bodies): (Vec<String>, Vec<VocabBody>) =
        std::mem::take(&mut sink.pending).into_iter().unzip();
    match sink.target {
        Some(target) => sink.stored += post_batch(target, sink.origin, &bodies)?,
        None => sink.dry_run_bodies.extend(bodies),
    }
    for word in words {
        let _ = writeln!(progress, "ok {word}");
    }
    Ok(())
}

/// A failed run still says how much was stored before it stopped.
fn with_summary(mut failed: Report, stored: u64, skipped: usize) -> Report {
    failed.stdout = Some(format!("stored {stored}, skipped {skipped}"));
    failed
}

/// The origin to store with each word, or the report to exit with when the
/// server would refuse it.
fn check_origin(origin: &str) -> Result<&str, Report> {
    let origin = origin.trim();
    if origin.is_empty() || origin.chars().count() > MAX_ORIGIN_CHARS {
        return Err(Report::rejected(
            "vocab",
            format!("origin: must be 1 to {MAX_ORIGIN_CHARS} characters"),
        ));
    }
    Ok(origin)
}

/// Where to send batches: `None` for a dry run, which needs neither a server nor
/// a token.
fn resolve_target(server_flag: Option<String>, dry_run: bool) -> Result<Option<Target>, Report> {
    if dry_run {
        return Ok(None);
    }
    let server = resolve_server(server_flag, std::env::var(crate::SERVER_ENV).ok());
    let token = resolve_token(std::env::var(crate::TOKEN_ENV).ok());
    match (server, token) {
        (Ok(server), Ok(token)) => Ok(Some(Target {
            words_url: format!("{server}/vocab/words"),
            token,
        })),
        (Err(message), _) | (_, Err(message)) => Err(Report::failure(message)),
    }
}

/// Reads a UTF-8 text file, or stdin for `-`. Text that is not UTF-8 exits with
/// `encoding_exit`; a file that cannot be read exits 1.
fn read_text(path: &str, encoding_exit: u8) -> Result<String, Report> {
    let bytes =
        read_input(path).map_err(|e| Report::failure(format!("cannot read {path}: {e}")))?;
    String::from_utf8(bytes).map_err(|_| Report {
        stdout: None,
        stderr: Some(format!("{path} is not valid UTF-8 text")),
        code: encoding_exit,
    })
}

/// `os-widget ingest words`.
pub fn words(args: WordsArgs) -> Report {
    let origin = match check_origin(&args.origin) {
        Ok(origin) => origin,
        Err(report) => return report,
    };
    let target = match resolve_target(args.server.clone(), args.dry_run) {
        Ok(target) => target,
        Err(report) => return report,
    };
    let text = match read_text(&args.path, crate::EXIT_FAILURE) {
        Ok(text) => text,
        Err(report) => return report,
    };

    let list = parse_word_list(&text);
    let mut dictionary = dictionary::http(&args.dictionary_url);
    run_words(
        &list,
        &mut dictionary,
        &HashMap::new(),
        origin,
        target.as_ref(),
        &mut std::io::stderr(),
    )
}

/// `os-widget ingest book`.
pub fn book(args: BookArgs) -> Report {
    let origin = match check_origin(&args.origin) {
        Ok(origin) => origin,
        Err(report) => return report,
    };
    // `--dry-run` alone never reaches the network, so it needs no server or token.
    let sends = !args.dry_run;
    let target = match resolve_target(args.server.clone(), !sends) {
        Ok(target) => target,
        Err(report) => return report,
    };
    let text = match read_text(&args.path, crate::EXIT_INVALID) {
        Ok(text) => text,
        Err(report) => return report,
    };

    let found = book::candidates(&text, args.min_length, args.max);
    if args.dry_run && !args.lookup {
        let listed: Vec<Value> = found
            .iter()
            .map(|c| json!({ "word": c.word, "context": c.context }))
            .collect();
        return Report {
            stdout: Some(serde_json::to_string_pretty(&listed).unwrap_or_else(|_| "[]".into())),
            stderr: Some(format!("dry run: {} candidate words", found.len())),
            code: 0,
        };
    }
    let mut dictionary = dictionary::http(&args.dictionary_url);
    run_candidates(
        found,
        &mut dictionary,
        origin,
        target.as_ref(),
        &mut std::io::stderr(),
    )
}

/// Looks the chosen words up and stores them with their context sentences. A
/// word the dictionary cannot complete is skipped, so a sentence is never sent
/// without the rest of its entry.
fn run_candidates<F, S>(
    found: Vec<book::Candidate>,
    dictionary: &mut Dictionary<F, S>,
    origin: &str,
    target: Option<&Target>,
    progress: &mut dyn Write,
) -> Report
where
    F: FnMut(&str) -> Fetched,
    S: FnMut(Duration),
{
    let list = WordList {
        words: found.iter().map(|c| c.word.clone()).collect(),
        rejected: Vec::new(),
    };
    let contexts: HashMap<String, String> =
        found.into_iter().map(|c| (c.word, c.context)).collect();
    run_words(&list, dictionary, &contexts, origin, target, progress)
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
            &HashMap::new(),
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
            "skip resilient missing ipa\nok serendipity\nok candid\nok wandered\nok benevolent\n"
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

    #[test]
    fn a_word_is_reported_ok_only_after_its_batch_is_stored() {
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
        let (report, progress) = run(&server, &distinct_words(30), true);

        assert_eq!(report.code, 1);
        let ok: Vec<&str> = progress.lines().filter(|l| l.starts_with("ok ")).collect();
        assert_eq!(ok.len(), 25, "{progress}");
        // The last five words were in the batch the server refused.
        for refused in ["waz", "wba", "wbb", "wbc", "wbd"] {
            assert!(!progress.contains(&format!("ok {refused}")), "{progress}");
        }
        assert!(
            ok.contains(&"ok waa") && ok.contains(&"ok way"),
            "{progress}"
        );
    }

    // --- books ---

    const SAMPLE_BOOK: &str = include_str!("../../tests/fixtures/book/sample.txt");

    fn run_book(server: &FakeServer, text: &str, send: bool) -> (Report, String) {
        let found = book::candidates(text, 5, 50);
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
        let report = run_candidates(
            found,
            &mut dictionary,
            "A Small Sample",
            send.then_some(&target),
            &mut progress,
        );
        (report, String::from_utf8(progress).unwrap())
    }

    #[test]
    fn book_words_are_sent_with_the_sentence_taken_from_the_book() {
        let server = worker_and_dictionary(200, None);
        let (report, _) = run_book(&server, SAMPLE_BOOK, true);

        assert_eq!(report.code, 0, "{report:?}");
        // The dictionary has no IPA for `lanterns`, so that word is not stored.
        assert_eq!(report.stdout.as_deref(), Some("stored 6, skipped 1"));
        let posts = server.posts();
        assert_eq!(posts.len(), 1);
        let sent: Value = serde_json::from_str(&posts[0].body).unwrap();
        assert_eq!(sent["origin"], "A Small Sample");
        let words = sent["words"].as_array().unwrap();
        let contexts: Vec<(&str, &str)> = words
            .iter()
            .map(|w| (w["word"].as_str().unwrap(), w["context"].as_str().unwrap()))
            .collect();
        assert_eq!(contexts.len(), 6);
        assert!(contexts.contains(&(
            "gardens",
            "Gardens grew behind the fish market, and the gardens were full of wet green leaves."
        )));
        assert!(!contexts.iter().any(|(word, _)| *word == "lanterns"));
        for word in words {
            envelope::parse_vocab(word).unwrap();
        }
    }

    #[test]
    fn a_book_word_the_dictionary_cannot_complete_is_skipped_not_sent_alone() {
        let server = worker_and_dictionary(200, None);
        let text = "The unknownword rose slowly. The unknownword fell again. \
                    The gardens grew behind the market. The gardens were wet.";
        let (report, progress) = run_book(&server, text, true);

        assert_eq!(report.stdout.as_deref(), Some("stored 1, skipped 1"));
        assert!(
            progress.contains("skip unknownword not found"),
            "{progress}"
        );
        let sent: Value = serde_json::from_str(&server.posts()[0].body).unwrap();
        let words: Vec<&str> = sent["words"]
            .as_array()
            .unwrap()
            .iter()
            .map(|w| w["word"].as_str().unwrap())
            .collect();
        assert_eq!(words, ["gardens"]);
    }

    #[test]
    fn a_book_dry_run_with_lookup_prints_bodies_with_context_and_never_posts() {
        let server = worker_and_dictionary(200, None);
        let (report, _) = run_book(&server, SAMPLE_BOOK, false);

        assert_eq!(report.code, 0);
        let bodies: Value = serde_json::from_str(report.stdout.as_deref().unwrap()).unwrap();
        let bodies = bodies.as_array().unwrap();
        assert_eq!(bodies.len(), 6);
        assert!(
            bodies
                .iter()
                .all(|b| !b["context"].as_str().unwrap().is_empty())
        );
        assert_eq!(
            report.stderr.as_deref(),
            Some("dry run: would store 6, skipped 1")
        );
        assert!(server.posts().is_empty());
    }

    #[test]
    fn a_dry_run_without_lookup_lists_words_and_contexts_and_calls_nothing() {
        let path = format!(
            "{}/tests/fixtures/book/sample.txt",
            env!("CARGO_MANIFEST_DIR")
        );
        let report = book(BookArgs {
            path,
            origin: "A Small Sample".into(),
            max: 2,
            min_length: 5,
            // Nothing listens here: a request would fail the run.
            dictionary_url: "http://127.0.0.1:9/en".into(),
            server: None,
            dry_run: true,
            lookup: false,
        });

        assert_eq!(report.code, 0, "{report:?}");
        let listed: Value = serde_json::from_str(report.stdout.as_deref().unwrap()).unwrap();
        assert_eq!(listed.as_array().unwrap().len(), 2);
        assert_eq!(listed[0]["word"], "harbours");
        assert!(
            listed[1]["context"]
                .as_str()
                .unwrap()
                .starts_with("The lanterns swayed")
        );
        assert_eq!(report.stderr.as_deref(), Some("dry run: 2 candidate words"));
    }

    fn book_args(path: &str, origin: &str) -> BookArgs {
        BookArgs {
            path: path.into(),
            origin: origin.into(),
            max: 50,
            min_length: 5,
            dictionary_url: "http://127.0.0.1:9/en".into(),
            server: None,
            dry_run: true,
            lookup: false,
        }
    }

    #[test]
    fn a_book_that_is_not_utf8_exits_2_and_says_so() {
        let dir = std::env::temp_dir().join(format!("os-widget-book-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("latin1.txt");
        std::fs::write(&path, b"caf\xe9 caf\xe9 caf\xe9").unwrap();

        let report = book(book_args(path.to_str().unwrap(), "x"));
        let _ = std::fs::remove_dir_all(&dir);

        assert_eq!(report.code, 2);
        assert!(
            report.stderr.unwrap().contains("not valid UTF-8"),
            "names the problem"
        );
    }

    #[test]
    fn a_missing_book_exits_1_and_a_bad_origin_exits_2_before_reading() {
        let missing = book(book_args("/nonexistent/book.txt", "x"));
        assert_eq!(missing.code, 1);
        assert!(missing.stderr.unwrap().contains("cannot read"));

        let blank = book(book_args("/nonexistent/book.txt", "  "));
        assert_eq!(blank.code, 2);
        assert!(blank.stderr.unwrap().starts_with("invalid vocab: origin"));
    }
}
