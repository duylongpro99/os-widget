//! Vocabulary: `POST /vocab/words` stores a batch of words, and the scheduled
//! handler asks the database to send the next one.
//!
//! All word-picking logic lives in the `vocab_tick` SQL function; this module only
//! validates batches, calls the two functions and logs one short line per tick.

use serde::Deserialize;
use serde_json::{Value, json};
use worker::{Env, Request, Response, Result};

use crate::json_response;
use crate::supabase;

/// Most words one request may carry.
const MAX_WORDS: usize = 50;
/// Longest `origin`, in characters.
const MAX_ORIGIN_CHARS: usize = 200;

/// A batch that passed validation, in the shape `vocab_upsert` takes.
#[derive(Debug, PartialEq)]
struct Batch {
    origin: String,
    words: Vec<Value>,
}

/// Why a request body was refused: the field to name and what is wrong with it.
#[derive(Debug, PartialEq, Eq)]
struct Invalid {
    field: String,
    message: String,
}

impl Invalid {
    fn new(field: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            field: field.into(),
            message: message.into(),
        }
    }

    fn body(&self) -> Value {
        json!({ "error": "invalid vocab", "field": self.field, "message": self.message })
    }
}

/// Checks `{"origin": ..., "words": [...]}`. Every word must pass
/// `envelope::parse_vocab`; the stored words are the decoded and re-serialized
/// bodies, never the raw request.
fn parse_batch(bytes: &[u8]) -> std::result::Result<Batch, Invalid> {
    let value: Value = serde_json::from_slice(bytes)
        .map_err(|_| Invalid::new("", "body must be a JSON object"))?;
    let Some(object) = value.as_object() else {
        return Err(Invalid::new("", "body must be a JSON object"));
    };

    let origin = match object.get("origin") {
        Some(Value::String(s)) if !s.trim().is_empty() => s,
        _ => return Err(Invalid::new("origin", "must be a non-empty string")),
    };
    if origin.chars().count() > MAX_ORIGIN_CHARS {
        return Err(Invalid::new(
            "origin",
            format!("must be at most {MAX_ORIGIN_CHARS} characters"),
        ));
    }

    let Some(Value::Array(items)) = object.get("words") else {
        return Err(Invalid::new("words", "must be an array"));
    };
    if items.is_empty() || items.len() > MAX_WORDS {
        return Err(Invalid::new(
            "words",
            format!("must have between 1 and {MAX_WORDS} words"),
        ));
    }

    let mut words = Vec::with_capacity(items.len());
    for (i, item) in items.iter().enumerate() {
        let body =
            envelope::parse_vocab(item).map_err(|e| Invalid::new(word_field(i, &e), e.message))?;
        words.push(
            serde_json::to_value(body)
                .map_err(|e| Invalid::new(format!("words[{i}]"), e.to_string()))?,
        );
    }
    Ok(Batch {
        origin: origin.clone(),
        words,
    })
}

/// Names the field of word `index` that `error` is about. The envelope reports a
/// missing field in its message and stops the path at the parent, so the missing
/// name is appended to give `words[3].ipa` rather than `words[3]`.
fn word_field(index: usize, error: &envelope::EnvelopeError) -> String {
    let mut field = format!("words[{index}]");
    if !error.field.is_empty() {
        field.push('.');
        field.push_str(&error.field);
    }
    let missing = error
        .message
        .strip_prefix("missing field `")
        .and_then(|rest| rest.strip_suffix('`'));
    if let Some(name) = missing {
        field.push('.');
        field.push_str(name);
    }
    field
}

/// The arguments of the `vocab_upsert` function.
fn upsert_args(batch: &Batch) -> Value {
    json!({ "p_origin": batch.origin, "p_words": batch.words })
}

/// `POST /vocab/words`: 200 `{"stored": n}`, or 400 naming the first bad field.
/// A batch with any bad word stores nothing.
pub async fn post(mut req: Request, env: &Env) -> Result<Response> {
    let bytes = req.bytes().await?;
    let batch = match parse_batch(&bytes) {
        Ok(batch) => batch,
        Err(invalid) => return json_response(400, &invalid.body()),
    };
    let stored: u64 = supabase::rpc(env, "vocab_upsert", upsert_args(&batch).to_string()).await?;
    json_response(200, &json!({ "stored": stored }))
}

#[derive(Debug, Deserialize)]
struct TickResult {
    status: String,
    #[serde(default)]
    word: Option<String>,
}

/// The one log line of a tick, from the database's answer. It carries the status
/// and never the word's content.
fn tick_log_line(result: &Value) -> String {
    match serde_json::from_value::<TickResult>(result.clone()) {
        Ok(tick) => {
            let _ = &tick.word;
            format!("vocab.tick status={}", sanitize(&tick.status))
        }
        Err(_) => "vocab.tick status=unknown".to_owned(),
    }
}

/// Keeps a status to plain identifier characters so a log line stays one token.
fn sanitize(status: &str) -> String {
    status
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' {
                c
            } else {
                '?'
            }
        })
        .take(32)
        .collect()
}

/// One cron run: a single call to `vocab_tick`. Failures are logged, never raised.
pub async fn tick(env: &Env) {
    match supabase::rpc::<Value>(env, "vocab_tick", "{}".to_owned()).await {
        Ok(result) => worker::console_log!("{}", tick_log_line(&result)),
        Err(e) => worker::console_error!("vocab.tick failed: {e}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn word(name: &str) -> Value {
        json!({
            "word": name,
            "ipa": "/x/",
            "pos": "noun",
            "meanings": [{ "definition": "a thing", "examples": ["an example"] }],
        })
    }

    fn batch(origin: Value, words: Value) -> Vec<u8> {
        serde_json::to_vec(&json!({ "origin": origin, "words": words })).unwrap()
    }

    #[test]
    fn valid_batch_is_kept_in_order() {
        let bytes = batch(json!("dictionaryapi.dev"), json!([word("a"), word("b")]));
        let parsed = parse_batch(&bytes).unwrap();
        assert_eq!(parsed.origin, "dictionaryapi.dev");
        assert_eq!(parsed.words.len(), 2);
        assert_eq!(parsed.words[1]["word"], "b");
        let args = upsert_args(&parsed);
        assert_eq!(args["p_origin"], "dictionaryapi.dev");
        assert_eq!(args["p_words"][0]["word"], "a");
    }

    #[test]
    fn stored_words_are_the_decoded_bodies() {
        let mut raw = word("a");
        raw["unknown"] = json!(1);
        let parsed = parse_batch(&batch(json!("o"), json!([raw]))).unwrap();
        assert!(parsed.words[0].get("unknown").is_none());
        assert_eq!(parsed.words[0]["synonyms"], json!([]));
    }

    #[test]
    fn origin_must_be_a_non_empty_string_of_at_most_200_chars() {
        for origin in [json!(""), json!("  "), json!(null), json!(3)] {
            let err = parse_batch(&batch(origin, json!([word("a")]))).unwrap_err();
            assert_eq!(err.field, "origin");
        }
        let missing = serde_json::to_vec(&json!({ "words": [word("a")] })).unwrap();
        assert_eq!(parse_batch(&missing).unwrap_err().field, "origin");
        assert!(parse_batch(&batch(json!("é".repeat(200)), json!([word("a")]))).is_ok());
        let err = parse_batch(&batch(json!("é".repeat(201)), json!([word("a")]))).unwrap_err();
        assert_eq!(err.field, "origin");
    }

    #[test]
    fn words_must_hold_one_to_fifty_items() {
        let empty = parse_batch(&batch(json!("o"), json!([]))).unwrap_err();
        assert_eq!(empty.field, "words");
        let many: Vec<Value> = (0..51).map(|i| word(&format!("w{i}"))).collect();
        let err = parse_batch(&batch(json!("o"), json!(many))).unwrap_err();
        assert_eq!(err.field, "words");
        let fifty: Vec<Value> = (0..50).map(|i| word(&format!("w{i}"))).collect();
        assert!(parse_batch(&batch(json!("o"), json!(fifty))).is_ok());
        let not_array = parse_batch(&batch(json!("o"), json!("x"))).unwrap_err();
        assert_eq!(not_array.field, "words");
    }

    #[test]
    fn a_bad_word_names_its_index_and_field() {
        let mut bad = word("d");
        bad.as_object_mut().unwrap().remove("ipa");
        let words = json!([word("a"), word("b"), word("c"), bad]);
        let err = parse_batch(&batch(json!("o"), words)).unwrap_err();
        assert_eq!(err.field, "words[3].ipa");
        let body = err.body();
        assert_eq!(body["error"], "invalid vocab");
        assert_eq!(body["field"], "words[3].ipa");
        assert!(body["message"].as_str().is_some_and(|m| !m.is_empty()));
    }

    #[test]
    fn nested_and_blank_fields_are_named_relative_to_the_word() {
        let mut no_definition = word("c");
        no_definition["meanings"] = json!([{ "examples": [] }]);
        let err = parse_batch(&batch(json!("o"), json!([word("a"), no_definition]))).unwrap_err();
        assert_eq!(err.field, "words[1].meanings[0].definition");

        let mut blank = word("b");
        blank["ipa"] = json!("  ");
        let err = parse_batch(&batch(json!("o"), json!([blank]))).unwrap_err();
        assert_eq!(err.field, "words[0].ipa");
    }

    #[test]
    fn a_word_that_is_not_an_object_names_its_index() {
        let err = parse_batch(&batch(json!("o"), json!(["text"]))).unwrap_err();
        assert!(err.field.starts_with("words[0]"), "{err:?}");
    }

    #[test]
    fn a_body_that_is_not_a_json_object_is_refused() {
        for bytes in [&b"not json"[..], b"[]", b"3", b""] {
            let err = parse_batch(bytes).unwrap_err();
            assert_eq!(err.field, "");
        }
    }

    #[test]
    fn tick_line_has_the_status_and_never_the_word() {
        let sent =
            json!({ "status": "sent", "word": "serendipity", "item_id": "x", "warnings": [] });
        assert_eq!(tick_log_line(&sent), "vocab.tick status=sent");
        for status in ["not_due", "empty", "exhausted", "disabled", "duplicate"] {
            let line = tick_log_line(&json!({ "status": status, "warnings": [] }));
            assert_eq!(line, format!("vocab.tick status={status}"));
        }
    }

    #[test]
    fn tick_line_survives_an_unexpected_answer() {
        assert_eq!(tick_log_line(&json!(null)), "vocab.tick status=unknown");
        assert_eq!(
            tick_log_line(&json!({ "x": 1 })),
            "vocab.tick status=unknown"
        );
        assert_eq!(
            tick_log_line(&json!({ "status": "a b\nc" })),
            "vocab.tick status=a?b?c"
        );
    }
}
