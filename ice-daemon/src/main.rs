#![windows_subsystem = "windows"]

use ax_sse::{Event, KeepAlive, Sse};
use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use futures_util::stream::Stream;
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, net::SocketAddr, process::Stdio, sync::{Arc, Mutex}, time::Duration};
use tokio::process::Command;
use tokio::io::{AsyncBufReadExt, BufReader};
use tower_http::cors::{Any, CorsLayer};
use tracing::{info, error};
use std::path::{Path, PathBuf};
use tokio::fs::File;
use tokio::io::AsyncWriteExt;
use tray_icon::{
    menu::{Menu, MenuItem, PredefinedMenuItem, MenuEvent},
    TrayIconBuilder, TrayIcon,
};
use crossbeam_channel::{unbounded, Sender};

// Simplified SSE types for Axum 0.7
mod ax_sse {
    pub use axum::response::sse::{Event, KeepAlive, Sse};
}

#[derive(Clone)]
struct AppState {
    downloads: Arc<Mutex<HashMap<String, DownloadState>>>,
    tray_tx: Sender<TrayCommand>,
}

enum TrayCommand {
    Show,
    Hide,
}

struct DownloadState {
    child_pid: Option<u32>,
    last_status: String,
    progress: Option<Progress>,
}

#[derive(Deserialize)]
struct DownloadRequest {
    url: String,
    format: String,
    quality: String,
    sponsorblock: bool,
    #[serde(rename = "embedMetadata")]
    embed_metadata: bool,
    #[serde(rename = "embedSubs")]
    embed_subs: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct Progress {
    percent: String,
    speed: String,
    eta: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(tag = "state")]
enum StatusResponse {
    #[serde(rename = "none")]
    None,
    #[serde(rename = "downloading")]
    Downloading { progress: Option<Progress> },
    #[serde(rename = "downloaded")]
    Downloaded,
    #[serde(rename = "error")]
    Error { error: String },
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let _ = tokio::spawn(async {
        if let Err(e) = ensure_ytdlp().await {
            error!("Failed to ensure yt-dlp: {}", e);
        }
    });

    let (tray_tx, tray_rx) = unbounded::<TrayCommand>();

    // Dedicated Tray Thread
    std::thread::spawn(move || {
        let mut tray_icon: Option<TrayIcon> = None;
        let menu_channel = MenuEvent::receiver();
        
        // Initial show
        tray_icon = create_tray();

        loop {
            // Handle Commands
            while let Ok(cmd) = tray_rx.try_recv() {
                match cmd {
                    TrayCommand::Show => {
                        if tray_icon.is_none() {
                            tray_icon = create_tray();
                        }
                    }
                    TrayCommand::Hide => {
                        tray_icon = None;
                    }
                }
            }

            // Handle Menu Events
            if let Ok(event) = menu_channel.try_recv() {
                if event.id == "quit" {
                    std::process::exit(0);
                } else if event.id == "restart" {
                    if let Ok(exe) = std::env::current_exe() {
                        let _ = std::process::Command::new(exe).spawn();
                        std::process::exit(0);
                    }
                }
            }

            std::thread::sleep(Duration::from_millis(100));
        }
    });

    let state = AppState {
        downloads: Arc::new(Mutex::new(HashMap::new())),
        tray_tx,
    };

    let app = Router::new()
        .route("/download", post(start_download))
        .route("/status", get(get_status))
        .route("/status/stream", get(status_stream))
        .route("/cancel", post(cancel_download))
        .route("/open", post(open_folder_api))
        .route("/config", post(update_config))
        .layer(
            CorsLayer::new()
                .allow_origin(Any)
                .allow_methods(Any)
                .allow_headers(Any),
        )
        .with_state(state);

    let addr = SocketAddr::from(([127, 0, 0, 1], 3100));
    info!("IceDaemon listening on {}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

fn create_tray() -> Option<TrayIcon> {
    let tray_menu = Menu::with_items(&[
        &MenuItem::with_id("restart", "Перезапустить", true, None),
        &PredefinedMenuItem::separator(),
        &MenuItem::with_id("quit", "Закрыть", true, None),
    ]).unwrap();

    let icon = load_icon();

    TrayIconBuilder::new()
        .with_menu(Box::new(tray_menu))
        .with_tooltip("IceDownloader Daemon")
        .with_icon(icon)
        .build()
        .ok()
}

fn load_icon() -> tray_icon::Icon {
    let path = Path::new("extension/icon.png");
    if path.exists() {
        if let Ok(image) = image::open(path) {
            let image = image.to_rgba8();
            let (width, height) = image.dimensions();
            let rgba = image.into_raw();
            return tray_icon::Icon::from_rgba(rgba, width, height).unwrap();
        }
    }
    tray_icon::Icon::from_rgba(vec![0; 16 * 16 * 4], 16, 16).unwrap()
}

async fn update_config(
    State(state): State<AppState>,
    Json(new_config): Json<HashMap<String, serde_json::Value>>,
) -> impl IntoResponse {
    if let Some(val) = new_config.get("showTray") {
        if val.as_bool().unwrap_or(true) {
            let _ = state.tray_tx.send(TrayCommand::Show);
        } else {
            let _ = state.tray_tx.send(TrayCommand::Hide);
        }
    }
    StatusCode::OK
}

async fn ensure_ytdlp() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let path = Path::new("yt-dlp.exe");
    if path.exists() { return Ok(()); }
    let url = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe";
    let response = reqwest::get(url).await?;
    let mut file = File::create(path).await?;
    let content = response.bytes().await?;
    file.write_all(&content).await?;
    Ok(())
}

async fn start_download(
    State(state): State<AppState>,
    Json(req): Json<DownloadRequest>,
) -> impl IntoResponse {
    let url = req.url.clone();
    let mut downloads = state.downloads.lock().unwrap();
    if downloads.contains_key(&url) {
        return (StatusCode::CONFLICT, "Already downloading").into_response();
    }
    downloads.insert(url.clone(), DownloadState {
        child_pid: None,
        last_status: "downloading".to_string(),
        progress: None,
    });
    drop(downloads);
    tokio::spawn(async move { run_ytdlp(req, state).await; });
    StatusCode::OK.into_response()
}

async fn run_ytdlp(req: DownloadRequest, state: AppState) {
    let url_clone = req.url.clone();
    let mut args = vec![
        "--progress", "--newline",
        "--progress-template", "DOWNLOAD:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
    ];
    if req.format == "audio" { args.extend_from_slice(&["-x", "--audio-format", "mp3"]); }
    if req.sponsorblock { args.extend_from_slice(&["--sponsorblock-remove", "all"]); }
    if req.embed_metadata { args.extend_from_slice(&["--embed-metadata", "--embed-thumbnail"]); }
    if req.embed_subs && req.format != "audio" { args.extend_from_slice(&["--write-auto-subs", "--embed-subs"]); }
    args.push(&req.url);

    let child = Command::new("./yt-dlp.exe")
        .args(&args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();

    let mut child = match child {
        Ok(c) => c,
        Err(e) => {
            error!("Spawn error: {}", e);
            state.downloads.lock().unwrap().remove(&url_clone);
            return;
        }
    };

    let pid = child.id().unwrap();
    {
        let mut downloads = state.downloads.lock().unwrap();
        if let Some(ds) = downloads.get_mut(&url_clone) {
            ds.child_pid = Some(pid);
        }
    }

    let stdout = child.stdout.take().unwrap();
    let mut reader = BufReader::new(stdout).lines();
    while let Ok(Some(line)) = reader.next_line().await {
        if line.starts_with("DOWNLOAD:") {
            let parts: Vec<&str> = line["DOWNLOAD:".len()..].split('|').collect();
            if parts.len() >= 3 {
                let mut downloads = state.downloads.lock().unwrap();
                if let Some(ds) = downloads.get_mut(&url_clone) {
                    ds.progress = Some(Progress {
                        percent: parts[0].trim().replace("%", ""),
                        speed: parts[1].to_string(),
                        eta: parts[2].to_string(),
                    });
                }
            }
        }
    }

    let status = child.wait().await;
    let mut downloads = state.downloads.lock().unwrap();
    if let Ok(s) = status {
        if s.success() {
            if let Some(ds) = downloads.get_mut(&url_clone) {
                ds.last_status = "downloaded".to_string();
            }
        } else { downloads.remove(&url_clone); }
    } else { downloads.remove(&url_clone); }
}

async fn get_status(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> impl IntoResponse {
    let url = params.get("url").cloned().unwrap_or_default();
    if url == "ping" { return Json(StatusResponse::None); }
    let downloads = state.downloads.lock().unwrap();
    if let Some(ds) = downloads.get(&url) {
        if ds.last_status == "downloaded" { return Json(StatusResponse::Downloaded); }
        return Json(StatusResponse::Downloading { progress: ds.progress.clone() });
    }
    Json(StatusResponse::None)
}

async fn status_stream(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Sse<impl Stream<Item = Result<Event, std::convert::Infallible>>> {
    let url = params.get("url").cloned().unwrap_or_default();
    let stream = async_stream::stream! {
        loop {
            let (res, done) = {
                match state.downloads.lock().unwrap().get(&url) {
                    Some(ds) if ds.last_status == "downloaded" => (StatusResponse::Downloaded, true),
                    Some(ds) => (StatusResponse::Downloading { progress: ds.progress.clone() }, false),
                    None => (StatusResponse::None, true),
                }
            };
            yield Ok(Event::default().data(serde_json::to_string(&res).unwrap()));
            if done { break; }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

async fn cancel_download(
    State(state): State<AppState>,
    Json(req): Json<HashMap<String, String>>,
) -> impl IntoResponse {
    let url = req.get("url").cloned().unwrap_or_default();
    if let Some(ds) = state.downloads.lock().unwrap().remove(&url) {
        if let Some(pid) = ds.child_pid {
            let _ = Command::new("taskkill").args(&["/F", "/PID", &pid.to_string()]).spawn();
        }
    }
    StatusCode::OK
}

async fn open_folder_api() -> impl IntoResponse {
    let _ = open_folder();
    StatusCode::OK
}

fn open_folder() -> Result<(), std::io::Error> {
    let path = PathBuf::from(std::env::var("USERPROFILE").unwrap_or_default()).join("Downloads");
    Command::new("explorer").arg(path).spawn()?;
    Ok(())
}
