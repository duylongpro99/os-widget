//! Envelope types shared by the Worker and publishers.
//!
//! [`parse`] is the validation: it decodes a publish request, names the offending
//! field when decoding fails, and applies the rules the types cannot express.
//! The wire format keeps `kind` and `body` as two sibling top-level fields, so `Body`
//! is adjacently tagged and flattened into the envelope.

mod generic;
mod parse;
mod vocab;

pub use generic::{Block, Field, GenericBody};
pub use parse::{EnvelopeError, parse};
pub use vocab::{Meaning, VocabBody};

use serde::{Deserialize, Serialize};

/// A publish request as sent to `POST /items`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Envelope {
    /// Envelope format version.
    pub v: u32,
    /// `kind` and `body`, decided together by the variant.
    #[serde(flatten)]
    pub content: Body,
    /// Name of the sender, shown on the card.
    pub source: String,
    #[serde(default)]
    pub priority: Priority,
    /// Plain text, one line.
    pub title: String,
    /// Plain text, short.
    pub summary: String,
    #[serde(default)]
    pub url: Option<String>,
    /// Lifetime in seconds; the server converts it into `expires_at`.
    #[serde(default)]
    pub ttl: Option<u64>,
    #[serde(default)]
    pub dedupe_key: Option<String>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Priority {
    Low,
    #[default]
    Normal,
    High,
}

/// Content of the envelope, tagged by `kind` with its data in `body`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "body", rename_all = "snake_case")]
pub enum Body {
    /// `body` may be omitted; the card then shows only `title` and `summary`.
    Notification(#[serde(default)] Option<NotificationBody>),
    /// One word to learn; `body` is required.
    Vocab(VocabBody),
    /// Free-form content built from blocks; `body` is required.
    Generic(GenericBody),
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationBody {
    /// Short markdown.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

impl Body {
    /// The `kind` string as it appears on the wire.
    pub fn kind(&self) -> &'static str {
        match self {
            Body::Notification(_) => "notification",
            Body::Vocab(_) => "vocab",
            Body::Generic(_) => "generic",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{from_str, json, to_value};

    const VALID: &str = r#"{
        "v": 1,
        "kind": "notification",
        "source": "m0",
        "priority": "high",
        "title": "hello",
        "summary": "smoke",
        "url": null,
        "ttl": 86400,
        "dedupe_key": null,
        "body": { "text": "hi" }
    }"#;

    #[test]
    fn valid_notification_deserializes() {
        let e: Envelope = from_str(VALID).unwrap();
        assert_eq!(e.v, 1);
        assert_eq!(e.content.kind(), "notification");
        assert_eq!(
            e.content,
            Body::Notification(Some(NotificationBody {
                text: Some("hi".into())
            }))
        );
        assert_eq!(e.priority, Priority::High);
        assert_eq!(e.ttl, Some(86400));
    }

    #[test]
    fn optional_fields_default() {
        let e: Envelope = from_str(
            r#"{"v":1,"kind":"notification","source":"m0","title":"t","summary":"s","body":{"text":"hi"}}"#,
        )
        .unwrap();
        assert_eq!(e.priority, Priority::Normal);
        assert_eq!(e.url, None);
        assert_eq!(e.ttl, None);
        assert_eq!(e.dedupe_key, None);
    }

    #[test]
    fn notification_body_may_be_omitted() {
        let e: Envelope =
            from_str(r#"{"v":1,"kind":"notification","source":"m0","title":"t","summary":"s"}"#)
                .unwrap();
        assert_eq!(e.content, Body::Notification(None));
    }

    #[test]
    fn missing_title_fails() {
        let err = from_str::<Envelope>(
            r#"{"v":1,"kind":"notification","source":"m0","summary":"s","body":{}}"#,
        )
        .unwrap_err();
        assert!(err.to_string().contains("title"), "{err}");
    }

    #[test]
    fn unknown_kind_fails() {
        assert!(
            from_str::<Envelope>(
                r#"{"v":1,"kind":"weather","source":"m0","title":"t","summary":"s","body":{}}"#,
            )
            .is_err()
        );
    }

    /// The publish request example from the architecture doc, with `kind` set to
    /// the one supported variant, must survive a round trip unchanged.
    #[test]
    fn architecture_example_round_trips() {
        let input = json!({
            "v": 1,
            "kind": "notification",
            "source": "vocab-cron",
            "priority": "normal",
            "title": "serendipity",
            "summary": "(n.) sự tình cờ may mắn",
            "url": null,
            "ttl": 86400,
            "dedupe_key": "vocab-2026-11-22T10",
            "body": { }
        });
        let e: Envelope = serde_json::from_value(input.clone()).unwrap();
        assert_eq!(to_value(&e).unwrap(), input);

        let with_text = json!({
            "v": 1, "kind": "notification", "source": "m0", "priority": "high",
            "title": "t", "summary": "s", "url": "https://example.com", "ttl": null,
            "dedupe_key": null, "body": { "text": "**hi**" }
        });
        let e: Envelope = serde_json::from_value(with_text.clone()).unwrap();
        assert_eq!(to_value(&e).unwrap(), with_text);
    }

    #[test]
    fn serializes_kind_and_body_as_siblings() {
        let e: Envelope = from_str(VALID).unwrap();
        let v = to_value(&e).unwrap();
        assert_eq!(v["kind"], json!("notification"));
        assert_eq!(v["body"], json!({ "text": "hi" }));
    }
}
