use crate::agent::{McpRuntimeStatus, McpServerConfig, McpServerRegistry, McpServerState};
use crate::mcp_profiles::McpProfileState;
use crate::wallet_store::{SpendDecision, WalletOwner, WalletPolicy, WalletSnapshot};
use crate::{afm, browser_engine::*, security::*, AppState};
use afm_node::{AfmNodeController, AfmTaskDescriptor, GossipFrame, NodeStatus};
use anyhow::Result;
use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
use base64::Engine;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Runtime, State};
// use tokio::sync::Mutex as AsyncMutex;
use uuid::Uuid;

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
    let _protocol_handler = state.protocol_handler.lock().map_err(|e| e.to_string())?;

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

#[tauri::command]
pub async fn start_download<R: Runtime>(
    url: String,
    filename: String,
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<String, String> {
    state
        .browser_engine
        .start_download(url, filename)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_downloads<R: Runtime>(
    state: State<'_, AppState>,
    _app_handle: AppHandle<R>,
) -> Result<Vec<DownloadItem>, String> {
    state
        .browser_engine
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

impl Default for BrowserSettings {
    fn default() -> Self {
        Self {
            default_search_engine: "duckduckgo".to_string(),
            homepage: "https://vitalik.eth.limo/".to_string(),
            privacy_settings: PrivacySettings::default(),
            ipfs_gateway: "https://ipfs.io".to_string(),
            ens_resolver: Some("https://eth.limo".to_string()),
        }
    }
}

fn settings_storage_path() -> Result<PathBuf, String> {
    let base = std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .or_else(|| std::env::current_dir().ok())
        .ok_or_else(|| "Unable to resolve settings directory".to_string())?;

    let mut dir = base;
    dir.push(".advatar");
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
    serde_json::from_str(&data).map_err(|e| e.to_string())
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
