//! Validating parser for publish requests, with errors that name the offending field.

use std::fmt;

use serde::Deserialize;
use serde::de::DeserializeOwned;
use serde_json::Value;
use serde_path_to_error::Segment;

use crate::{Block, Body, Envelope, Priority, check_vocab};

/// Why a publish request was rejected.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EnvelopeError {
    /// Path to the offending field, such as `title` or `body.meanings[0]`.
    /// Empty when the problem is at the root, including a missing top-level field,
    /// whose name is then given in `message`.
    pub field: String,
    pub message: String,
}

impl EnvelopeError {
    pub(crate) fn new(field: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            field: field.into(),
            message: message.into(),
        }
    }
}

impl fmt::Display for EnvelopeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if self.field.is_empty() {
            f.write_str(&self.message)
        } else {
            write!(f, "{}: {}", self.field, self.message)
        }
    }
}

impl std::error::Error for EnvelopeError {}

/// The common fields, with `body` kept raw until `kind` picks its type.
///
/// Flattening `Body` into `Envelope` hides the path of errors inside `body`, so
/// `parse` decodes in two steps instead of going through `Envelope`'s `Deserialize`.
#[derive(Deserialize)]
struct RawEnvelope {
    v: u32,
    kind: String,
    #[serde(default)]
    body: Option<Value>,
    source: String,
    #[serde(default)]
    priority: Priority,
    title: String,
    summary: String,
    #[serde(default)]
    url: Option<String>,
    #[serde(default)]
    ttl: Option<u64>,
    #[serde(default)]
    dedupe_key: Option<String>,
}

/// Parses and validates a publish request.
///
/// This is the single validation used by the Worker and by publishers: a request
/// is valid if and only if this returns `Ok`.
pub fn parse(bytes: &[u8]) -> Result<Envelope, EnvelopeError> {
    // Derived struct decoding also accepts a JSON array of positional values;
    // a publish request is always an object. Empty input is left to serde.
    let first = bytes
        .iter()
        .find(|b| !matches!(b, b' ' | b'\t' | b'\n' | b'\r'));
    if first.is_some_and(|b| *b != b'{') {
        return Err(EnvelopeError::new("", "expected a JSON object"));
    }

    let mut de = serde_json::Deserializer::from_slice(bytes);
    let raw: RawEnvelope =
        serde_path_to_error::deserialize(&mut de).map_err(|e| path_error("", e))?;
    de.end()
        .map_err(|e| EnvelopeError::new("", without_position(&e)))?;

    let content = match raw.kind.as_str() {
        "notification" => Body::Notification(decode_body(raw.body.unwrap_or(Value::Null))?),
        "vocab" => Body::Vocab(decode_body(required(raw.body)?)?),
        "generic" => Body::Generic(decode_body(required(raw.body)?)?),
        other => {
            return Err(EnvelopeError::new(
                "kind",
                format!("unknown kind `{other}`, expected one of notification, vocab, generic"),
            ));
        }
    };

    let envelope = Envelope {
        v: raw.v,
        content,
        source: raw.source,
        priority: raw.priority,
        title: raw.title,
        summary: raw.summary,
        url: raw.url,
        ttl: raw.ttl,
        dedupe_key: raw.dedupe_key,
    };
    check(&envelope)?;
    Ok(envelope)
}

fn required(body: Option<Value>) -> Result<Value, EnvelopeError> {
    body.ok_or_else(|| EnvelopeError::new("", "missing field `body`"))
}

fn decode_body<T: DeserializeOwned>(body: Value) -> Result<T, EnvelopeError> {
    serde_path_to_error::deserialize(body).map_err(|e| path_error("body", e))
}

/// Turns a serde error into an `EnvelopeError` whose field is `prefix` followed by
/// the path serde reached. The path stops at the first segment serde could not
/// name (malformed JSON inside an object), so it points at the closest known parent.
pub(crate) fn path_error(
    prefix: &str,
    e: serde_path_to_error::Error<serde_json::Error>,
) -> EnvelopeError {
    let mut field = prefix.to_owned();
    for segment in e.path() {
        match segment {
            Segment::Seq { index } => field.push_str(&format!("[{index}]")),
            Segment::Map { key } => push_key(&mut field, key),
            Segment::Enum { variant } => push_key(&mut field, variant),
            Segment::Unknown => break,
        }
    }
    EnvelopeError::new(field, without_position(e.inner()))
}

fn push_key(field: &mut String, key: &str) {
    if !field.is_empty() {
        field.push('.');
    }
    field.push_str(key);
}

/// The serde_json message without its " at line X column Y" suffix.
fn without_position(e: &serde_json::Error) -> String {
    let message = e.to_string();
    if e.line() == 0 {
        return message;
    }
    let suffix = format!(" at line {} column {}", e.line(), e.column());
    match message.strip_suffix(&suffix) {
        Some(stripped) => stripped.to_owned(),
        None => message,
    }
}

/// Rules the types alone cannot express.
fn check(e: &Envelope) -> Result<(), EnvelopeError> {
    if e.v != 1 {
        return Err(EnvelopeError::new(
            "v",
            format!("unsupported version {}, expected 1", e.v),
        ));
    }
    not_blank("source", &e.source)?;
    not_blank("title", &e.title)?;
    if e.title.contains(['\n', '\r']) {
        return Err(EnvelopeError::new("title", "must be a single line"));
    }
    not_blank("summary", &e.summary)?;
    if let Some(url) = &e.url {
        web_url("url", url)?;
    }
    if e.ttl == Some(0) {
        return Err(EnvelopeError::new("ttl", "must be at least 1"));
    }
    if let Some(key) = &e.dedupe_key {
        not_blank("dedupe_key", key)?;
    }

    match &e.content {
        Body::Notification(_) => {}
        Body::Vocab(b) => check_vocab(b, "body.")?,
        Body::Generic(b) => {
            for (i, block) in b.blocks.iter().enumerate() {
                match block {
                    Block::Link { url, .. } => web_url(&format!("body.blocks[{i}].url"), url)?,
                    Block::Image { url, .. } => https_url(&format!("body.blocks[{i}].url"), url)?,
                    _ => {}
                }
            }
        }
    }
    Ok(())
}

pub(crate) fn not_blank(field: &str, value: &str) -> Result<(), EnvelopeError> {
    if value.trim().is_empty() {
        return Err(EnvelopeError::new(field, "must not be empty"));
    }
    Ok(())
}

fn web_url(field: &str, url: &str) -> Result<(), EnvelopeError> {
    if url.starts_with("http://") || url.starts_with("https://") {
        return Ok(());
    }
    Err(EnvelopeError::new(
        field,
        "must start with http:// or https://",
    ))
}

pub(crate) fn https_url(field: &str, url: &str) -> Result<(), EnvelopeError> {
    if url.starts_with("https://") {
        return Ok(());
    }
    Err(EnvelopeError::new(field, "must start with https://"))
}
