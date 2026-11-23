//! `GET /events`: the ordered event log, with created items embedded.

use std::num::IntErrorKind;

use serde::{Deserialize, Serialize};
use serde_json::Value;
use worker::{Env, Method, Request, Response, Result};

use crate::supabase;
use crate::{error, json_response};

/// Page size when `limit` is absent, and the largest page served.
const MAX_LIMIT: u32 = 100;

#[derive(Debug, Deserialize, Serialize)]
struct Event {
    seq: i64,
    #[serde(rename = "type")]
    kind: String,
    item_id: String,
    created_at: String,
    /// Set only on `item.created`; `null` when the item no longer exists.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    item: Option<Value>,
}

#[derive(Debug, PartialEq, Eq)]
struct Page {
    since: i64,
    limit: u32,
}

/// `GET /events?since=<seq>&limit=<n>`: events after `since`, oldest first.
pub async fn list(req: Request, env: &Env) -> Result<Response> {
    let url = req.url()?;
    let param = |name: &str| {
        url.query_pairs()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.into_owned())
    };
    let page = match parse_page(param("since").as_deref(), param("limit").as_deref()) {
        Ok(page) => page,
        Err(code) => return error(400, code),
    };

    let mut events: Vec<Event> = supabase::rows(
        env,
        Method::Get,
        &format!(
            "events?seq=gt.{}&order=seq.asc&limit={}",
            page.since, page.limit
        ),
        None,
        None,
    )
    .await?;

    let ids: Vec<&str> = events
        .iter()
        .filter(|e| e.kind == "item.created")
        .map(|e| e.item_id.as_str())
        .collect();
    if !ids.is_empty() {
        // Item ids are server-generated UUIDs; quoting keeps the filter safe regardless.
        let list = ids
            .iter()
            .map(|id| format!("\"{}\"", id.replace('"', "")))
            .collect::<Vec<_>>()
            .join(",");
        let items: Vec<Value> = supabase::rows(
            env,
            Method::Get,
            &format!("items?id=in.({})", supabase::encode(&list)),
            None,
            None,
        )
        .await?;
        embed_items(&mut events, &items);
    }

    json_response(200, &events)
}

/// Parses `since` (required, integer ≥ 0) and `limit` (default and cap 100, ≥ 1).
fn parse_page(since: Option<&str>, limit: Option<&str>) -> std::result::Result<Page, &'static str> {
    let since = since
        .and_then(|s| s.parse::<i64>().ok())
        .filter(|s| *s >= 0)
        .ok_or("invalid since")?;
    let limit = match limit {
        None => MAX_LIMIT,
        Some(s) => match s.parse::<i64>() {
            Ok(n) if n >= 1 => u32::try_from(n).map_or(MAX_LIMIT, |n| n.min(MAX_LIMIT)),
            Err(e) if *e.kind() == IntErrorKind::PosOverflow => MAX_LIMIT,
            _ => return Err("invalid limit"),
        },
    };
    Ok(Page { since, limit })
}

/// Attaches each `item.created` event's item, or `null` when it was purged.
fn embed_items(events: &mut [Event], items: &[Value]) {
    for event in events.iter_mut().filter(|e| e.kind == "item.created") {
        let item = items
            .iter()
            .find(|i| i.get("id").and_then(Value::as_str) == Some(event.item_id.as_str()));
        event.item = Some(item.cloned().unwrap_or(Value::Null));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn page(since: Option<&str>, limit: Option<&str>) -> std::result::Result<Page, &'static str> {
        parse_page(since, limit)
    }

    #[test]
    fn limit_absent_defaults_to_100() {
        assert_eq!(
            page(Some("0"), None),
            Ok(Page {
                since: 0,
                limit: 100
            })
        );
    }

    #[test]
    fn limit_within_range_is_kept() {
        assert_eq!(page(Some("7"), Some("50")).unwrap().limit, 50);
        assert_eq!(page(Some("7"), Some("1")).unwrap().limit, 1);
        assert_eq!(page(Some("7"), Some("100")).unwrap().limit, 100);
    }

    #[test]
    fn limit_above_100_is_capped() {
        assert_eq!(page(Some("0"), Some("500")).unwrap().limit, 100);
        assert_eq!(page(Some("0"), Some("4294967296")).unwrap().limit, 100);
        assert_eq!(
            page(Some("0"), Some("99999999999999999999999"))
                .unwrap()
                .limit,
            100
        );
    }

    #[test]
    fn limit_below_1_is_rejected() {
        assert_eq!(page(Some("0"), Some("0")), Err("invalid limit"));
        assert_eq!(page(Some("0"), Some("-1")), Err("invalid limit"));
        assert_eq!(
            page(Some("0"), Some("-99999999999999999999999")),
            Err("invalid limit")
        );
    }

    #[test]
    fn limit_not_a_number_is_rejected() {
        assert_eq!(page(Some("0"), Some("abc")), Err("invalid limit"));
        assert_eq!(page(Some("0"), Some("")), Err("invalid limit"));
        assert_eq!(page(Some("0"), Some("1.5")), Err("invalid limit"));
        assert_eq!(page(Some("0"), Some(" 5")), Err("invalid limit"));
    }

    #[test]
    fn since_is_parsed() {
        assert_eq!(page(Some("42"), None).unwrap().since, 42);
    }

    #[test]
    fn since_missing_is_rejected() {
        assert_eq!(page(None, None), Err("invalid since"));
        assert_eq!(page(None, Some("10")), Err("invalid since"));
    }

    #[test]
    fn since_negative_or_not_a_number_is_rejected() {
        assert_eq!(page(Some("-1"), None), Err("invalid since"));
        assert_eq!(page(Some("abc"), None), Err("invalid since"));
        assert_eq!(page(Some(""), None), Err("invalid since"));
    }

    fn event(seq: i64, kind: &str, item_id: &str) -> Event {
        Event {
            seq,
            kind: kind.into(),
            item_id: item_id.into(),
            created_at: "2026-11-23T00:00:00+00:00".into(),
            item: None,
        }
    }

    #[test]
    fn created_events_get_their_item_or_null() {
        let mut events = vec![
            event(1, "item.created", "a"),
            event(2, "item.read", "a"),
            event(3, "item.created", "gone"),
        ];
        let items = vec![json!({ "id": "a", "title": "t" })];
        embed_items(&mut events, &items);

        let out = serde_json::to_value(&events).unwrap();
        assert_eq!(out[0]["item"], json!({ "id": "a", "title": "t" }));
        assert_eq!(out[0]["type"], json!("item.created"));
        assert!(out[1].get("item").is_none(), "{out}");
        assert_eq!(out[2]["item"], Value::Null);
        assert!(out[2].as_object().unwrap().contains_key("item"));
    }
}
