//! PostgREST calls with the service role key, and the timestamps they need.

use serde::de::DeserializeOwned;
use worker::{
    Env, Error, Fetch, Headers, Method, Request, RequestInit, Result, js_sys, wasm_bindgen::JsValue,
};

/// Error message that marks a failed PostgREST call; the router answers it with 502.
pub const UPSTREAM_FAILURE: &str = "upstream error";

/// Calls `{SUPABASE_URL}/rest/v1/{path}` and decodes the returned rows.
///
/// A non-2xx answer is logged and turned into an error carrying
/// [`UPSTREAM_FAILURE`], so upstream details never reach the caller.
pub async fn rows<T: DeserializeOwned>(
    env: &Env,
    method: Method,
    path: &str,
    body: Option<String>,
    prefer: Option<&str>,
) -> Result<Vec<T>> {
    let base = env.var("SUPABASE_URL")?.to_string();
    let key = env.secret("SUPABASE_SERVICE_ROLE_KEY")?.to_string();

    let headers = Headers::new();
    headers.set("apikey", &key)?;
    headers.set("Authorization", &format!("Bearer {key}"))?;
    headers.set("Accept", "application/json")?;
    if body.is_some() {
        headers.set("Content-Type", "application/json")?;
    }
    if let Some(prefer) = prefer {
        headers.set("Prefer", prefer)?;
    }

    let mut init = RequestInit::new();
    init.with_method(method)
        .with_headers(headers)
        .with_body(body.map(|b| JsValue::from_str(&b)));
    let url = format!("{}/rest/v1/{path}", base.trim_end_matches('/'));
    let mut resp = Fetch::Request(Request::new_with_init(&url, &init)?)
        .send()
        .await?;

    let status = resp.status_code();
    if !(200..300).contains(&status) {
        let text = resp.text().await.unwrap_or_default();
        worker::console_error!("supabase {status}: {text}");
        return Err(Error::RustError(UPSTREAM_FAILURE.into()));
    }
    resp.json().await
}

/// Percent-encodes a query value, keeping only RFC 3986 unreserved characters.
pub fn encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            out.push(char::from(byte));
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

/// Current time in milliseconds since the epoch.
pub fn now_ms() -> f64 {
    js_sys::Date::now()
}

/// ISO 8601 timestamp for `ms` milliseconds since the epoch.
///
/// `ms` must be within the JS `Date` range: `toISOString` throws past it,
/// which would trap the Wasm.
pub fn iso(ms: f64) -> Result<String> {
    js_sys::Date::new(&JsValue::from_f64(ms))
        .to_iso_string()
        .as_string()
        .ok_or_else(|| Error::RustError("timestamp out of range".into()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_keeps_unreserved_characters() {
        assert_eq!(encode("abc-XYZ_0.9~"), "abc-XYZ_0.9~");
    }

    #[test]
    fn encode_escapes_reserved_and_non_ascii() {
        assert_eq!(encode("a b&c=d,e"), "a%20b%26c%3Dd%2Ce");
        assert_eq!(
            encode("2026-11-23T02:00:00.000+00:00"),
            "2026-11-23T02%3A00%3A00.000%2B00%3A00"
        );
        assert_eq!(encode("(\"x\")"), "%28%22x%22%29");
        assert_eq!(encode("é"), "%C3%A9");
    }
}
