//! HTTP API of os-widget: stores published envelopes in Supabase through PostgREST
//! and serves items and the ordered event log.
//!
//! Every response body is JSON; errors are `{"error": "<code>"}`.

mod auth;
mod events;
mod items;
mod supabase;
mod vocab;

use auth::Role;
use serde::Serialize;
use serde_json::json;
use worker::{
    Env, Error, Method, Request, Response, Result, ScheduleContext, ScheduledEvent, event,
};

#[event(fetch)]
async fn fetch(req: Request, env: Env, _ctx: worker::Context) -> Result<Response> {
    match handle(req, &env).await {
        Ok(resp) => Ok(resp),
        Err(Error::RustError(msg)) if msg == supabase::UPSTREAM_FAILURE => error(502, &msg),
        Err(e) => {
            worker::console_error!("{e}");
            error(500, "internal error")
        }
    }
}

/// Cron Trigger: asks the database to send the next vocabulary word if one is due.
#[event(scheduled)]
async fn scheduled(_event: ScheduledEvent, env: Env, _ctx: ScheduleContext) {
    vocab::tick(&env).await;
}

async fn handle(req: Request, env: &Env) -> Result<Response> {
    // Tokens are checked before routing, so unknown paths reveal nothing to anonymous callers.
    let header = req.headers().get("Authorization")?;
    let publish = env.secret("PUBLISH_TOKEN")?.to_string();
    let client = env.secret("CLIENT_TOKEN")?.to_string();
    let Some(role) = auth::classify(header.as_deref(), &publish, &client) else {
        return error(401, "unauthorized");
    };

    let path = req.path();
    let route = match route(&req.method(), &path) {
        Ok(route) => route,
        Err(status) => return error(status, status_error(status)),
    };
    if route.role() != role {
        return error(403, "forbidden");
    }

    match route {
        Route::PostItems => items::post(req, env).await,
        Route::PostVocabWords => vocab::post(req, env).await,
        Route::GetItems => items::list(env).await,
        Route::GetEvents => events::list(req, env).await,
        Route::PatchItem(id) => items::patch(req, env, id).await,
        Route::DeleteItem(id) => items::delete(env, id).await,
    }
}

#[derive(Debug, PartialEq, Eq)]
enum Route<'a> {
    PostItems,
    PostVocabWords,
    GetItems,
    GetEvents,
    PatchItem(&'a str),
    DeleteItem(&'a str),
}

impl Route<'_> {
    /// The token an endpoint requires: publishing needs the publish token, all else the client token.
    fn role(&self) -> Role {
        match self {
            Route::PostItems | Route::PostVocabWords => Role::Publish,
            _ => Role::Client,
        }
    }
}

/// Maps a request to its endpoint, or to the 404 or 405 status to answer.
///
/// An item id that is not a UUID cannot name an item, so it is 404 and never
/// reaches a PostgREST filter.
fn route<'a>(method: &Method, path: &'a str) -> std::result::Result<Route<'a>, u16> {
    match path {
        "/items" => match method {
            Method::Post => Ok(Route::PostItems),
            Method::Get => Ok(Route::GetItems),
            _ => Err(405),
        },
        "/vocab/words" => match method {
            Method::Post => Ok(Route::PostVocabWords),
            _ => Err(405),
        },
        "/events" => match method {
            Method::Get => Ok(Route::GetEvents),
            _ => Err(405),
        },
        _ => {
            let id = path.strip_prefix("/items/").ok_or(404u16)?;
            if !items::is_uuid(id) {
                return Err(404);
            }
            match method {
                Method::Patch => Ok(Route::PatchItem(id)),
                Method::Delete => Ok(Route::DeleteItem(id)),
                _ => Err(405),
            }
        }
    }
}

fn status_error(status: u16) -> &'static str {
    match status {
        404 => "not found",
        _ => "method not allowed",
    }
}

pub(crate) fn json_response<T: Serialize>(status: u16, body: &T) -> Result<Response> {
    Ok(Response::from_json(body)?.with_status(status))
}

pub(crate) fn error(status: u16, code: &str) -> Result<Response> {
    json_response(status, &json!({ "error": code }))
}

pub(crate) fn no_content() -> Result<Response> {
    Ok(Response::empty()?.with_status(204))
}

#[cfg(test)]
mod tests {
    use super::*;

    const ID: &str = "0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8b";

    #[test]
    fn endpoints_resolve() {
        assert_eq!(route(&Method::Post, "/items"), Ok(Route::PostItems));
        assert_eq!(route(&Method::Get, "/items"), Ok(Route::GetItems));
        assert_eq!(route(&Method::Get, "/events"), Ok(Route::GetEvents));
        assert_eq!(
            route(&Method::Post, "/vocab/words"),
            Ok(Route::PostVocabWords)
        );
        let path = format!("/items/{ID}");
        assert_eq!(route(&Method::Patch, &path), Ok(Route::PatchItem(ID)));
        assert_eq!(route(&Method::Delete, &path), Ok(Route::DeleteItem(ID)));
    }

    #[test]
    fn only_publishing_needs_the_publish_token() {
        assert_eq!(Route::PostItems.role(), Role::Publish);
        assert_eq!(Route::PostVocabWords.role(), Role::Publish);
        assert_eq!(Route::GetItems.role(), Role::Client);
        assert_eq!(Route::GetEvents.role(), Role::Client);
        assert_eq!(Route::PatchItem(ID).role(), Role::Client);
        assert_eq!(Route::DeleteItem(ID).role(), Role::Client);
    }

    #[test]
    fn unknown_paths_are_404() {
        assert_eq!(route(&Method::Get, "/"), Err(404));
        assert_eq!(route(&Method::Get, "/nope"), Err(404));
        assert_eq!(route(&Method::Get, "/items/"), Err(404));
        assert_eq!(route(&Method::Get, "/events/1"), Err(404));
        assert_eq!(route(&Method::Post, "/vocab"), Err(404));
        assert_eq!(route(&Method::Post, "/vocab/words/"), Err(404));
        assert_eq!(route(&Method::Patch, &format!("/items/{ID}/x")), Err(404));
    }

    #[test]
    fn non_uuid_item_ids_are_404() {
        assert_eq!(route(&Method::Patch, "/items/abc"), Err(404));
        assert_eq!(route(&Method::Delete, "/items/1"), Err(404));
        assert_eq!(
            route(
                &Method::Delete,
                "/items/0b7a3c9e-5f0d-4c1e-9a2b-3c4d5e6f7a8b&x"
            ),
            Err(404)
        );
    }

    #[test]
    fn wrong_methods_are_405() {
        assert_eq!(route(&Method::Delete, "/items"), Err(405));
        assert_eq!(route(&Method::Post, "/events"), Err(405));
        for method in [Method::Get, Method::Put, Method::Delete, Method::Patch] {
            assert_eq!(route(&method, "/vocab/words"), Err(405));
        }
        assert_eq!(route(&Method::Get, &format!("/items/{ID}")), Err(405));
    }
}
