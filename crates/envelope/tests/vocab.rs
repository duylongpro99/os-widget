//! Behaviour of the standalone `vocab` body validation shared by the Worker and the ingest command.

use envelope::{EnvelopeError, VocabBody, check_vocab, parse_vocab};
use serde_json::{Value, json};

fn body() -> Value {
    json!({
        "word": "serendipity",
        "ipa": "/ˌser.ənˈdɪp.ə.ti/",
        "pos": "noun",
        "audio_url": "https://example.com/serendipity.mp3",
        "meanings": [
            { "definition": "the luck of finding good things by chance", "examples": ["a happy serendipity"] },
            { "definition": "an instance of such luck" }
        ],
        "context": "Their meeting was pure serendipity.",
        "synonyms": ["chance", "fluke"],
        "antonyms": ["misfortune"]
    })
}

fn err(v: &Value) -> EnvelopeError {
    parse_vocab(v).expect_err("body should be rejected")
}

#[test]
fn complete_body_is_accepted() {
    let b = parse_vocab(&body()).unwrap();
    assert_eq!(b.word, "serendipity");
    assert_eq!(b.pos, "noun");
    assert_eq!(b.meanings.len(), 2);
    assert_eq!(b.meanings[1].examples, Vec::<String>::new());
    assert_eq!(b.synonyms, ["chance", "fluke"]);
}

#[test]
fn optional_fields_may_be_omitted() {
    let v = json!({
        "word": "lucid", "ipa": "/ˈluː.sɪd/", "pos": "adjective",
        "meanings": [{ "definition": "clear" }]
    });
    let b = parse_vocab(&v).unwrap();
    assert_eq!(b.audio_url, None);
    assert_eq!(b.context, None);
}

#[test]
fn missing_ipa_is_rejected_at_the_root() {
    let mut v = body();
    v.as_object_mut().unwrap().remove("ipa");
    let e = err(&v);
    assert_eq!(e.field, "");
    assert!(e.message.contains("ipa"), "{e}");
}

#[test]
fn empty_meanings_are_rejected() {
    let mut v = body();
    v["meanings"] = json!([]);
    assert_eq!(err(&v).field, "meanings");
}

#[test]
fn blank_definition_names_its_meaning() {
    let mut v = body();
    v["meanings"][1]["definition"] = json!("");
    assert_eq!(err(&v).field, "meanings[1].definition");
}

#[test]
fn missing_definition_is_a_decoding_error_on_the_meaning() {
    let mut v = body();
    v["meanings"][1]
        .as_object_mut()
        .unwrap()
        .remove("definition");
    assert_eq!(err(&v).field, "meanings[1]");
}

#[test]
fn plain_http_audio_is_rejected() {
    let mut v = body();
    v["audio_url"] = json!("http://example.com/a.mp3");
    let e = err(&v);
    assert_eq!(e.field, "audio_url");
    assert_eq!(e.message, "must start with https://");
}

#[test]
fn blank_word_is_rejected() {
    let mut v = body();
    v["word"] = json!("  ");
    assert_eq!(err(&v).field, "word");
}

#[test]
fn check_vocab_prefixes_the_field() {
    let mut b: VocabBody = serde_json::from_value(body()).unwrap();
    b.meanings[0].definition = String::new();
    let e = check_vocab(&b, "body.").unwrap_err();
    assert_eq!(e.field, "body.meanings[0].definition");
}

#[test]
fn whitespace_ipa_is_rejected() {
    let mut v = body();
    v["ipa"] = json!(" \t");
    let e = err(&v);
    assert_eq!(e.field, "ipa");
    assert_eq!(e.message, "must not be empty");
}

#[test]
fn empty_pos_is_rejected() {
    let mut v = body();
    v["pos"] = json!("");
    assert_eq!(err(&v).field, "pos");
}

#[test]
fn multi_line_word_is_rejected() {
    let mut v = body();
    v["word"] = json!("seren\ndipity");
    let e = err(&v);
    assert_eq!(e.field, "word");
    assert_eq!(e.message, "must be a single line");
}

#[test]
fn envelope_with_empty_ipa_names_the_body_field() {
    let v = json!({
        "v": 1, "kind": "vocab", "source": "vocab-cron", "title": "serendipity", "summary": "(n.)",
        "body": { "word": "serendipity", "ipa": "", "pos": "noun", "meanings": [{ "definition": "luck" }] }
    });
    let e = envelope::parse(&serde_json::to_vec(&v).unwrap()).unwrap_err();
    assert_eq!(e.field, "body.ipa");
}
