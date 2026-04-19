use crate::agent::{McpRuntimeStatus, McpServerConfig, McpServerRegistry, McpServerState};
use crate::mcp_profiles::McpProfileState;
use crate::wallet_store::{SpendDecision, WalletOwner, WalletPolicy, WalletSnapshot};
use crate::{afm, browser_engine::*, security::*, AppState};
use afm_node::{AfmNodeController, AfmTaskDescriptor, GossipFrame, NodeStatus};
use anyhow::Result;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine;
use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter, Manager, Runtime, State};
use tokio::io::AsyncWriteExt;
use tokio::sync::watch;
use uuid::Uuid;

pub const HISTORY_UPDATED_EVENT: &str = "browser://history-updated";
pub const TAB_STATE_UPDATED_EVENT: &str = "browser://tab-state-updated";
pub const DOWNLOADS_UPDATED_EVENT: &str = "browser://downloads-updated";
pub const NAVIGATION_BLOCKED_EVENT: &str = "browser://navigation-blocked";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TabStateUpdate {
    pub tab_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub loading: Option<bool>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NavigationBlockedEvent {
    pub tab_id: Option<String>,
    pub url: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DownloadSnapshot {
    pub id: String,
    pub url: String,
    pub filename: String,
    pub total_bytes: Option<u64>,
    pub received_bytes: u64,
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub start_time: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_time: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file_path: Option<String>,
}

fn to_download_snapshot(download: DownloadItem) -> DownloadSnapshot {
    let (status, error) = match download.state {
        DownloadState::InProgress => ("downloading".to_string(), None),
        DownloadState::Completed => ("completed".to_string(), None),
        DownloadState::Cancelled => ("cancelled".to_string(), None),
        DownloadState::Failed(message) => ("failed".to_string(), Some(message)),
    };

    DownloadSnapshot {
        id: download.id,
        url: download.url,
        filename: download.filename,
        total_bytes: download.total_bytes,
        received_bytes: download.received_bytes,
        status,
        error,
        start_time: download.start_time,
        completed_time: download.completed_time,
        file_path: download.file_path,
    }
}

pub fn emit_history_updated<R: Runtime>(
    app_handle: &AppHandle<R>,
    state: &AppState,
) -> Result<(), String> {
    let history = state
        .browser_engine
        .get_history()
        .map_err(|e| e.to_string())?;
    app_handle
        .emit(HISTORY_UPDATED_EVENT, &history)
        .map_err(|e| e.to_string())
}

pub fn emit_tab_state_updated<R: Runtime>(
    app_handle: &AppHandle<R>,
    payload: &TabStateUpdate,
) -> Result<(), String> {
    app_handle
        .emit(TAB_STATE_UPDATED_EVENT, payload)
        .map_err(|e| e.to_string())
}

pub fn emit_navigation_blocked<R: Runtime>(
    app_handle: &AppHandle<R>,
    payload: &NavigationBlockedEvent,
) -> Result<(), String> {
    app_handle
        .emit(NAVIGATION_BLOCKED_EVENT, payload)
        .map_err(|e| e.to_string())
}

pub fn emit_downloads_updated<R: Runtime>(
    app_handle: &AppHandle<R>,
    state: &AppState,
) -> Result<(), String> {
    let downloads = state
        .browser_engine
        .get_downloads()
        .map_err(|e| e.to_string())?
        .into_iter()
        .map(to_download_snapshot)
        .collect::<Vec<_>>();
    app_handle
        .emit(DOWNLOADS_UPDATED_EVENT, downloads)
        .map_err(|e| e.to_string())
}

// Tab management commands

#[tauri::command]
pub async fn create_tab<R: Runtime>(
    url: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    let tab_id = state
        .browser_engine
        .create_tab(url)
        .map_err(|e| e.to_string())?;
    Ok(tab_id)
}

#[tauri::command]
pub async fn close_tab<R: Runtime>(
    tab_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    state
        .browser_engine
        .close_tab(&tab_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn switch_tab<R: Runtime>(
    tab_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    state
        .browser_engine
        .switch_tab(&tab_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_tabs<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<Tab>, String> {
    state.browser_engine.get_tabs().map_err(|e| e.to_string())
}

// Bookmark management commands

#[tauri::command]
pub async fn add_bookmark<R: Runtime>(
    title: String,
    url: String,
    folder: Option<String>,
    tags: Vec<String>,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    state
        .browser_engine
        .add_bookmark(title, url, folder, tags)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_bookmarks<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<Bookmark>, String> {
    state
        .browser_engine
        .get_bookmarks()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn remove_bookmark<R: Runtime>(
    bookmark_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    state
        .browser_engine
        .remove_bookmark(&bookmark_id)
        .map_err(|e| e.to_string())
}

// History management commands

#[tauri::command]
pub async fn get_history<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<HistoryEntry>, String> {
    state
        .browser_engine
        .get_history()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn clear_history<R: Runtime>(
    state: State<'_, AppState>,
    app_handle: AppHandle<R>,
) -> Result<(), String> {
    state
        .browser_engine
        .clear_history()
        .map_err(|e| e.to_string())?;
    emit_history_updated(&app_handle, &state)?;
    Ok(())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchHistoryRequest {
    pub query: String,
    #[serde(default)]
    pub limit: Option<usize>,
}

#[tauri::command]
pub async fn search_history<R: Runtime>(
    request: SearchHistoryRequest,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<HistorySearchMatch>, String> {
    state
        .browser_engine
        .search_history(&request.query, request.limit.unwrap_or(12))
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn remove_history_entry<R: Runtime>(
    entry_id: String,
    state: State<'_, AppState>,
    app_handle: AppHandle<R>,
) -> Result<bool, String> {
    let removed = state
        .browser_engine
        .remove_history_entry(&entry_id)
        .map_err(|e| e.to_string())?;
    if removed {
        emit_history_updated(&app_handle, &state)?;
    }
    Ok(removed)
}

// Protocol handling commands

#[tauri::command]
pub async fn resolve_protocol_url<R: Runtime>(
    url: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    let handler = state
        .protocol_handler
        .lock()
        .map_err(|e| e.to_string())?
        .clone();
    handler
        .resolve_url(url.trim())
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn probe_runtime_url<R: Runtime>(
    url: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<bool, String> {
    let candidate = url.trim();
    if candidate.is_empty() {
        return Ok(false);
    }

    let handler = state
        .protocol_handler
        .lock()
        .map_err(|e| e.to_string())?
        .clone();
    let resolved = handler
        .resolve_url(candidate)
        .await
        .unwrap_or_else(|_| candidate.to_string());

    let parsed = match url::Url::parse(&resolved) {
        Ok(parsed) => parsed,
        Err(_) => return Ok(false),
    };

    let available = match parsed.scheme() {
        "ipfs" => probe_decentralized_url(&state, &resolved, "ipfs").await?,
        "ipns" => probe_decentralized_url(&state, &resolved, "ipns").await?,
        "http" | "https" => probe_http_url(&resolved).await,
        _ => false,
    };

    Ok(available)
}

async fn probe_decentralized_url(
    state: &State<'_, AppState>,
    url: &str,
    fallback_scheme: &str,
) -> Result<bool, String> {
    let handler = state
        .protocol_handler
        .lock()
        .map_err(|e| e.to_string())?
        .clone();

    Ok(tokio::time::timeout(
        Duration::from_secs(8),
        handler.load_custom_protocol_url(url, fallback_scheme),
    )
    .await
    .map(|result| result.is_ok())
    .unwrap_or(false))
}

async fn probe_http_url(url: &str) -> bool {
    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
    {
        Ok(client) => client,
        Err(_) => return false,
    };

    match client.get(url).send().await {
        Ok(response) => {
            let status = response.status();
            status.is_success() || status.is_redirection()
        }
        Err(_) => false,
    }
}

// Security management commands

#[derive(Serialize, Deserialize)]
pub struct SecurityStatus {
    pub is_secure: bool,
    pub certificate_valid: bool,
    pub privacy_settings: PrivacySettings,
    pub blocked_requests: u32,
}

#[tauri::command]
pub async fn update_security_settings<R: Runtime>(
    settings: PrivacySettings,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let mut security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;

    security_manager.update_privacy_settings(settings);
    Ok(())
}

#[tauri::command]
pub async fn get_security_status<R: Runtime>(
    url: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<SecurityStatus, String> {
    let security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;

    let is_secure = security_manager
        .validate_url_security(&url)
        .map_err(|e| e.to_string())?;

    Ok(SecurityStatus {
        is_secure,
        certificate_valid: security_manager.certificate_status_for_url(&url, is_secure),
        privacy_settings: security_manager.privacy_settings.clone(),
        blocked_requests: security_manager
            .blocked_request_count()
            .min(u32::MAX as u64) as u32,
    })
}

// Download management commands

fn preferred_data_root() -> Result<PathBuf, String> {
    if cfg!(target_os = "macos") {
        if let Some(home) = std::env::var_os("HOME") {
            return Ok(PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join("DecentralizedBrowser"));
        }
    }

    if cfg!(target_os = "windows") {
        if let Some(app_data) =
            std::env::var_os("LOCALAPPDATA").or_else(|| std::env::var_os("APPDATA"))
        {
            return Ok(PathBuf::from(app_data).join("DecentralizedBrowser"));
        }
    }

    if let Some(xdg) = std::env::var_os("XDG_DATA_HOME") {
        return Ok(PathBuf::from(xdg).join("decentralized-browser"));
    }

    if let Some(home) = std::env::var_os("HOME") {
        return Ok(PathBuf::from(home)
            .join(".local")
            .join("share")
            .join("decentralized-browser"));
    }

    Err("Unable to resolve application data directory".to_string())
}

fn downloads_directory() -> Result<PathBuf, String> {
    let dir = if let Some(home) = std::env::var_os("HOME") {
        PathBuf::from(home).join("Downloads")
    } else {
        preferred_data_root()?.join("downloads")
    };
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn sanitize_filename(name: &str) -> String {
    let trimmed = name.trim();
    let filtered = trimmed
        .chars()
        .map(|ch| match ch {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect::<String>()
        .trim()
        .trim_matches('.')
        .to_string();

    if filtered.is_empty() {
        "download.bin".to_string()
    } else {
        filtered
    }
}

fn unique_download_destination(filename: &str) -> Result<PathBuf, String> {
    let dir = downloads_directory()?;
    let sanitized = sanitize_filename(filename);
    let candidate = dir.join(&sanitized);
    if !candidate.exists() {
        return Ok(candidate);
    }

    let sanitized_path = PathBuf::from(&sanitized);
    let stem = sanitized_path
        .file_stem()
        .and_then(|value| value.to_str())
        .map(|value| value.to_string())
        .unwrap_or_else(|| "download".to_string());
    let ext = sanitized_path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| format!(".{}", value))
        .unwrap_or_default();

    for index in 1..=9999 {
        let next = dir.join(format!("{stem} ({index}){ext}"));
        if !next.exists() {
            return Ok(next);
        }
    }

    Err("Unable to allocate a unique download path".to_string())
}

fn temp_download_path(destination: &PathBuf) -> PathBuf {
    let file_name = destination
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("download.bin");
    destination.with_file_name(format!(".{}.part", file_name))
}

async fn cleanup_download_control(state: &AppState, download_id: &str) {
    let mut controls = state.download_controls.lock().await;
    controls.remove(download_id);
}

async fn run_download_task<R: Runtime>(
    app_handle: AppHandle<R>,
    download_id: String,
    url: String,
    destination: PathBuf,
    cancel_rx: watch::Receiver<bool>,
) {
    let Some(state) = app_handle.try_state::<AppState>() else {
        return;
    };

    let client = match reqwest::Client::builder()
        .timeout(Duration::from_secs(60))
        .build()
    {
        Ok(client) => client,
        Err(err) => {
            let _ = state.browser_engine.fail_download(
                &download_id,
                format!("failed to build download client: {err}"),
            );
            let _ = emit_downloads_updated(&app_handle, &state);
            cleanup_download_control(&state, &download_id).await;
            return;
        }
    };

    let response = match client.get(&url).send().await {
        Ok(response) => response,
        Err(err) => {
            let _ = state
                .browser_engine
                .fail_download(&download_id, format!("download request failed: {err}"));
            let _ = emit_downloads_updated(&app_handle, &state);
            cleanup_download_control(&state, &download_id).await;
            return;
        }
    };

    if !response.status().is_success() {
        let _ = state.browser_engine.fail_download(
            &download_id,
            format!("download failed with status {}", response.status()),
        );
        let _ = emit_downloads_updated(&app_handle, &state);
        cleanup_download_control(&state, &download_id).await;
        return;
    }

    let total_bytes = response.content_length();
    let _ = state
        .browser_engine
        .update_download(&download_id, 0, total_bytes);
    let _ = emit_downloads_updated(&app_handle, &state);

    let temp_path = temp_download_path(&destination);
    let mut file = match tokio::fs::File::create(&temp_path).await {
        Ok(file) => file,
        Err(err) => {
            let _ = state
                .browser_engine
                .fail_download(&download_id, format!("failed to create file: {err}"));
            let _ = emit_downloads_updated(&app_handle, &state);
            cleanup_download_control(&state, &download_id).await;
            return;
        }
    };

    let mut received_bytes = 0u64;
    let mut stream = response.bytes_stream();
    while let Some(item) = stream.next().await {
        if *cancel_rx.borrow() {
            let _ = tokio::fs::remove_file(&temp_path).await;
            let _ = state.browser_engine.cancel_download(&download_id);
            let _ = emit_downloads_updated(&app_handle, &state);
            cleanup_download_control(&state, &download_id).await;
            return;
        }

        let chunk = match item {
            Ok(bytes) => bytes,
            Err(err) => {
                let _ = tokio::fs::remove_file(&temp_path).await;
                let _ = state
                    .browser_engine
                    .fail_download(&download_id, format!("download stream failed: {err}"));
                let _ = emit_downloads_updated(&app_handle, &state);
                cleanup_download_control(&state, &download_id).await;
                return;
            }
        };

        if let Err(err) = file.write_all(&chunk).await {
            let _ = tokio::fs::remove_file(&temp_path).await;
            let _ = state
                .browser_engine
                .fail_download(&download_id, format!("failed to write file: {err}"));
            let _ = emit_downloads_updated(&app_handle, &state);
            cleanup_download_control(&state, &download_id).await;
            return;
        }

        received_bytes = received_bytes.saturating_add(chunk.len() as u64);
        let _ = state
            .browser_engine
            .update_download(&download_id, received_bytes, total_bytes);
        let _ = emit_downloads_updated(&app_handle, &state);
    }

    if let Err(err) = file.flush().await {
        let _ = tokio::fs::remove_file(&temp_path).await;
        let _ = state
            .browser_engine
            .fail_download(&download_id, format!("failed to flush file: {err}"));
        let _ = emit_downloads_updated(&app_handle, &state);
        cleanup_download_control(&state, &download_id).await;
        return;
    }

    if let Err(err) = tokio::fs::rename(&temp_path, &destination).await {
        let _ = tokio::fs::remove_file(&temp_path).await;
        let _ = state
            .browser_engine
            .fail_download(&download_id, format!("failed to finalize download: {err}"));
        let _ = emit_downloads_updated(&app_handle, &state);
        cleanup_download_control(&state, &download_id).await;
        return;
    }

    let _ = state
        .browser_engine
        .complete_download(&download_id, destination.to_string_lossy().into_owned());
    let _ = emit_downloads_updated(&app_handle, &state);
    cleanup_download_control(&state, &download_id).await;
}

#[tauri::command]
pub async fn start_download<R: Runtime>(
    url: String,
    filename: String,
    state: State<'_, AppState>,
    app_handle: AppHandle<R>,
) -> Result<String, String> {
    let candidate = url.trim();
    if candidate.is_empty() {
        return Err("url must not be empty".to_string());
    }

    {
        let security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;
        let allowed = security_manager
            .validate_url_security(candidate)
            .map_err(|e| e.to_string())?;
        if !allowed {
            return Err(format!("download blocked by security policy: {candidate}"));
        }
    }

    let destination = unique_download_destination(&filename)?;
    let filename = destination
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("download.bin")
        .to_string();

    let download_id = state
        .browser_engine
        .start_download(candidate.to_string(), filename.clone())
        .map_err(|e| e.to_string())?;

    let (cancel_tx, cancel_rx) = watch::channel(false);
    {
        let mut controls = state.download_controls.lock().await;
        controls.insert(
            download_id.clone(),
            crate::app_state::DownloadControl {
                url: candidate.to_string(),
                filename,
                destination: destination.clone(),
                cancel: cancel_tx,
            },
        );
    }

    emit_downloads_updated(&app_handle, &state)?;

    tauri::async_runtime::spawn(run_download_task(
        app_handle,
        download_id.clone(),
        candidate.to_string(),
        destination,
        cancel_rx,
    ));

    Ok(download_id)
}

#[tauri::command]
pub async fn get_downloads<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<DownloadSnapshot>, String> {
    state
        .browser_engine
        .get_downloads()
        .map_err(|e| e.to_string())
        .map(|downloads| downloads.into_iter().map(to_download_snapshot).collect())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CancelDownloadRequest {
    pub download_id: String,
}

#[tauri::command]
pub async fn cancel_download<R: Runtime>(
    request: CancelDownloadRequest,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let controls = state.download_controls.lock().await;
    let control = controls
        .get(request.download_id.trim())
        .ok_or_else(|| format!("unknown download `{}`", request.download_id.trim()))?;
    control.cancel.send(true).map_err(|_| {
        format!(
            "download `{}` is no longer active",
            request.download_id.trim()
        )
    })
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RevealDownloadRequest {
    pub download_id: String,
}

fn reveal_download_path(path: &str) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    {
        Command::new("open")
            .args(["-R", path])
            .status()
            .map_err(|e| e.to_string())
            .and_then(|status| {
                if status.success() {
                    Ok(())
                } else {
                    Err(format!("open exited with status {status}"))
                }
            })
    }

    #[cfg(target_os = "windows")]
    {
        Command::new("explorer")
            .args(["/select,", path])
            .status()
            .map_err(|e| e.to_string())
            .and_then(|status| {
                if status.success() {
                    Ok(())
                } else {
                    Err(format!("explorer exited with status {status}"))
                }
            })
    }

    #[cfg(all(not(target_os = "macos"), not(target_os = "windows")))]
    {
        let parent = PathBuf::from(path)
            .parent()
            .map(PathBuf::from)
            .ok_or_else(|| "download path does not have a parent directory".to_string())?;
        Command::new("xdg-open")
            .arg(parent)
            .status()
            .map_err(|e| e.to_string())
            .and_then(|status| {
                if status.success() {
                    Ok(())
                } else {
                    Err(format!("xdg-open exited with status {status}"))
                }
            })
    }
}

#[tauri::command]
pub async fn reveal_download<R: Runtime>(
    request: RevealDownloadRequest,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let download = state
        .browser_engine
        .get_downloads()
        .map_err(|e| e.to_string())?
        .into_iter()
        .find(|download| download.id == request.download_id.trim())
        .ok_or_else(|| format!("unknown download `{}`", request.download_id.trim()))?;
    let path = download
        .file_path
        .ok_or_else(|| "download file is not available yet".to_string())?;
    reveal_download_path(&path)
}

// Cookie management commands

#[tauri::command]
pub async fn get_cookies<R: Runtime>(
    domain: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<Cookie>, String> {
    let security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;

    security_manager
        .get_cookies(&domain)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn clear_cookies<R: Runtime>(
    domain: Option<String>,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;

    security_manager
        .clear_cookies(domain.as_deref())
        .map_err(|e| e.to_string())
}

// Domain blocking commands

#[tauri::command]
pub async fn block_domain<R: Runtime>(
    domain: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;

    security_manager
        .block_domain(&domain)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn unblock_domain<R: Runtime>(
    domain: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;

    security_manager
        .unblock_domain(&domain)
        .map_err(|e| e.to_string())
}

// Wallet integration commands (will be implemented with blockchain crate)

#[derive(Serialize, Deserialize)]
pub struct WalletInfo {
    pub address: String,
    pub balance: String,
    pub network: String,
    pub is_connected: bool,
}

#[tauri::command]
pub fn get_wallet_info<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<WalletInfo, String> {
    let snapshot = {
        let mut store = state.wallet_store.lock().map_err(|e| e.to_string())?;
        store.ensure_user_profile().map_err(|e| e.to_string())?;
        store
            .snapshot(&WalletOwner::User)
            .ok_or_else(|| "wallet snapshot unavailable".to_string())?
    };

    Ok(WalletInfo {
        address: snapshot.address.unwrap_or_default(),
        balance: "0".into(),
        network: "Local".into(),
        is_connected: snapshot.is_initialized,
    })
}

#[tauri::command]
pub fn connect_wallet<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<WalletInfo, String> {
    {
        let mut store = state.wallet_store.lock().map_err(|e| e.to_string())?;
        store
            .regenerate_wallet(WalletOwner::User)
            .map_err(|e| e.to_string())?;
    }
    get_wallet_info(state, _app_handle)
}

#[tauri::command]
pub fn disconnect_wallet<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let mut store = state.wallet_store.lock().map_err(|e| e.to_string())?;
    store
        .disconnect_wallet(WalletOwner::User)
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn get_agent_wallet<R: Runtime>(
    agent_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<WalletSnapshot, String> {
    let mut store = state.wallet_store.lock().map_err(|e| e.to_string())?;
    store
        .ensure_agent_profile(&agent_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn set_agent_wallet_policy<R: Runtime>(
    agent_id: String,
    policy: WalletPolicy,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<WalletSnapshot, String> {
    let mut store = state.wallet_store.lock().map_err(|e| e.to_string())?;
    let owner = WalletOwner::Agent(agent_id);
    store.set_policy(owner, policy).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn evaluate_agent_spend<R: Runtime>(
    agent_id: String,
    amount: u128,
    chain: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<SpendDecision, String> {
    let mut store = state.wallet_store.lock().map_err(|e| e.to_string())?;
    let owner = WalletOwner::Agent(agent_id);
    let _ = store
        .ensure_agent_profile(match &owner {
            WalletOwner::Agent(id) => id,
            WalletOwner::User => "user",
        })
        .map_err(|e| e.to_string())?;
    store
        .evaluate_spend(&owner, amount, &chain)
        .map_err(|e| e.to_string())
}

// Settings management commands

#[derive(Serialize, Deserialize, Clone)]
#[serde(default)]
pub struct BrowserSettings {
    pub default_search_engine: String,
    pub homepage: String,
    pub privacy_settings: PrivacySettings,
    pub ipfs_gateway: String,
    pub ens_resolver: Option<String>,
}

const DEFAULT_HOMEPAGE: &str = "https://duckduckgo.com";

fn sanitize_homepage(homepage: &str) -> String {
    let normalized = homepage.trim();
    if normalized.is_empty()
        || normalized == "https://vitalik.eth.limo/"
        || normalized == "https://opensea.eth.limo/"
        || normalized == "https://opensea.eth.limo"
    {
        DEFAULT_HOMEPAGE.to_string()
    } else {
        normalized.to_string()
    }
}

impl Default for BrowserSettings {
    fn default() -> Self {
        Self {
            default_search_engine: "duckduckgo".to_string(),
            homepage: DEFAULT_HOMEPAGE.to_string(),
            privacy_settings: PrivacySettings::default(),
            ipfs_gateway: "builtin://ipfs".to_string(),
            ens_resolver: Some("https://cloudflare-eth.com".to_string()),
        }
    }
}

fn settings_storage_path() -> Result<PathBuf, String> {
    let mut dir = preferred_data_root()?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    dir.push("browser-settings.json");
    Ok(dir)
}

fn load_settings_from_disk() -> Result<BrowserSettings, String> {
    let path = settings_storage_path()?;
    if !path.exists() {
        return Ok(BrowserSettings::default());
    }

    let data = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let mut settings = serde_json::from_str::<BrowserSettings>(&data).map_err(|e| e.to_string())?;
    settings.homepage = sanitize_homepage(&settings.homepage);
    Ok(settings)
}

fn save_settings_to_disk(settings: &BrowserSettings) -> Result<(), String> {
    let path = settings_storage_path()?;
    let payload = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    fs::write(&path, payload).map_err(|e| e.to_string())
}

pub fn apply_persisted_settings(state: &AppState) -> Result<BrowserSettings, String> {
    let settings = load_settings_from_disk().unwrap_or_else(|_| BrowserSettings::default());

    if let Ok(mut protocol_handler) = state.protocol_handler.lock() {
        protocol_handler.set_ipfs_gateway(settings.ipfs_gateway.clone());
        protocol_handler.set_ens_resolver(settings.ens_resolver.clone());
    }

    if let Ok(mut security_manager) = state.security_manager.lock() {
        security_manager.update_privacy_settings(settings.privacy_settings.clone());
    }

    Ok(settings)
}

#[tauri::command]
pub async fn get_settings<R: Runtime>(
    _app_handle: AppHandle<R>,
) -> Result<BrowserSettings, String> {
    load_settings_from_disk().or_else(|_| Ok(BrowserSettings::default()))
}

#[tauri::command]
pub async fn update_settings<R: Runtime>(
    settings: BrowserSettings,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let settings = BrowserSettings {
        homepage: sanitize_homepage(&settings.homepage),
        ..settings
    };

    // Update protocol handler settings
    if let Ok(mut protocol_handler) = state.protocol_handler.lock() {
        protocol_handler.set_ipfs_gateway(settings.ipfs_gateway.clone());
        protocol_handler.set_ens_resolver(settings.ens_resolver.clone());
    }

    // Update security settings
    if let Ok(mut security_manager) = state.security_manager.lock() {
        security_manager.update_privacy_settings(settings.privacy_settings.clone());
    }

    save_settings_to_disk(&settings)?;
    Ok(())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ManagedMcpServer {
    pub config: McpServerConfig,
    pub status: McpRuntimeStatus,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpProfileUpdatePayload {
    pub profile_state: McpProfileState,
    pub servers: Vec<ManagedMcpServer>,
}

#[tauri::command]
pub async fn list_mcp_servers<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<ManagedMcpServer>, String> {
    let (_, configs) = state
        .mcp_config
        .load_active_servers()
        .map_err(|e| e.to_string())?;
    let view = compose_mcp_view(configs, state.mcp_registry.clone()).await;
    Ok(view)
}

#[tauri::command]
pub async fn save_mcp_servers<R: Runtime>(
    servers: Vec<McpServerConfig>,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<ManagedMcpServer>, String> {
    let (_, sanitized) = state
        .mcp_config
        .save_active_servers(servers)
        .map_err(|e| e.to_string())?;
    state
        .mcp_registry
        .reload_active()
        .await
        .map_err(|e| e.to_string())?;
    let view = compose_mcp_view(sanitized, state.mcp_registry.clone()).await;
    Ok(view)
}

#[tauri::command]
pub async fn test_mcp_server<R: Runtime>(
    server: McpServerConfig,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<McpRuntimeStatus, String> {
    let resolved = state
        .mcp_config
        .resolve_inline_server(&server)
        .map_err(|e| e.to_string())?;
    state
        .mcp_registry
        .probe_resolved_config(resolved)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn list_mcp_profiles<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<McpProfileState, String> {
    state.mcp_config.profile_state().map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn set_active_mcp_profile<R: Runtime>(
    profile_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<McpProfileUpdatePayload, String> {
    state
        .mcp_config
        .set_active_profile(&profile_id)
        .map_err(|e| e.to_string())?;
    state
        .mcp_registry
        .reload_active()
        .await
        .map_err(|e| e.to_string())?;
    build_profile_payload(&state).await
}

#[tauri::command]
pub async fn create_mcp_profile<R: Runtime>(
    label: String,
    make_active: Option<bool>,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<McpProfileUpdatePayload, String> {
    let activate = make_active.unwrap_or(true);
    state
        .mcp_config
        .create_profile(&label, activate)
        .map_err(|e| e.to_string())?;
    if activate {
        state
            .mcp_registry
            .reload_active()
            .await
            .map_err(|e| e.to_string())?;
    }
    build_profile_payload(&state).await
}

#[tauri::command]
pub async fn import_mcp_profile<R: Runtime>(
    bundle_path: String,
    label: Option<String>,
    make_active: Option<bool>,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<McpProfileUpdatePayload, String> {
    let activate = make_active.unwrap_or(true);
    let path = PathBuf::from(&bundle_path);
    state
        .mcp_config
        .import_profile_from_path(&path, label.as_deref(), activate)
        .map_err(|e| e.to_string())?;
    if activate {
        state
            .mcp_registry
            .reload_active()
            .await
            .map_err(|e| e.to_string())?;
    }
    build_profile_payload(&state).await
}

#[tauri::command]
pub async fn export_mcp_profile<R: Runtime>(
    profile_id: Option<String>,
    target_path: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let profile = match profile_id {
        Some(id) => id,
        None => state
            .mcp_config
            .active_profile_id()
            .map_err(|e| e.to_string())?,
    };
    let path = PathBuf::from(&target_path);
    state
        .mcp_config
        .export_profile(&profile, &path)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn read_mcp_secret<R: Runtime>(
    secret_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    let vault = state.mcp_config.secret_store();
    vault.read(&secret_id).map_err(|e| e.to_string())
}

async fn compose_mcp_view(
    configs: Vec<McpServerConfig>,
    registry: Arc<McpServerRegistry>,
) -> Vec<ManagedMcpServer> {
    let snapshot = registry.status_snapshot().await;
    let mut status_map: HashMap<String, McpRuntimeStatus> = HashMap::with_capacity(snapshot.len());
    for (id, status) in snapshot {
        status_map.insert(id, status);
    }

    configs
        .into_iter()
        .map(|config| {
            let status = if config.enabled {
                status_map
                    .get(&config.id)
                    .cloned()
                    .unwrap_or_else(|| McpRuntimeStatus::new(McpServerState::Idle))
            } else {
                McpRuntimeStatus::new(McpServerState::Disabled)
            };
            ManagedMcpServer { config, status }
        })
        .collect()
}

async fn build_profile_payload(state: &AppState) -> Result<McpProfileUpdatePayload, String> {
    let (_, configs) = state
        .mcp_config
        .load_active_servers()
        .map_err(|e| e.to_string())?;
    let servers = compose_mcp_view(configs, state.mcp_registry.clone()).await;
    let profile_state = state
        .mcp_config
        .profile_state()
        .map_err(|e| e.to_string())?;
    Ok(McpProfileUpdatePayload {
        profile_state,
        servers,
    })
}

#[derive(Debug, Deserialize)]
pub struct AfmTaskRequest {
    #[serde(default)]
    pub task_id: Option<String>,
    #[serde(default)]
    pub payload: serde_json::Value,
}

#[derive(Debug, Deserialize)]
pub struct AfmGossipRequest {
    pub topic: String,
    #[serde(rename = "payloadB64")]
    pub payload_b64: String,
}

#[tauri::command]
pub async fn start_afm_node<R: Runtime>(
    state: State<'_, AppState>,
    app_handle: AppHandle<R>,
) -> Result<afm::AfmNodeSnapshot, String> {
    let mut controller_slot = state.afm_node_controller.lock().await;
    if controller_slot.is_some() {
        return Err("AFM node already running".to_string());
    }

    let resolved = {
        state
            .afm_node_config
            .lock()
            .map_err(|_| "AFM node config lock poisoned".to_string())
            .map(|cfg| afm::resolve_config(&cfg))?
    };

    let controller = AfmNodeController::launch(resolved.clone())
        .await
        .map_err(|err| err.to_string())?;
    let handle = controller.handle();

    {
        let mut cfg_slot = state
            .afm_node_config
            .lock()
            .map_err(|_| "AFM node config lock poisoned".to_string())?;
        *cfg_slot = resolved.clone();
    }

    {
        let mut handle_slot = state
            .afm_node_handle
            .lock()
            .map_err(|_| "AFM node handle lock poisoned".to_string())?;
        *handle_slot = Some(handle.clone());
    }

    let snapshot = afm::AfmNodeSnapshot::new(resolved, handle.status());
    *controller_slot = Some(controller);
    drop(controller_slot);

    if let Err(err) = app_handle.emit("afm-node-status", &snapshot) {
        tracing::warn!(
            target: "afm_node",
            error = %err,
            "failed to emit afm-node-status event after start"
        );
    }

    Ok(snapshot)
}

#[tauri::command]
pub async fn stop_afm_node<R: Runtime>(
    state: State<'_, AppState>,
    app_handle: AppHandle<R>,
) -> Result<afm::AfmNodeSnapshot, String> {
    let mut controller_slot = state.afm_node_controller.lock().await;
    let controller = controller_slot
        .take()
        .ok_or_else(|| "AFM node is not running".to_string())?;
    drop(controller_slot);

    controller
        .shutdown()
        .await
        .map_err(|err| format!("failed to stop AFM node: {err}"))?;

    let config = state
        .afm_node_config
        .lock()
        .map_err(|_| "AFM node config lock poisoned".to_string())?
        .clone();

    {
        let mut handle_slot = state
            .afm_node_handle
            .lock()
            .map_err(|_| "AFM node handle lock poisoned".to_string())?;
        *handle_slot = None;
    }

    let snapshot = afm::AfmNodeSnapshot::new(config, NodeStatus::default());
    if let Err(err) = app_handle.emit("afm-node-status", &snapshot) {
        tracing::warn!(
            target: "afm_node",
            error = %err,
            "failed to emit afm-node-status event after stop"
        );
    }

    Ok(snapshot)
}

#[tauri::command]
pub async fn afm_node_status<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<afm::AfmNodeSnapshot, String> {
    let config = state
        .afm_node_config
        .lock()
        .map_err(|_| "AFM node config lock poisoned".to_string())?
        .clone();
    let status = {
        let handle_slot = state
            .afm_node_handle
            .lock()
            .map_err(|_| "AFM node handle lock poisoned".to_string())?;
        handle_slot
            .as_ref()
            .map(|handle| handle.status())
            .unwrap_or_else(NodeStatus::default)
    };

    Ok(afm::AfmNodeSnapshot::new(config, status))
}

#[tauri::command]
pub async fn afm_submit_task<R: Runtime>(
    request: AfmTaskRequest,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let handle = state
        .afm_node_handle
        .lock()
        .map_err(|_| "AFM node handle lock poisoned".to_string())?
        .as_ref()
        .cloned()
        .ok_or_else(|| "AFM node is not running".to_string())?;

    let task_id = request
        .task_id
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    handle
        .submit_task(AfmTaskDescriptor::new(task_id, request.payload))
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
pub async fn afm_feed_gossip<R: Runtime>(
    request: AfmGossipRequest,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    let handle = state
        .afm_node_handle
        .lock()
        .map_err(|_| "AFM node handle lock poisoned".to_string())?
        .as_ref()
        .cloned()
        .ok_or_else(|| "AFM node is not running".to_string())?;

    let bytes = BASE64_STANDARD
        .decode(request.payload_b64.trim())
        .map_err(|err| format!("invalid base64 payload: {err}"))?;

    handle
        .feed_gossip(GossipFrame {
            topic: request.topic,
            bytes,
        })
        .await
        .map_err(|err| err.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    #[test]
    fn browser_settings_default_homepage_is_duckduckgo() {
        assert_eq!(BrowserSettings::default().homepage, DEFAULT_HOMEPAGE);
    }

    #[test]
    fn browser_settings_default_ens_resolver_matches_runtime_rpc_endpoint() {
        assert_eq!(
            BrowserSettings::default().ens_resolver.as_deref(),
            Some("https://cloudflare-eth.com")
        );
    }

    #[test]
    fn sanitize_homepage_rewrites_invalid_ens_defaults() {
        assert_eq!(
            sanitize_homepage("https://vitalik.eth.limo/"),
            DEFAULT_HOMEPAGE
        );
        assert_eq!(
            sanitize_homepage("https://opensea.eth.limo/"),
            DEFAULT_HOMEPAGE
        );
        assert_eq!(
            sanitize_homepage("https://opensea.eth.limo"),
            DEFAULT_HOMEPAGE
        );
        assert_eq!(sanitize_homepage("   "), DEFAULT_HOMEPAGE);
    }

    #[test]
    fn sanitize_homepage_keeps_valid_homepage() {
        assert_eq!(
            sanitize_homepage("https://example.com"),
            "https://example.com"
        );
        assert_eq!(
            sanitize_homepage("https://duckduckgo.com"),
            "https://duckduckgo.com"
        );
    }

    #[tokio::test]
    async fn probe_http_url_accepts_success_statuses() {
        let url = spawn_http_probe_server("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n").await;
        assert!(probe_http_url(&url).await);
    }

    #[tokio::test]
    async fn probe_http_url_rejects_client_errors() {
        let url =
            spawn_http_probe_server("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n").await;
        assert!(!probe_http_url(&url).await);
    }

    async fn spawn_http_probe_server(response: &'static str) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();

        tokio::spawn(async move {
            let (mut socket, _) = listener.accept().await.unwrap();
            let mut buffer = [0_u8; 1024];
            let _ = socket.read(&mut buffer).await;
            socket.write_all(response.as_bytes()).await.unwrap();
            socket.shutdown().await.unwrap();
        });

        format!("http://{}", address)
    }
}
