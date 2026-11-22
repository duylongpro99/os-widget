//! HTTP API of os-widget: stores published envelopes in Supabase through PostgREST
//! and serves the ordered event log.

use envelope::Envelope;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use worker::{
    Env, Fetch, Headers, Method, Request, RequestInit, Response, Result, Router, event, js_sys,
    wasm_bindgen::JsValue,
};

/// Lifetime applied when the envelope carries no `ttl`.
const DEFAULT_TTL_SECS: u64 = 30 * 24 * 60 * 60;

/// Largest timestamp a JS `Date` can represent, in milliseconds since the epoch.
const MAX_JS_DATE_MS: f64 = 8.64e15;

#[event(fetch)]
async fn fetch(req: Request, env: Env, _ctx: worker::Context) -> Result<Response> {
    if !authorized(&req, &env)? {
        return error(401, "unauthorized");
    }
    Router::new()
        .post_async("/items", |req, ctx| post_items(req, ctx.env))
        .get_async("/events", |req, ctx| get_events(req, ctx.env))
        .run(req, env)
        .await
}

/// Checks `Authorization: Bearer <SPIKE_TOKEN>` in constant time.
fn authorized(req: &Request, env: &Env) -> Result<bool> {
    let expected = format!("Bearer {}", env.secret("SPIKE_TOKEN")?);
    let given = req.headers().get("Authorization")?.unwrap_or_default();
    let (a, b) = (expected.as_bytes(), given.as_bytes());
    let diff = a
        .iter()
        .zip(b)
        .fold(a.len() ^ b.len(), |acc, (x, y)| acc | usize::from(x ^ y));
    Ok(diff == 0)
}

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

async fn post_items(mut req: Request, env: Env) -> Result<Response> {
    let envelope: Envelope = match req.bytes().await.map(|b| serde_json::from_slice(&b)) {
        Ok(Ok(e)) => e,
        _ => return error(400, "invalid envelope"),
    };

    let body = serde_json::to_value(&envelope.content)?
        .get_mut("body")
        .map(Value::take)
        .unwrap_or(Value::Null);
    let ttl_ms = envelope
        .ttl
        .unwrap_or(DEFAULT_TTL_SECS)
        .saturating_mul(1000);
    let expires_ms = js_sys::Date::now() + ttl_ms as f64;
    // toISOString throws on dates past the JS range, which would trap the Wasm.
    if expires_ms > MAX_JS_DATE_MS {
        return error(400, "invalid envelope");
    }
    let expires_at = js_sys::Date::new(&JsValue::from_f64(expires_ms))
        .to_iso_string()
        .as_string()
        .ok_or("invalid ttl")?;

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
        expires_at,
    };

    let mut resp = supabase(
        &env,
        Method::Post,
        "items",
        Some(serde_json::to_string(&item)?),
    )
    .await?;
    if resp.status_code() >= 300 {
        return upstream_error(resp).await;
    }
    let rows: Vec<Value> = resp.json().await?;
    let id = rows
        .first()
        .and_then(|r| r.get("id"))
        .cloned()
        .ok_or("insert returned no row")?;
    Response::from_json(&json!({ "id": id }))
}

#[derive(Deserialize, Serialize)]
struct Event {
    seq: i64,
    #[serde(rename = "type")]
    kind: String,
    item_id: String,
    created_at: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    item: Option<Value>,
}

async fn get_events(req: Request, env: Env) -> Result<Response> {
    let url = req.url()?;
    let since = url
        .query_pairs()
        .find(|(k, _)| k == "since")
        .and_then(|(_, v)| v.parse::<i64>().ok());
    let Some(since) = since else {
        return error(400, "since must be an integer");
    };

    let mut resp = supabase(
        &env,
        Method::Get,
        &format!("events?seq=gt.{since}&order=seq.asc"),
        None,
    )
    .await?;
    if resp.status_code() >= 300 {
        return upstream_error(resp).await;
    }
    let mut events: Vec<Event> = resp.json().await?;

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
        let mut resp = supabase(&env, Method::Get, &format!("items?id=in.({list})"), None).await?;
        if resp.status_code() >= 300 {
            return upstream_error(resp).await;
        }
        let items: Vec<Value> = resp.json().await?;
        for event in events.iter_mut().filter(|e| e.kind == "item.created") {
            event.item = items
                .iter()
                .find(|i| i.get("id").and_then(Value::as_str) == Some(&event.item_id))
                .cloned();
        }
    }

    Response::from_json(&events)
}

/// Calls PostgREST at `{SUPABASE_URL}/rest/v1/{path}` with the service role key.
async fn supabase(env: &Env, method: Method, path: &str, body: Option<String>) -> Result<Response> {
    let base = env.var("SUPABASE_URL")?.to_string();
    let key = env.secret("SUPABASE_SERVICE_ROLE_KEY")?.to_string();

    let headers = Headers::new();
    headers.set("apikey", &key)?;
    headers.set("Authorization", &format!("Bearer {key}"))?;
    headers.set("Accept", "application/json")?;
    if body.is_some() {
        headers.set("Content-Type", "application/json")?;
        headers.set("Prefer", "return=representation")?;
    }

    let mut init = RequestInit::new();
    init.with_method(method)
        .with_headers(headers)
        .with_body(body.map(|b| JsValue::from_str(&b)));
    let url = format!("{}/rest/v1/{path}", base.trim_end_matches('/'));
    Fetch::Request(Request::new_with_init(&url, &init)?)
        .send()
        .await
}

/// Logs the PostgREST failure and returns 502 without echoing upstream details.
async fn upstream_error(mut resp: Response) -> Result<Response> {
    let status = resp.status_code();
    let text = resp.text().await.unwrap_or_default();
    worker::console_error!("supabase {status}: {text}");
    error(502, "upstream error")
}

fn error(status: u16, message: &str) -> Result<Response> {
    Ok(Response::from_json(&json!({ "error": message }))?.with_status(status))
}
