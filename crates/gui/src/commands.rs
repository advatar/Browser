use crate::{AppState, browser_engine::*, protocol_handlers::*, security::*};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tauri::{AppHandle, Runtime, State};
use tokio::sync::Mutex as AsyncMutex;

// Tab management commands

#[tauri::command]
pub async fn create_tab<R: Runtime>(
    url: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    let tab_id = state.browser_engine
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
    state.browser_engine
        .close_tab(&tab_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn switch_tab<R: Runtime>(
    tab_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    state.browser_engine
        .switch_tab(&tab_id)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_tabs<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<Tab>, String> {
    state.browser_engine
        .get_tabs()
        .map_err(|e| e.to_string())
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
    state.browser_engine
        .add_bookmark(title, url, folder, tags)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_bookmarks<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<Bookmark>, String> {
    state.browser_engine
        .get_bookmarks()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn remove_bookmark<R: Runtime>(
    bookmark_id: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    state.browser_engine
        .remove_bookmark(&bookmark_id)
        .map_err(|e| e.to_string())
}

// History management commands

#[tauri::command]
pub async fn get_history<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<HistoryEntry>, String> {
    state.browser_engine
        .get_history()
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn clear_history<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    // Clear history in browser engine
    if let Ok(mut history) = state.browser_engine.history.lock() {
        history.clear();
    }
    Ok(())
}

// Protocol handling commands

#[tauri::command]
pub fn resolve_protocol_url<R: Runtime>(
    url: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    let protocol_handler = state.protocol_handler
        .lock()
        .map_err(|e| e.to_string())?;
    
    // Since we can't make this async, we'll just return the URL as is
    // This is a simplified version - in a real app, you'd want to handle this differently
    // or ensure the handler doesn't need to be async
    Ok(url)
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
    let mut security_manager = state.security_manager
        .lock()
        .map_err(|e| e.to_string())?;
    
    security_manager.update_privacy_settings(settings);
    Ok(())
}

#[tauri::command]
pub async fn get_security_status<R: Runtime>(
    url: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<SecurityStatus, String> {
    let security_manager = state.security_manager
        .lock()
        .map_err(|e| e.to_string())?;
    
    let is_secure = security_manager
        .validate_url_security(&url)
        .map_err(|e| e.to_string())?;
    
    Ok(SecurityStatus {
        is_secure,
        certificate_valid: true, // TODO: Implement certificate validation
        privacy_settings: security_manager.privacy_settings.clone(),
        blocked_requests: 0, // TODO: Track blocked requests
    })
}

// Download management commands

#[tauri::command]
pub async fn start_download<R: Runtime>(
    url: String,
    filename: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    state.browser_engine
        .start_download(url, filename)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_downloads<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<DownloadItem>, String> {
    state.browser_engine
        .get_downloads()
        .map_err(|e| e.to_string())
}

// Cookie management commands

#[tauri::command]
pub async fn get_cookies<R: Runtime>(
    domain: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<Cookie>, String> {
    let security_manager = state.security_manager
        .lock()
        .map_err(|e| e.to_string())?;
    
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
    let security_manager = state.security_manager
        .lock()
        .map_err(|e| e.to_string())?;
    
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
    let security_manager = state.security_manager
        .lock()
        .map_err(|e| e.to_string())?;
    
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
    let security_manager = state.security_manager
        .lock()
        .map_err(|e| e.to_string())?;
    
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
pub async fn get_wallet_info<R: Runtime>(
    _app_handle: AppHandle<R>,
) -> Result<WalletInfo, String> {
    // TODO: Integrate with blockchain crate wallet
    Ok(WalletInfo {
        address: "0x...".to_string(),
        balance: "0.0 ETH".to_string(),
        network: "Ethereum Mainnet".to_string(),
        is_connected: false,
    })
}

#[tauri::command]
pub async fn connect_wallet<R: Runtime>(
    _app_handle: AppHandle<R>,
) -> Result<WalletInfo, String> {
    // TODO: Implement wallet connection
    Err("Wallet connection not implemented yet".to_string())
}

#[tauri::command]
pub async fn disconnect_wallet<R: Runtime>(
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    // TODO: Implement wallet disconnection
    Ok(())
}

// Settings management commands

#[derive(Serialize, Deserialize)]
pub struct BrowserSettings {
    pub default_search_engine: String,
    pub homepage: String,
    pub privacy_settings: PrivacySettings,
    pub ipfs_gateway: String,
    pub ens_resolver: Option<String>,
}

impl Default for BrowserSettings {
    fn default() -> Self {
        Self {
            default_search_engine: "duckduckgo".to_string(),
            homepage: "about:blank".to_string(),
            privacy_settings: PrivacySettings::default(),
            ipfs_gateway: "https://ipfs.io".to_string(),
            ens_resolver: Some("https://cloudflare-eth.com".to_string()),
        }
    }
}

#[tauri::command]
pub async fn get_settings<R: Runtime>(
    _app_handle: AppHandle<R>,
) -> Result<BrowserSettings, String> {
    // TODO: Load settings from persistent storage
    Ok(BrowserSettings::default())
}

#[tauri::command]
pub async fn update_settings<R: Runtime>(
    settings: BrowserSettings,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<(), String> {
    // Update protocol handler settings
    if let Ok(mut protocol_handler) = state.protocol_handler.lock() {
        protocol_handler.set_ipfs_gateway(settings.ipfs_gateway);
        protocol_handler.set_ens_resolver(settings.ens_resolver);
    }
    
    // Update security settings
    if let Ok(mut security_manager) = state.security_manager.lock() {
        security_manager.update_privacy_settings(settings.privacy_settings);
    }
    
    // TODO: Save settings to persistent storage
    Ok(())
}
