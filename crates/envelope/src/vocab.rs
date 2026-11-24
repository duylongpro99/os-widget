//! Body of a `vocab` envelope: one word with its meanings.

use serde::{Deserialize, Serialize};

use crate::parse::{EnvelopeError, https_url, not_blank, path_error};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VocabBody {
    pub word: String,
    pub ipa: String,
    /// Part of speech, for example `noun`.
    pub pos: String,
    /// Pronunciation audio; must be HTTPS.
    #[serde(default)]
    pub audio_url: Option<String>,
    /// At least one meaning.
    pub meanings: Vec<Meaning>,
    #[serde(default)]
    pub context: Option<String>,
    #[serde(default)]
    pub synonyms: Vec<String>,
    #[serde(default)]
    pub antonyms: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Meaning {
    pub definition: String,
    #[serde(default)]
    pub examples: Vec<String>,
}

/// Decodes and validates a standalone `vocab` body, as sent to `POST /vocab/words`
/// or built by the ingest command. Fields are named relative to the body, such as
/// `ipa` or `meanings[1].definition`.
pub fn parse_vocab(value: &serde_json::Value) -> Result<VocabBody, EnvelopeError> {
    let body: VocabBody = serde_path_to_error::deserialize(value).map_err(|e| path_error("", e))?;
    check_vocab(&body, "")?;
    Ok(body)
}

/// Rules of a `vocab` body that the types cannot express. `prefix` is put before
/// every field name, so `envelope::parse` passes `body.`.
pub fn check_vocab(body: &VocabBody, prefix: &str) -> Result<(), EnvelopeError> {
    let field = |name: &str| format!("{prefix}{name}");
    not_blank(&field("word"), &body.word)?;
    // The word becomes the card title, which is one line.
    if body.word.contains(['\n', '\r']) {
        return Err(EnvelopeError::new(field("word"), "must be a single line"));
    }
    not_blank(&field("ipa"), &body.ipa)?;
    not_blank(&field("pos"), &body.pos)?;
    if let Some(url) = &body.audio_url {
        https_url(&field("audio_url"), url)?;
    }
    if body.meanings.is_empty() {
        return Err(EnvelopeError::new(
            field("meanings"),
            "must have at least one meaning",
        ));
    }
    for (i, m) in body.meanings.iter().enumerate() {
        not_blank(&field(&format!("meanings[{i}].definition")), &m.definition)?;
    }
    Ok(())
}
