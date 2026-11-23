//! `/items` endpoints: publish, snapshot, read state and deletion.

use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use worker::{Env, Method, Request, Response, Result};

use crate::supabase::{self, encode};
use crate::{error, json_response, no_content};

/// Lifetime applied when the envelope carries no `ttl`.
const DEFAULT_TTL_SECS: u64 = 7 * 24 * 60 * 60;

/// Largest timestamp a JS `Date` can represent, in milliseconds since the epoch.
const MAX_JS_DATE_MS: f64 = 8.64e15;

#[derive(Serialize)]
struct NewItem<'a> {
    id: String,
    kind: &'static str,
    source: &'a str,
    priority: envelope::Priority,
    title: &'a str,
    summary: &'a str,
    url: Option<&'a str>,
    body: Value,
    dedupe_key: Option<&'a str>,
    expires_at: String,
}

#[derive(Deserialize)]
struct IdRow {
    id: String,
}

#[derive(Deserialize)]
struct SeqRow {
    seq: i64,
}

#[derive(Deserialize)]
struct DeletedRow {
    deleted_at: Option<String>,
}

/// `POST /items`: validates the envelope and stores it.
///
/// 201 with the new id; with a `dedupe_key` already stored, 200 with the existing
/// id, even if that item was deleted since.
pub async fn post(mut req: Request, env: &Env) -> Result<Response> {
    let bytes = req.bytes().await?;
    let envelope = match envelope::parse(&bytes) {
        Ok(e) => e,
        Err(e) => return json_response(400, &invalid_envelope(&e.field, &e.message)),
    };
    let Some(expires_ms) = expires_ms(supabase::now_ms(), envelope.ttl) else {
        return json_response(400, &invalid_envelope("ttl", "ttl is too large"));
    };

    // Store the re-serialized body, never the raw request, so stored data always
    // has the shape of the parsed types.
    let body = serde_json::to_value(&envelope.content)?
        .get_mut("body")
        .map(Value::take)
        .unwrap_or(Value::Null);
    let item = NewItem {
        id: uuid::Uuid::new_v4().to_string(),
        kind: envelope.content.kind(),
        source: &envelope.source,
        priority: envelope.priority,
        title: &envelope.title,
        summary: &envelope.summary,
        url: envelope.url.as_deref(),
        body,
        dedupe_key: envelope.dedupe_key.as_deref(),
        expires_at: supabase::iso(expires_ms)?,
    };
    let payload = Some(serde_json::to_string(&item)?);

    let Some(key) = envelope.dedupe_key.as_deref() else {
        let rows: Vec<IdRow> = supabase::rows(
            env,
            Method::Post,
            "items?select=id",
            payload,
            Some("return=representation"),
        )
        .await?;
        return created(rows);
    };

    // The trigger only fires for inserted rows, so an ignored duplicate adds no event.
    let rows: Vec<IdRow> = supabase::rows(
        env,
        Method::Post,
        "items?on_conflict=dedupe_key&select=id",
        payload,
        Some("resolution=ignore-duplicates,return=representation"),
    )
    .await?;
    if !rows.is_empty() {
        return created(rows);
    }
    let existing: Vec<IdRow> = supabase::rows(
        env,
        Method::Get,
        &format!("items?dedupe_key=eq.{}&select=id", encode(key)),
        None,
        None,
    )
    .await?;
    match existing.into_iter().next() {
        Some(row) => json_response(200, &json!({ "id": row.id })),
        None => Err("dedupe_key conflicted but no item holds it".into()),
    }
}

fn created(rows: Vec<IdRow>) -> Result<Response> {
    let row = rows.into_iter().next().ok_or("insert returned no row")?;
    json_response(201, &json!({ "id": row.id }))
}

/// `GET /items`: the items still in effect, with the `seq` they are current as of.
pub async fn list(env: &Env) -> Result<Response> {
    // Read `seq` first: an event committed between the two reads is returned again
    // by `GET /events?since=<seq>`, and applying it twice is harmless.
    let latest: Vec<SeqRow> = supabase::rows(
        env,
        Method::Get,
        "events?select=seq&order=seq.desc&limit=1",
        None,
        None,
    )
    .await?;
    let seq = latest.first().map_or(0, |r| r.seq);

    let now = supabase::iso(supabase::now_ms())?;
    let items: Vec<Value> =
        supabase::rows(env, Method::Get, &active_items_path(&now), None, None).await?;
    json_response(200, &json!({ "seq": seq, "items": items }))
}

/// PostgREST path for items neither deleted nor expired at `now`, newest first.
fn active_items_path(now: &str) -> String {
    // Quoted because the timestamp holds `:` and `.`, which PostgREST reserves
    // inside logic trees.
    let filter = format!("(expires_at.is.null,expires_at.gt.\"{now}\")");
    format!(
        "items?deleted_at=is.null&or={}&order=created_at.desc",
        encode(&filter)
    )
}

/// `PATCH /items/{id}`: sets or clears the read state.
///
/// 204 when the item ends in the requested state, 404 when it does not exist or
/// was deleted: deletion wins over reading.
pub async fn patch(mut req: Request, env: &Env, id: &str) -> Result<Response> {
    let Some(read) = parse_read(&req.bytes().await?) else {
        return error(400, "invalid body");
    };
    let (read_at, unchanged) = if read {
        (Value::String(supabase::iso(supabase::now_ms())?), "is.null")
    } else {
        (Value::Null, "not.is.null")
    };
    let updated: Vec<IdRow> = supabase::rows(
        env,
        Method::Patch,
        &format!("items?id=eq.{id}&deleted_at=is.null&read_at={unchanged}&select=id"),
        Some(json!({ "read_at": read_at }).to_string()),
        Some("return=representation"),
    )
    .await?;
    if !updated.is_empty() {
        return no_content();
    }

    let found: Vec<DeletedRow> = supabase::rows(
        env,
        Method::Get,
        &format!("items?id=eq.{id}&select=deleted_at"),
        None,
        None,
    )
    .await?;
    match found.first() {
        Some(row) if row.deleted_at.is_none() => no_content(),
        _ => error(404, "not found"),
    }
}

/// `DELETE /items/{id}`: soft-deletes the item.
///
/// 204 when the item exists, deleted now or before; 404 when it does not exist.
pub async fn delete(env: &Env, id: &str) -> Result<Response> {
    let now = supabase::iso(supabase::now_ms())?;
    let updated: Vec<IdRow> = supabase::rows(
        env,
        Method::Patch,
        &format!("items?id=eq.{id}&deleted_at=is.null&select=id"),
        Some(json!({ "deleted_at": now }).to_string()),
        Some("return=representation"),
    )
    .await?;
    if !updated.is_empty() {
        return no_content();
    }

    let found: Vec<IdRow> = supabase::rows(
        env,
        Method::Get,
        &format!("items?id=eq.{id}&select=id"),
        None,
        None,
    )
    .await?;
    if found.is_empty() {
        error(404, "not found")
    } else {
        no_content()
    }
}

/// Error body for a rejected envelope, naming the offending field.
fn invalid_envelope(field: &str, message: &str) -> Value {
    json!({ "error": "invalid envelope", "field": field, "message": message })
}

/// Expiry in milliseconds since the epoch, or `None` when it falls past the JS
/// `Date` range.
fn expires_ms(now_ms: f64, ttl: Option<u64>) -> Option<f64> {
    let ttl_ms = ttl.unwrap_or(DEFAULT_TTL_SECS).saturating_mul(1000);
    let expires = now_ms + ttl_ms as f64;
    (expires <= MAX_JS_DATE_MS).then_some(expires)
}

/// Reads `{"read": true}` or `{"read": false}`; anything else is `None`.
fn parse_read(bytes: &[u8]) -> Option<bool> {
    let value: Value = serde_json::from_slice(bytes).ok()?;
    value.as_object()?.get("read")?.as_bool()
}

/// True for a hyphenated UUID such as `0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8b`.
///
/// Path ids are checked with this before they reach a PostgREST filter.
pub fn is_uuid(s: &str) -> bool {
    s.len() == 36
        && s.bytes().enumerate().all(|(i, b)| match i {
            8 | 13 | 18 | 23 => b == b'-',
            _ => b.is_ascii_hexdigit(),
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_envelope_names_field_and_message() {
        let e = envelope::parse(
            br#"{"v":1,"kind":"vocab","source":"s","title":"t","summary":"s",
                "body":{"word":"w","ipa":"i","pos":"n","meanings":[{}]}}"#,
        )
        .unwrap_err();
        assert_eq!(
            invalid_envelope(&e.field, &e.message),
            json!({
                "error": "invalid envelope",
                "field": "body.meanings[0]",
                "message": "missing field `definition`"
            })
        );
    }

    #[test]
    fn invalid_envelope_keeps_empty_root_field() {
        let e = envelope::parse(br#"{"v":1,"kind":"notification","source":"s","summary":"s"}"#)
            .unwrap_err();
        let v = invalid_envelope(&e.field, &e.message);
        assert_eq!(v["field"], json!(""));
        assert!(v["message"].as_str().unwrap().contains("title"), "{v}");
    }

    #[test]
    fn default_ttl_is_seven_days() {
        assert_eq!(DEFAULT_TTL_SECS, 604_800);
        assert_eq!(expires_ms(1_000.0, None), Some(1_000.0 + 604_800_000.0));
    }

    #[test]
    fn explicit_ttl_is_used() {
        assert_eq!(expires_ms(1_000.0, Some(60)), Some(61_000.0));
        assert_eq!(expires_ms(1_000.0, Some(0)), Some(1_000.0));
    }

    #[test]
    fn ttl_past_js_date_range_is_rejected() {
        let now = 1.8e12;
        assert_eq!(expires_ms(now, Some(u64::MAX)), None);
        assert_eq!(expires_ms(now, Some(9_000_000_000_000)), None);
        let largest = ((MAX_JS_DATE_MS - now) / 1000.0) as u64;
        assert!(expires_ms(now, Some(largest)).is_some());
    }

    #[test]
    fn read_body_true_and_false() {
        assert_eq!(parse_read(br#"{"read":true}"#), Some(true));
        assert_eq!(parse_read(br#"{"read":false}"#), Some(false));
        assert_eq!(
            parse_read(br#" { "read" : false, "extra": 1 } "#),
            Some(false)
        );
    }

    #[test]
    fn read_body_missing_read_is_rejected() {
        assert_eq!(parse_read(br#"{}"#), None);
        assert_eq!(parse_read(br#"{"unread":true}"#), None);
        assert_eq!(parse_read(b""), None);
        assert_eq!(parse_read(b"{"), None);
    }

    #[test]
    fn read_body_non_bool_is_rejected() {
        assert_eq!(parse_read(br#"{"read":"true"}"#), None);
        assert_eq!(parse_read(br#"{"read":1}"#), None);
        assert_eq!(parse_read(br#"{"read":null}"#), None);
        assert_eq!(parse_read(br#"[true]"#), None);
        assert_eq!(parse_read(b"true"), None);
    }

    #[test]
    fn uuid_accepted() {
        assert!(is_uuid("0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8b"));
        assert!(is_uuid("0B7A3C9E-5F0D-4C1E-9A2B-3C4D5E6F7A8B"));
        assert!(is_uuid(&uuid::Uuid::new_v4().to_string()));
    }

    #[test]
    fn non_uuid_rejected() {
        assert!(!is_uuid(""));
        assert!(!is_uuid("abc"));
        assert!(!is_uuid("0b7a3c9e5f0d4c1e9a2b3c4d5e6f7a8b"));
        assert!(!is_uuid("{0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8b}"));
        assert!(!is_uuid("0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8g"));
        assert!(!is_uuid("0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8b0"));
        assert!(!is_uuid("0b7a3c9e-5f0d-4c1e-9a2b3-c4d5e6f7a8b"));
        assert!(!is_uuid("0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8,"));
        assert!(!is_uuid("x&id=not.is.null-5f0d-4c1e-9a2b-3c4d5e"));
    }

    #[test]
    fn active_items_path_quotes_and_encodes_time() {
        assert_eq!(
            active_items_path("2026-11-23T02:00:00.000Z"),
            "items?deleted_at=is.null\
             &or=%28expires_at.is.null%2Cexpires_at.gt.%222026-11-23T02%3A00%3A00.000Z%22%29\
             &order=created_at.desc"
        );
    }
}
