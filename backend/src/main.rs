use science_chatbot_server::http::{Config, app};
use std::{env, error::Error, path::PathBuf, time::Duration};
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;

fn setting(name: &str, default: &str) -> String {
    env::var(name)
        .ok()
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| default.into())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let config = Config {
        root: PathBuf::from(setting("ASSET_ROOT", ".")),
        upstream: setting("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
        model: setting("OLLAMA_MODEL", "qwen3:8b"),
        public_origin: setting("PUBLIC_ORIGIN", ""),
        timeout: Duration::from_millis(setting("OLLAMA_TIMEOUT_MS", "120000").parse()?),
    };
    let host = setting("HOST", "127.0.0.1");
    // The side-by-side default is deliberately separate from the live service.
    let port: u16 = setting("PORT", "11437").parse()?;
    let listener = TcpListener::bind((host.as_str(), port)).await?;
    let shutdown = CancellationToken::new();
    let router = app(config, shutdown.clone())?;
    println!("Science Chatbot ready at http://{}", listener.local_addr()?);
    let mut terminate = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    axum::serve(listener, router)
        .with_graceful_shutdown(async move {
            tokio::select! {
                _ = tokio::signal::ctrl_c() => {},
                _ = terminate.recv() => {},
            }
            shutdown.cancel();
        })
        .await?;
    Ok(())
}
