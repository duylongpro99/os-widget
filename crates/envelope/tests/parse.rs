//! Behaviour of `envelope::parse`: accepted payloads and the field each rejection names.

use envelope::{Block, Body, EnvelopeError, parse};
use serde_json::{Value, json, to_value};

fn vocab_example() -> Value {
    json!({
        "v": 1,
        "kind": "vocab",
        "source": "vocab-cron",
        "priority": "normal",
        "title": "serendipity",
        "summary": "(n.) sự tình cờ may mắn",
        "url": null,
        "ttl": 86400,
        "dedupe_key": "vocab-2026-11-22T10",
        "body": {
            "word": "serendipity",
            "ipa": "/ˌser.ənˈdɪp.ə.ti/",
            "pos": "noun",
            "audio_url": null,
            "meanings": [
                { "definition": "the luck of finding good things by chance", "examples": ["a happy serendipity"] }
            ],
            "context": "Their meeting was pure serendipity.",
            "synonyms": ["chance", "fluke"],
            "antonyms": ["misfortune"]
        }
    })
}

fn notification() -> Value {
    json!({ "v": 1, "kind": "notification", "source": "m0", "title": "t", "summary": "s" })
}

fn generic_with(block: Value) -> Value {
    json!({
        "v": 1, "kind": "generic", "source": "agent", "title": "t", "summary": "s",
        "body": { "blocks": [block] }
    })
}

fn parse_value(v: &Value) -> Result<envelope::Envelope, EnvelopeError> {
    parse(&serde_json::to_vec(v).unwrap())
}

fn parse_err(v: &Value) -> EnvelopeError {
    parse_value(v).expect_err("payload should be rejected")
}

#[test]
fn vocab_example_parses_and_round_trips() {
    let input = vocab_example();
    let e = parse_value(&input).unwrap();
    let Body::Vocab(body) = &e.content else {
        panic!("expected vocab, got {:?}", e.content);
    };
    assert_eq!(body.word, "serendipity");
    assert_eq!(body.meanings[0].examples, ["a happy serendipity"]);
    assert_eq!(e.content.kind(), "vocab");
    assert_eq!(to_value(&e).unwrap(), input);
}

#[test]
fn generic_with_all_seven_blocks_parses_and_round_trips() {
    let input = json!({
        "v": 1, "kind": "generic", "source": "agent", "priority": "low",
        "title": "Deploy report", "summary": "3 services updated",
        "url": "https://example.com/run/1", "ttl": 3600, "dedupe_key": null,
        "body": { "blocks": [
            { "type": "heading", "text": "Deploy" },
            { "type": "text", "markdown": "**done**" },
            { "type": "fields", "items": [{ "label": "env", "value": "prod" }] },
            { "type": "list", "items": ["api", "web"], "ordered": true },
            { "type": "image", "url": "https://example.com/a.png", "alt": "graph" },
            { "type": "code", "text": "cargo test", "language": "sh" },
            { "type": "link", "label": "Logs", "url": "http://example.com/logs" }
        ]}
    });
    let e = parse_value(&input).unwrap();
    let Body::Generic(body) = &e.content else {
        panic!("expected generic, got {:?}", e.content);
    };
    assert_eq!(body.blocks.len(), 7);
    assert_eq!(e.content.kind(), "generic");
    assert_eq!(to_value(&e).unwrap(), input);
}

#[test]
fn missing_title_names_the_field_at_the_root() {
    let mut v = notification();
    v.as_object_mut().unwrap().remove("title");
    let err = parse_err(&v);
    assert_eq!(err.field, "");
    assert!(err.message.contains("title"), "{err}");
}

#[test]
fn unknown_kind_is_rejected_on_kind() {
    let mut v = notification();
    v["kind"] = json!("weather");
    let err = parse_err(&v);
    assert_eq!(err.field, "kind");
    assert_eq!(
        err.message,
        "unknown kind `weather`, expected one of notification, vocab, generic"
    );
}

#[test]
fn vocab_missing_definition_points_at_the_meaning() {
    let mut v = vocab_example();
    v["body"]["meanings"][0]
        .as_object_mut()
        .unwrap()
        .remove("definition");
    let err = parse_err(&v);
    assert_eq!(err.field, "body.meanings[0]");
    assert!(err.message.contains("definition"), "{err}");
}

#[test]
fn unknown_block_type_points_at_the_block() {
    let err = parse_err(&generic_with(
        json!({ "type": "video", "url": "https://x" }),
    ));
    assert!(err.field.starts_with("body.blocks[0]"), "{err}");
    assert!(err.message.contains("video"), "{err}");
}

#[test]
fn version_other_than_one_is_rejected() {
    let mut v = notification();
    v["v"] = json!(2);
    assert_eq!(parse_err(&v).field, "v");
}

#[test]
fn multi_line_title_is_rejected() {
    let mut v = notification();
    v["title"] = json!("first\nsecond");
    assert_eq!(parse_err(&v).field, "title");
}

#[test]
fn non_web_url_is_rejected() {
    let mut v = notification();
    v["url"] = json!("javascript:x");
    assert_eq!(parse_err(&v).field, "url");
}

#[test]
fn plain_http_image_is_rejected() {
    let err = parse_err(&generic_with(
        json!({ "type": "image", "url": "http://example.com/a.png" }),
    ));
    assert_eq!(err.field, "body.blocks[0].url");
}

#[test]
fn zero_ttl_is_rejected() {
    let mut v = notification();
    v["ttl"] = json!(0);
    assert_eq!(parse_err(&v).field, "ttl");
}

#[test]
fn vocab_without_meanings_is_rejected() {
    let mut v = vocab_example();
    v["body"]["meanings"] = json!([]);
    assert_eq!(parse_err(&v).field, "body.meanings");
}

#[test]
fn malformed_json_is_an_error_not_a_panic() {
    let err = parse(b"{").unwrap_err();
    assert_eq!(err.field, "");
    assert!(!err.message.contains(" at line "), "{err}");
}

#[test]
fn messages_carry_no_position() {
    let mut v = notification();
    v["ttl"] = json!("soon");
    let err = parse_err(&v);
    assert_eq!(err.field, "ttl");
    assert!(!err.message.contains(" at line "), "{err}");
}

#[test]
fn display_joins_field_and_message() {
    let err = EnvelopeError {
        field: "body.meanings[0]".into(),
        message: "missing field `definition`".into(),
    };
    assert_eq!(
        err.to_string(),
        "body.meanings[0]: missing field `definition`"
    );
    let root = EnvelopeError {
        field: String::new(),
        message: "missing field `title`".into(),
    };
    assert_eq!(root.to_string(), "missing field `title`");
}

#[test]
fn notification_body_is_optional() {
    let e = parse_value(&notification()).unwrap();
    assert_eq!(e.content, Body::Notification(None));
}

#[test]
fn vocab_requires_a_body() {
    let mut v = vocab_example();
    v.as_object_mut().unwrap().remove("body");
    let err = parse_err(&v);
    assert_eq!(err.field, "");
    assert!(err.message.contains("body"), "{err}");
}

#[test]
fn blank_summary_is_rejected() {
    let mut v = notification();
    v["summary"] = json!("   ");
    assert_eq!(parse_err(&v).field, "summary");
}

#[test]
fn empty_dedupe_key_is_rejected() {
    let mut v = notification();
    v["dedupe_key"] = json!("");
    assert_eq!(parse_err(&v).field, "dedupe_key");
}

#[test]
fn blank_dedupe_key_is_rejected() {
    let mut v = notification();
    v["dedupe_key"] = json!(" \t ");
    assert_eq!(parse_err(&v).field, "dedupe_key");
}

#[test]
fn plain_http_audio_is_rejected() {
    let mut v = vocab_example();
    v["body"]["audio_url"] = json!("http://example.com/a.mp3");
    assert_eq!(parse_err(&v).field, "body.audio_url");
}

#[test]
fn blank_vocab_word_and_definition_are_rejected() {
    let mut v = vocab_example();
    v["body"]["word"] = json!("");
    assert_eq!(parse_err(&v).field, "body.word");

    let mut v = vocab_example();
    v["body"]["meanings"][0]["definition"] = json!(" ");
    assert_eq!(parse_err(&v).field, "body.meanings[0].definition");
}

#[test]
fn non_web_link_block_is_rejected() {
    let err = parse_err(&generic_with(
        json!({ "type": "link", "label": "x", "url": "file:///etc/passwd" }),
    ));
    assert_eq!(err.field, "body.blocks[0].url");
}

#[test]
fn unknown_fields_are_accepted() {
    let mut v = vocab_example();
    v["future_field"] = json!(true);
    v["body"]["future_field"] = json!(true);
    assert!(parse_value(&v).is_ok());
}

#[test]
fn block_defaults_apply() {
    let e = parse_value(&generic_with(json!({ "type": "list", "items": ["a"] }))).unwrap();
    let Body::Generic(body) = e.content else {
        panic!("expected generic");
    };
    assert_eq!(
        body.blocks[0],
        Block::List {
            items: vec!["a".into()],
            ordered: false
        }
    );
}

#[test]
fn root_must_be_a_json_object() {
    for payload in [
        &br#"[1,"notification",null,"m0","normal","t","s",null,null,null]"#[..],
        b" []",
        br#""x""#,
    ] {
        let err = parse(payload).expect_err("non-object root should be rejected");
        assert_eq!(err.field, "");
        assert_eq!(err.message, "expected a JSON object");
    }
}
