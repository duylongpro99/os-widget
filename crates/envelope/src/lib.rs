//! Envelope types shared by the Worker and publishers.
//!
//! Deserializing into [`Envelope`] is the validation: a payload that parses is valid.
//! The wire format keeps `kind` and `body` as two sibling top-level fields, so `Body`
//! is adjacently tagged and flattened into the envelope.

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
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotificationBody {
    /// Short markdown.
    #[serde(default)]
    pub text: Option<String>,
}

impl Body {
    /// The `kind` string as it appears on the wire.
    pub fn kind(&self) -> &'static str {
        match self {
            Body::Notification(_) => "notification",
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

    #[test]
    fn serializes_kind_and_body_as_siblings() {
        let e: Envelope = from_str(VALID).unwrap();
        let v = to_value(&e).unwrap();
        assert_eq!(v["kind"], json!("notification"));
        assert_eq!(v["body"], json!({ "text": "hi" }));
    }
}
