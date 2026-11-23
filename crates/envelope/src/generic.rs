//! Body of a `generic` envelope: a list of typed blocks.
//!
//! The block set is kept small so other clients can map it onto Adaptive Cards.
//! The server rejects unknown block types; clients skip them.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GenericBody {
    pub blocks: Vec<Block>,
}

/// One block, tagged by its `type` field.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Block {
    Heading {
        text: String,
    },
    Text {
        markdown: String,
    },
    Fields {
        items: Vec<Field>,
    },
    List {
        items: Vec<String>,
        #[serde(default)]
        ordered: bool,
    },
    /// The image is loaded only over HTTPS.
    Image {
        url: String,
        #[serde(default)]
        alt: Option<String>,
    },
    Code {
        text: String,
        #[serde(default)]
        language: Option<String>,
    },
    Link {
        label: String,
        url: String,
    },
}

/// One label/value row of a `fields` block.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Field {
    pub label: String,
    pub value: String,
}
