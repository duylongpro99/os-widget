//! Body of a `vocab` envelope: one word with its meanings.

use serde::{Deserialize, Serialize};

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
