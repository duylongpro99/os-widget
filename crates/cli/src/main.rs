//! `os-widget`: command-line publisher for agents and cron jobs.
//!
//! `publish` validates an envelope with `envelope::parse` before sending it to
//! `POST /items`, so a malformed envelope never reaches the network.

use std::io::{self, Read, Write};
use std::process::ExitCode;
use std::time::Duration;

use clap::{Args, Parser, Subcommand, ValueEnum};
use envelope::Envelope;
use serde_json::{Map, Value, json};

const SERVER_ENV: &str = "OS_WIDGET_SERVER";
const TOKEN_ENV: &str = "OS_WIDGET_PUBLISH_TOKEN";
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// Exit code for an envelope rejected locally or by the server.
const EXIT_INVALID: u8 = 2;
/// Exit code for every other failure: auth, server, network, configuration.
const EXIT_FAILURE: u8 = 1;

#[derive(Debug, Parser)]
#[command(
    name = "os-widget",
    version,
    about = "Publish items to the os-widget server"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Validate an envelope and send it to `POST /items`.
    ///
    /// The server URL comes from OS_WIDGET_SERVER (or --server) and the token from
    /// OS_WIDGET_PUBLISH_TOKEN; the token is never accepted as a flag.
    Publish(PublishArgs),
}

#[derive(Debug, Args)]
struct PublishArgs {
    /// Server URL; overrides OS_WIDGET_SERVER.
    #[arg(long, value_name = "URL")]
    server: Option<String>,

    /// Validate and print the normalized envelope without sending it.
    #[arg(long)]
    dry_run: bool,

    /// Read a complete envelope from PATH, or from stdin when PATH is `-`.
    #[arg(
        long,
        value_name = "PATH",
        conflicts_with_all = ["source", "title", "summary", "text", "link", "priority", "ttl", "dedupe_key"]
    )]
    file: Option<String>,

    /// Sender name shown on the card (builds a `notification` envelope).
    #[arg(long, required_unless_present = "file")]
    source: Option<String>,

    /// One-line plain-text title.
    #[arg(long, required_unless_present = "file")]
    title: Option<String>,

    /// Short plain-text summary.
    #[arg(long, required_unless_present = "file")]
    summary: Option<String>,

    /// Short markdown shown as `body.text`.
    #[arg(long)]
    text: Option<String>,

    /// Link opened when the card is clicked.
    #[arg(long, value_name = "URL")]
    link: Option<String>,

    #[arg(long, value_enum)]
    priority: Option<PriorityArg>,

    /// Lifetime in seconds.
    #[arg(long, value_name = "SECS")]
    ttl: Option<u64>,

    /// Publishing again with the same key returns the existing item.
    #[arg(long, value_name = "KEY")]
    dedupe_key: Option<String>,
}

#[derive(Debug, Clone, Copy, ValueEnum)]
enum PriorityArg {
    Low,
    Normal,
    High,
}

impl PriorityArg {
    fn as_str(self) -> &'static str {
        match self {
            PriorityArg::Low => "low",
            PriorityArg::Normal => "normal",
            PriorityArg::High => "high",
        }
    }
}

/// What a command prints and how it exits.
#[derive(Debug, PartialEq, Eq)]
struct Report {
    stdout: Option<String>,
    stderr: Option<String>,
    code: u8,
}

impl Report {
    fn ok(stdout: String) -> Self {
        Self {
            stdout: Some(stdout),
            stderr: None,
            code: 0,
        }
    }

    fn invalid(detail: impl std::fmt::Display) -> Self {
        Self {
            stdout: None,
            stderr: Some(format!("invalid envelope: {detail}")),
            code: EXIT_INVALID,
        }
    }

    fn failure(message: impl Into<String>) -> Self {
        Self {
            stdout: None,
            stderr: Some(message.into()),
            code: EXIT_FAILURE,
        }
    }
}

/// Where and how to send a publish request.
#[derive(Debug, PartialEq, Eq)]
struct Config {
    items_url: String,
    token: String,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let report = match cli.command {
        Command::Publish(args) => publish(args),
    };
    if let Some(out) = &report.stdout {
        println!("{out}");
    }
    if let Some(err) = &report.stderr {
        eprintln!("{err}");
    }
    let _ = io::stdout().flush();
    ExitCode::from(report.code)
}

fn publish(args: PublishArgs) -> Report {
    let raw = match &args.file {
        Some(path) => match read_input(path) {
            Ok(bytes) => bytes,
            Err(e) => return Report::failure(format!("cannot read {path}: {e}")),
        },
        None => notification_json(&args),
    };
    let envelope = match envelope::parse(&raw) {
        Ok(envelope) => envelope,
        Err(e) => return Report::invalid(e),
    };

    if args.dry_run {
        return match serde_json::to_string_pretty(&envelope) {
            Ok(json) => Report::ok(json),
            Err(e) => Report::failure(format!("cannot serialize envelope: {e}")),
        };
    }

    let config = match resolve_config(
        args.server,
        std::env::var(SERVER_ENV).ok(),
        std::env::var(TOKEN_ENV).ok(),
    ) {
        Ok(config) => config,
        Err(message) => return Report::failure(message),
    };
    send(&config, &envelope)
}

fn read_input(path: &str) -> io::Result<Vec<u8>> {
    if path == "-" {
        let mut bytes = Vec::new();
        io::stdin().read_to_end(&mut bytes)?;
        Ok(bytes)
    } else {
        std::fs::read(path)
    }
}

/// Builds the JSON of a `notification` envelope from the flags.
///
/// The result is not validated here: it goes through `envelope::parse` like a
/// file would, so both inputs share one set of rules.
fn notification_json(args: &PublishArgs) -> Vec<u8> {
    let mut envelope = Map::new();
    envelope.insert("v".into(), json!(1));
    envelope.insert("kind".into(), json!("notification"));
    envelope.insert("source".into(), json!(args.source));
    envelope.insert("title".into(), json!(args.title));
    envelope.insert("summary".into(), json!(args.summary));
    if let Some(priority) = args.priority {
        envelope.insert("priority".into(), json!(priority.as_str()));
    }
    if let Some(link) = &args.link {
        envelope.insert("url".into(), json!(link));
    }
    if let Some(ttl) = args.ttl {
        envelope.insert("ttl".into(), json!(ttl));
    }
    if let Some(key) = &args.dedupe_key {
        envelope.insert("dedupe_key".into(), json!(key));
    }
    if let Some(text) = &args.text {
        envelope.insert("body".into(), json!({ "text": text }));
    }
    Value::Object(envelope).to_string().into_bytes()
}

/// Picks the server URL (flag over environment) and the token (environment only).
fn resolve_config(
    server_flag: Option<String>,
    server_env: Option<String>,
    token_env: Option<String>,
) -> Result<Config, String> {
    let server = server_flag
        .or(server_env)
        .map(|s| s.trim().trim_end_matches('/').to_owned())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("missing server URL: set {SERVER_ENV} or pass --server"))?;
    let token = token_env
        .map(|t| t.trim().to_owned())
        .filter(|t| !t.is_empty())
        .ok_or_else(|| format!("missing publish token: set {TOKEN_ENV}"))?;
    Ok(Config {
        items_url: format!("{server}/items"),
        token,
    })
}

fn send(config: &Config, envelope: &Envelope) -> Report {
    let body = match serde_json::to_vec(envelope) {
        Ok(body) => body,
        Err(e) => return Report::failure(format!("cannot serialize envelope: {e}")),
    };
    // Status codes are answers to map, not transport errors.
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_global(Some(REQUEST_TIMEOUT))
        .build()
        .into();
    let result = agent
        .post(&config.items_url)
        .header("Authorization", format!("Bearer {}", config.token))
        .header("Content-Type", "application/json")
        .send(&body[..]);
    let mut response = match result {
        Ok(response) => response,
        Err(e) => return Report::failure(format!("request to {} failed: {e}", config.items_url)),
    };
    let status = response.status().as_u16();
    match response.body_mut().read_to_string() {
        Ok(text) => interpret_response(status, &text),
        Err(e) => Report::failure(format!(
            "HTTP {status}: cannot read response from {}: {e}",
            config.items_url
        )),
    }
}

/// Turns the server's answer to `POST /items` into what the command prints.
fn interpret_response(status: u16, body: &str) -> Report {
    let json: Option<Value> = serde_json::from_str(body).ok();
    let text = |key: &str| {
        json.as_ref()
            .and_then(|v| v.get(key))
            .and_then(Value::as_str)
            .map(str::to_owned)
    };

    match status {
        201 | 200 => match text("id") {
            Some(id) if status == 201 => Report::ok(id),
            Some(id) => Report {
                stdout: Some(id),
                stderr: Some("duplicate: existing item returned".into()),
                code: 0,
            },
            None => Report::failure(format!(
                "HTTP {status}: response has no id: {}",
                snippet(body)
            )),
        },
        400 => match (text("field"), text("message")) {
            (Some(field), Some(message)) if !field.is_empty() => {
                Report::invalid(format!("{field}: {message}"))
            }
            (_, Some(message)) => Report::invalid(message),
            _ => Report::invalid(format!("HTTP 400: {}", snippet(body))),
        },
        _ => {
            let reason = text("error").unwrap_or_else(|| snippet(body));
            let hint = match status {
                401 => format!(" (check {TOKEN_ENV})"),
                403 => format!(" ({TOKEN_ENV} is not a publish token)"),
                _ => String::new(),
            };
            Report::failure(format!("HTTP {status}: {reason}{hint}"))
        }
    }
}

/// A short, single-line excerpt of a response body for error messages.
fn snippet(body: &str) -> String {
    const MAX: usize = 200;
    let line = body.split_whitespace().collect::<Vec<_>>().join(" ");
    if line.is_empty() {
        return "empty response".into();
    }
    match line.char_indices().nth(MAX) {
        Some((cut, _)) => format!("{}…", &line[..cut]),
        None => line,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use envelope::{Body, NotificationBody, Priority};

    fn parse_args(extra: &[&str]) -> Result<PublishArgs, clap::Error> {
        let argv = ["os-widget", "publish"].iter().chain(extra);
        Cli::try_parse_from(argv).map(|cli| match cli.command {
            Command::Publish(args) => args,
        })
    }

    /// The required notification flags followed by `extra`.
    fn flags<'a>(extra: &[&'a str]) -> Vec<&'a str> {
        let mut all = vec![
            "--source",
            "blog-agents",
            "--title",
            "New post",
            "--summary",
            "Read it",
        ];
        all.extend_from_slice(extra);
        all
    }

    fn envelope_from(extra: &[&str]) -> Envelope {
        let args = parse_args(&flags(extra)).unwrap();
        envelope::parse(&notification_json(&args)).unwrap()
    }

    #[test]
    fn minimal_flags_build_a_valid_notification() {
        let e = envelope_from(&[]);
        assert_eq!(e.v, 1);
        assert_eq!(e.content, Body::Notification(None));
        assert_eq!(e.source, "blog-agents");
        assert_eq!(e.title, "New post");
        assert_eq!(e.summary, "Read it");
        assert_eq!(e.priority, Priority::Normal);
        assert_eq!((e.url, e.ttl, e.dedupe_key), (None, None, None));
    }

    #[test]
    fn text_goes_into_body_text() {
        let e = envelope_from(&["--text", "**hi**"]);
        assert_eq!(
            e.content,
            Body::Notification(Some(NotificationBody {
                text: Some("**hi**".into())
            }))
        );
    }

    #[test]
    fn optional_flags_map_to_envelope_fields() {
        let e = envelope_from(&[
            "--link",
            "https://example.com/post",
            "--priority",
            "high",
            "--ttl",
            "3600",
            "--dedupe-key",
            "post-42",
        ]);
        assert_eq!(e.url.as_deref(), Some("https://example.com/post"));
        assert_eq!(e.priority, Priority::High);
        assert_eq!(e.ttl, Some(3600));
        assert_eq!(e.dedupe_key.as_deref(), Some("post-42"));
    }

    #[test]
    fn unknown_priority_is_rejected_by_clap() {
        let err = parse_args(&flags(&["--priority", "urgent"])).unwrap_err();
        assert_eq!(err.kind(), clap::error::ErrorKind::InvalidValue);
    }

    #[test]
    fn file_conflicts_with_notification_flags() {
        let err = parse_args(&["--file", "e.json", "--title", "t"]).unwrap_err();
        assert_eq!(err.kind(), clap::error::ErrorKind::ArgumentConflict);
    }

    #[test]
    fn file_alone_needs_no_notification_flags() {
        let args = parse_args(&["--file", "-", "--dry-run"]).unwrap();
        assert_eq!(args.file.as_deref(), Some("-"));
        assert!(args.dry_run);
    }

    #[test]
    fn notification_flags_are_required_without_file() {
        let err = parse_args(&["--source", "s", "--summary", "x"]).unwrap_err();
        assert_eq!(err.kind(), clap::error::ErrorKind::MissingRequiredArgument);
    }

    #[test]
    fn there_is_no_url_or_token_flag() {
        assert!(parse_args(&flags(&["--url", "https://example.com"])).is_err());
        assert!(parse_args(&flags(&["--token", "secret"])).is_err());
    }

    #[test]
    fn blank_title_from_flags_fails_local_validation() {
        let args = parse_args(&["--source", "s", "--title", " ", "--summary", "x"]).unwrap();
        let err = envelope::parse(&notification_json(&args)).unwrap_err();
        assert_eq!(
            Report::invalid(err).stderr.as_deref(),
            Some("invalid envelope: title: must not be empty")
        );
    }

    #[test]
    fn local_validation_error_names_the_field_and_exits_2() {
        let raw = br#"{"v":1,"kind":"vocab","source":"s","title":"t","summary":"s",
            "body":{"word":"w","ipa":"/w/","pos":"noun","meanings":[{"examples":[]}]}}"#;
        let report = Report::invalid(envelope::parse(raw).unwrap_err());
        assert_eq!(report.code, 2);
        assert_eq!(
            report.stderr.as_deref(),
            Some("invalid envelope: body.meanings[0]: missing field `definition`")
        );
    }

    #[test]
    fn normalized_envelope_parses_back_unchanged() {
        let e = envelope_from(&["--text", "hi", "--ttl", "60"]);
        let sent = serde_json::to_vec(&e).unwrap();
        assert_eq!(envelope::parse(&sent).unwrap(), e);

        let bare = envelope_from(&[]);
        let sent = serde_json::to_vec(&bare).unwrap();
        assert_eq!(envelope::parse(&sent).unwrap(), bare);
    }

    #[test]
    fn created_prints_id_and_exits_0() {
        assert_eq!(
            interpret_response(201, r#"{"id":"abc"}"#),
            Report::ok("abc".into())
        );
    }

    #[test]
    fn duplicate_prints_id_with_notice_and_exits_0() {
        let report = interpret_response(200, r#"{"id":"abc"}"#);
        assert_eq!(report.stdout.as_deref(), Some("abc"));
        assert_eq!(
            report.stderr.as_deref(),
            Some("duplicate: existing item returned")
        );
        assert_eq!(report.code, 0);
    }

    #[test]
    fn success_without_id_is_a_failure() {
        let report = interpret_response(201, "{}");
        assert_eq!(report.code, 1);
        assert_eq!(report.stdout, None);
    }

    #[test]
    fn server_400_uses_field_and_message_and_exits_2() {
        let body = r#"{"error":"invalid envelope","field":"body.meanings[0]","message":"missing field `definition`"}"#;
        let report = interpret_response(400, body);
        assert_eq!(report.code, 2);
        assert_eq!(report.stdout, None);
        assert_eq!(
            report.stderr.as_deref(),
            Some("invalid envelope: body.meanings[0]: missing field `definition`")
        );
    }

    #[test]
    fn server_400_with_root_field_shows_message_only() {
        let body = r#"{"error":"invalid envelope","field":"","message":"missing field `title`"}"#;
        assert_eq!(
            interpret_response(400, body).stderr.as_deref(),
            Some("invalid envelope: missing field `title`")
        );
    }

    #[test]
    fn server_400_without_details_still_exits_2() {
        let report = interpret_response(400, "Bad Request");
        assert_eq!(report.code, 2);
        assert_eq!(
            report.stderr.as_deref(),
            Some("invalid envelope: HTTP 400: Bad Request")
        );
    }

    #[test]
    fn unauthorized_exits_1_with_status() {
        let report = interpret_response(401, r#"{"error":"unauthorized"}"#);
        assert_eq!(report.code, 1);
        assert_eq!(report.stdout, None);
        assert_eq!(
            report.stderr.as_deref(),
            Some("HTTP 401: unauthorized (check OS_WIDGET_PUBLISH_TOKEN)")
        );
    }

    #[test]
    fn forbidden_and_server_errors_exit_1_with_status() {
        let forbidden = interpret_response(403, r#"{"error":"forbidden"}"#);
        assert_eq!(forbidden.code, 1);
        assert!(forbidden.stderr.unwrap().starts_with("HTTP 403: forbidden"));

        let server = interpret_response(503, "<html>\n upstream down </html>");
        assert_eq!(server.code, 1);
        assert_eq!(
            server.stderr.as_deref(),
            Some("HTTP 503: <html> upstream down </html>")
        );
    }

    #[test]
    fn server_flag_overrides_environment() {
        let config = resolve_config(
            Some("https://flag.example/".into()),
            Some("https://env.example".into()),
            Some("tok".into()),
        )
        .unwrap();
        assert_eq!(
            config,
            Config {
                items_url: "https://flag.example/items".into(),
                token: "tok".into()
            }
        );
    }

    #[test]
    fn server_comes_from_environment_without_flag() {
        let config =
            resolve_config(None, Some("https://env.example".into()), Some("tok".into())).unwrap();
        assert_eq!(config.items_url, "https://env.example/items");
    }

    #[test]
    fn missing_server_or_token_is_reported() {
        let no_server = resolve_config(None, None, Some("tok".into())).unwrap_err();
        assert!(no_server.contains("OS_WIDGET_SERVER"), "{no_server}");

        let no_token =
            resolve_config(None, Some("https://env.example".into()), Some(" ".into())).unwrap_err();
        assert!(no_token.contains("OS_WIDGET_PUBLISH_TOKEN"), "{no_token}");
    }

    #[test]
    fn snippet_is_single_line_and_bounded() {
        assert_eq!(snippet(""), "empty response");
        let long = "é".repeat(500);
        let s = snippet(&long);
        assert_eq!(s.chars().count(), 201);
        assert!(s.ends_with('…'));
    }
}
