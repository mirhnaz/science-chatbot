//! HTTP boundary: keep Node's friendly errors rather than extractor defaults.
use std::{
    path::PathBuf,
    sync::Arc,
    time::{Duration, Instant},
};

use axum::{
    Router,
    body::{Body, to_bytes},
    extract::{Request, State},
    http::{HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
};
use serde_json::{Value, json};
use tokio::sync::Semaphore;
use tokio_util::sync::CancellationToken;

use crate::chat::{validate_question, validate_reply};

pub const TUTOR_PROMPT: &str = include_str!("tutor.txt");
const SCHEMA: &str = include_str!("reply-schema.json");
const UNCLEAR: &str = "The answer did not come through clearly. Could you try your question again?";
const OFFLINE: &str =
    "The science tutor is offline. Ask an adult to check the tutor computer and connection.";

#[derive(Clone)]
pub struct Config {
    pub root: PathBuf,
    pub upstream: String,
    pub model: String,
    pub public_origin: String,
    pub timeout: Duration,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            root: PathBuf::from(env!("CARGO_MANIFEST_DIR")).join(".."),
            upstream: "http://127.0.0.1:11434".into(),
            model: "qwen3:8b".into(),
            public_origin: String::new(),
            timeout: Duration::from_secs(120),
        }
    }
}

struct AppState {
    config: Config,
    client: reqwest::Client,
    slots: Semaphore,
    shutdown: CancellationToken,
}

pub fn app(config: Config, shutdown: CancellationToken) -> Result<Router, reqwest::Error> {
    let state = Arc::new(AppState {
        config,
        client: reqwest::Client::builder().build()?,
        slots: Semaphore::new(2),
        shutdown,
    });
    // A fallback handles all methods explicitly, including HEAD, so Axum does
    // not substitute its own 404/405 bodies or automatic HEAD-on-GET behavior.
    Ok(Router::new().fallback(handle).with_state(state))
}

async fn handle(State(state): State<Arc<AppState>>, request: Request) -> Response {
    let mut response = tokio::select! {
        response = dispatch(&state, request) => response,
        () = state.shutdown.cancelled() => error(503, "The science tutor is restarting. Please try again."),
    };
    let headers = response.headers_mut();
    headers.insert(
        "x-content-type-options",
        HeaderValue::from_static("nosniff"),
    );
    headers.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    headers.insert("content-security-policy", HeaderValue::from_static("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"));
    response
}

fn json_response(status: u16, value: Value) -> Response {
    (
        StatusCode::from_u16(status).expect("constant HTTP status"),
        [
            ("content-type", "application/json; charset=utf-8"),
            ("cache-control", "no-store"),
        ],
        value.to_string(),
    )
        .into_response()
}

fn error(status: u16, message: &str) -> Response {
    json_response(status, json!({"error": message}))
}

fn asset(path: &str) -> Option<(&'static str, &'static str)> {
    Some(match path {
        "/" => ("public/index.html", "text/html; charset=utf-8"),
        "/theme.js" => ("build/client/theme.js", "text/javascript; charset=utf-8"),
        "/app.js" => ("build/client/app.js", "text/javascript; charset=utf-8"),
        "/styles.css" => ("public/styles.css", "text/css; charset=utf-8"),
        "/favicon.ico" => ("public/favicon.ico", "image/vnd.microsoft.icon"),
        "/favicon-32.png" => ("public/favicon-32.png", "image/png"),
        "/apple-touch-icon.png" => ("public/apple-touch-icon.png", "image/png"),
        "/icon-192.png" => ("public/icon-192.png", "image/png"),
        "/icon-512.png" => ("public/icon-512.png", "image/png"),
        "/site.webmanifest" => ("public/site.webmanifest", "application/manifest+json"),
        _ => return None,
    })
}

async fn dispatch(state: &AppState, request: Request) -> Response {
    // URL parsing reproduces Node's dot-segment normalization without exposing
    // filesystem paths. Only the fixed allowlist below can read a file.
    let uri = request.uri().to_string();
    let Ok(url) = reqwest::Url::parse("http://localhost").and_then(|base| base.join(&uri)) else {
        return error(404, "Not found.");
    };
    let path = url.path();
    if path == "/api/suggestions" {
        if request.method() != Method::GET {
            let mut response = error(405, "Use GET.");
            response
                .headers_mut()
                .insert("allow", HeaderValue::from_static("GET"));
            return response;
        }
        if url.query().unwrap_or("").len() > 3000 {
            return error(400, "Too many recent suggestions.");
        }
        let exclusions: Vec<_> = url
            .query_pairs()
            .filter(|(key, _)| key == "exclude")
            .map(|(_, value)| value.into_owned())
            .collect();
        let recent: Vec<_> = exclusions
            .iter()
            .flat_map(|value| value.split(','))
            .filter(|id| !id.is_empty())
            .collect();
        if recent.len() > crate::suggestions::RECENT_LIMIT || recent.iter().any(|id| id.len() > 64)
        {
            return error(400, "Too many recent suggestions.");
        }
        return json_response(
            200,
            json!({"suggestions": crate::suggestions::select(&recent)}),
        );
    }
    if request.method() == Method::GET {
        if path == "/healthz" {
            return json_response(200, json!({"status": "ok"}));
        }
        if let Some((file, mime)) = asset(path) {
            return match tokio::fs::read(state.config.root.join(file)).await {
                Ok(body) => (
                    [("content-type", mime), ("cache-control", "no-cache")],
                    Body::from(body),
                )
                    .into_response(),
                Err(_) => error(500, "The page could not be loaded."),
            };
        }
    }
    if path != "/api/chat" {
        return error(404, "Not found.");
    }
    if request.method() != Method::POST {
        let mut response = error(405, "Use POST.");
        response
            .headers_mut()
            .insert("allow", HeaderValue::from_static("POST"));
        return response;
    }
    let headers = request.headers();
    let content_type = headers
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    if !content_type
        .split(';')
        .next()
        .unwrap_or("")
        .eq_ignore_ascii_case("application/json")
    {
        return error(415, "Send a JSON question.");
    }
    if let Some(origin) = headers.get("origin").filter(|v| !v.is_empty()) {
        let allowed = origin.to_str().ok().is_some_and(|origin| {
            if !state.config.public_origin.is_empty() {
                origin == state.config.public_origin
            } else {
                reqwest::Url::parse(origin).ok().is_some_and(|url| {
                    let host = &url[url::Position::BeforeHost..url::Position::AfterPort];
                    headers.get("host").and_then(|v| v.to_str().ok()) == Some(host)
                })
            }
        });
        if !allowed {
            return error(403, "This request came from a different website.");
        }
    }
    let body = match to_bytes(request.into_body(), 8192).await {
        Ok(body) => body,
        Err(_) => return error(413, "Please ask a shorter question."),
    };
    // Node decodes invalid UTF-8 with replacement before parsing JSON.
    let body: Value = match serde_json::from_str(&String::from_utf8_lossy(&body)) {
        Ok(body) => body,
        Err(_) => return error(400, "The question could not be read. Please try again."),
    };
    let question =
        match validate_question(body.get("question").and_then(Value::as_str).unwrap_or("")) {
            Ok(question) => question,
            Err(err) => return error(400, &err.to_string()),
        };
    let Ok(_permit) = state.slots.try_acquire() else {
        return error(429, "The science tutor is busy. Try again in a moment.");
    };
    // The permit and upstream future belong to this request. Dropping the
    // handler (disconnect/shutdown) drops both; no model task is detached.
    match tokio::time::timeout(state.config.timeout, ask(state, question)).await {
        Ok(response) => response,
        Err(_) => error(504, "That answer took too long. Try a shorter question."),
    }
}

async fn ask(state: &AppState, question: &str) -> Response {
    let started = Instant::now();
    let payload = json!({
        "model": state.config.model, "stream": false, "think": false,
        "format": serde_json::from_str::<Value>(SCHEMA).expect("embedded reply schema"),
        "messages": [{"role": "system", "content": TUTOR_PROMPT}, {"role": "user", "content": question}],
    });
    let response = match state
        .client
        .post(format!(
            "{}/api/chat",
            state.config.upstream.trim_end_matches('/')
        ))
        .json(&payload)
        .send()
        .await
    {
        Ok(response) => response,
        Err(_) => return error(502, OFFLINE),
    };
    if !response.status().is_success() {
        return error(
            502,
            if response.status() == StatusCode::NOT_FOUND {
                "The science model is not available. Ask an adult to check the tutor computer."
            } else {
                "The science tutor could not answer just now. Please try again."
            },
        );
    }
    let data = match response.json::<Value>().await {
        Ok(data) => data,
        Err(_) => return error(502, OFFLINE),
    };
    let reply = data
        .pointer("/message/content")
        .and_then(Value::as_str)
        .and_then(|content| serde_json::from_str::<Value>(content).ok())
        .unwrap_or(Value::Null);
    let answer = reply.get("answer").and_then(Value::as_str).unwrap_or("");
    let follow_ups: Vec<String> = reply
        .get("followUps")
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .map(|v| v.as_str().unwrap_or("").to_owned())
                .collect()
        })
        .unwrap_or_default();
    match validate_reply(answer, &follow_ups) {
        Ok(reply) => json_response(
            200,
            json!({"answer": reply.answer, "followUps": reply.follow_ups, "elapsedMs": started.elapsed().as_millis()}),
        ),
        Err(_) => error(502, UNCLEAR),
    }
}
