use curio_server::{
    http::{Config, app},
    limits::Limits,
};
use std::{env, error::Error, net::SocketAddr, path::PathBuf, time::Duration};
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
        model: setting("OLLAMA_MODEL", "gemma4:12b"),
        public_origin: setting("PUBLIC_ORIGIN", ""),
        timeout: Duration::from_millis(setting("OLLAMA_TIMEOUT_MS", "120000").parse()?),
        // Questions allowed per caller and for everyone together; 0 = no limit.
        limits: Limits {
            per_minute: setting("QUESTIONS_PER_MINUTE", "10").parse()?,
            per_day: setting("QUESTIONS_PER_DAY", "200").parse()?,
            daily_cap: setting("QUESTIONS_DAILY_CAP", "1000").parse()?,
        },
        require_client_header: setting("REQUIRE_CLIENT_HEADER", "0") == "1",
    };
    let host = setting("HOST", "127.0.0.1");
    // The side-by-side default is deliberately separate from the live service.
    let port: u16 = setting("PORT", "11437").parse()?;
    let listener = TcpListener::bind((host.as_str(), port)).await?;
    let shutdown = CancellationToken::new();
    let router = app(config, shutdown.clone())?;
    println!("Curio ready at http://{}", listener.local_addr()?);
    let mut terminate = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    // "With connect info" hands each request the address of whoever connected.
    axum::serve(
        listener,
        router.into_make_service_with_connect_info::<SocketAddr>(),
    )
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
