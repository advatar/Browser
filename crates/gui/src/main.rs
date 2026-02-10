#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use afm_node::AfmNodeConfig;
use ai_agent::McpToolDescription;
use serde::Deserialize;
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use tauri::Emitter;
use tauri::Manager; // bring Manager trait into scope
use tauri::{
    menu::{IsMenuItem, Menu, MenuItem, Submenu},
    Runtime, WebviewWindowBuilder,
};
use tauri_plugin_dialog;
use tokio::sync::Mutex as AsyncMutex;

// Use the library crate modules
use gui::agent::{
    AgentManager, AgentRunRequest, AgentRunResponse, AgentSkillSummary, ApprovalBroker,
    CreditSnapshot, McpServerRegistry,
};
use gui::agent_apps::{AgentAppRegistry, AgentAppSummary};
use gui::app_state::AppState;
use gui::browser_engine::BrowserEngine;
use gui::commands::*;
use gui::mcp_profiles::McpConfigService;
use gui::protocol_handlers::ProtocolHandler;
use gui::security::SecurityManager;
use gui::telemetry::TelemetryManager;
use gui::telemetry_commands::*;
use gui::wallet_store::WalletStore;

const MAIN_WEBVIEW_LABEL: &str = "main";
const CONTENT_WEBVIEW_LABEL: &str = "content";

fn log_path() -> PathBuf {
    let mut base = std::env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    base.push("Library/Logs/DecentralizedBrowser");
    // Ensure directory exists
    let _ = create_dir_all(&base);
    base.push("gui.log");
    base
}

fn log_startup(msg: &str) {
    let path = log_path();
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{} | {}", chrono_like_timestamp(), msg);
    }
}

fn chrono_like_timestamp() -> String {
    // Minimal, dependency-free timestamp using system time since UNIX_EPOCH
    use std::time::{SystemTime, UNIX_EPOCH};
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(dur) => format!("{}.{:03}", dur.as_secs(), dur.subsec_millis()),
        Err(_) => "0".to_string(),
    }
}

fn create_main_menu<R: Runtime, M: Manager<R>>(manager: &M) -> tauri::Result<Menu<R>> {
    log_startup("create_main_menu: start");
    // Create menu items
    let new_tab = MenuItem::with_id(manager, "new_tab", "New Tab", true, None::<&str>)?;
    let new_window = MenuItem::with_id(manager, "new_window", "New Window", true, None::<&str>)?;
    let settings = MenuItem::with_id(manager, "settings", "Settings", true, None::<&str>)?;
    let quit = MenuItem::with_id(manager, "quit", "Quit", true, None::<&str>)?;

    // Create file menu
    let file_menu = Submenu::with_items(
        manager,
        "File",
        true,
        &[
            &new_tab as &dyn IsMenuItem<R>,
            &new_window,
            &settings,
            &quit,
        ],
    )?;

    // Create edit menu
    let cut = MenuItem::with_id(manager, "cut", "Cut", true, Some("CmdOrCtrl+X"))?;
    let copy = MenuItem::with_id(manager, "copy", "Copy", true, Some("CmdOrCtrl+C"))?;
    let paste = MenuItem::with_id(manager, "paste", "Paste", true, Some("CmdOrCtrl+V"))?;
    let select_all = MenuItem::with_id(
        manager,
        "select_all",
        "Select All",
        true,
        Some("CmdOrCtrl+A"),
    )?;

    let edit_menu = Submenu::with_items(
        manager,
        "Edit",
        true,
        &[&cut as &dyn IsMenuItem<R>, &copy, &paste, &select_all],
    )?;

    // Create view menu
    let zoom_in = MenuItem::with_id(manager, "zoomin", "Zoom In", true, Some("CmdOrCtrl+Plus"))?;
    let zoom_out = MenuItem::with_id(manager, "zoomout", "Zoom Out", true, Some("CmdOrCtrl+-"))?;
    let reset_zoom = MenuItem::with_id(
        manager,
        "resetzoom",
        "Reset Zoom",
        true,
        Some("CmdOrCtrl+0"),
    )?;

    let view_menu = Submenu::with_items(
        manager,
        "View",
        true,
        &[&zoom_in as &dyn IsMenuItem<R>, &zoom_out, &reset_zoom],
    )?;

    // Create main menu
    let menu = Menu::with_items(
        manager,
        &[&file_menu as &dyn IsMenuItem<R>, &edit_menu, &view_menu],
    )?;
    log_startup("create_main_menu: success");

    Ok(menu)
}

fn create_browser_window<R: Runtime>(
    app: &tauri::AppHandle<R>,
    url: Option<&str>,
) -> tauri::Result<()> {
    log_startup("create_browser_window: start");
    let initial_url = url.unwrap_or("about:home");

    // Create the menu first
    let menu = create_main_menu(app)?;

    let webview =
        WebviewWindowBuilder::new(app, MAIN_WEBVIEW_LABEL, tauri::WebviewUrl::App("index.html".into()))
            .title("Decentralized Browser")
            .inner_size(1200.0, 800.0)
            .min_inner_size(800.0, 600.0)
            .menu(menu)
            .build()?;
    log_startup("create_browser_window: webview built");

    // Create a child webview that will host the actual browsing content.
    //
    // IMPORTANT: this must not have any IPC capabilities. We enforce that by scoping capabilities
    // to the `main` webview label (see `crates/gui/capabilities/main.json`).
    let content_webview = {
        use tauri::{LogicalPosition, LogicalSize};
        use tauri::webview::WebviewBuilder;

        let blank: url::Url = "about:blank".parse().unwrap_or_else(|_| {
            // `about:blank` should always parse; fallback is a defensive last resort.
            url::Url::parse("https://example.com").expect("fallback url parses")
        });
        let window = webview.as_ref().window();
        let child = window.add_child(
            WebviewBuilder::new(CONTENT_WEBVIEW_LABEL, tauri::WebviewUrl::External(blank)),
            LogicalPosition::new(0.0, 0.0),
            LogicalSize::new(0.0, 0.0),
        )?;
        let _ = child.hide();
        child
    };

    // Store the initial URL in the app state
    if let Some(state) = app.try_state::<AppState>() {
        if let Ok(mut current_url) = state.current_url.lock() {
            *current_url = initial_url.to_string();
        }
    }

    // Enable dev tools in debug mode
    #[cfg(debug_assertions)]
    webview.open_devtools();

    // Setup menu event handlers.
    let zoom_level = Arc::new(Mutex::new(1.0_f64));
    let content_for_menu = content_webview.clone();
    let zoom_for_menu = zoom_level.clone();
    webview.on_menu_event(move |_webview, event| {
        let content_webview = content_for_menu.clone();
        let zoom_level = zoom_for_menu.clone();
        tauri::async_runtime::spawn(async move {
            let id = event.id().as_ref();
            if id == "new_tab" {
                println!("New tab requested");
            } else if id == "new_window" {
                println!("New window requested");
            } else if id == "settings" {
                println!("Settings requested");
            } else if id == "zoomin" || id == "zoomout" || id == "resetzoom" {
                let mut level = zoom_level.lock().unwrap_or_else(|e| e.into_inner());
                match id {
                    "zoomin" => *level = (*level + 0.1).min(5.0),
                    "zoomout" => *level = (*level - 0.1).max(0.2),
                    _ => *level = 1.0,
                }
                if let Err(e) = content_webview.set_zoom(*level) {
                    eprintln!("Zoom update failed: {}", e);
                }
            } else if id == "quit" {
                std::process::exit(0);
            }
        });
    });

    Ok(())
}

fn main() {
    // Install a panic hook to capture early panics to our log file
    std::panic::set_hook(Box::new(|info| {
        let msg = if let Some(s) = info.payload().downcast_ref::<&str>() {
            *s
        } else if let Some(s) = info.payload().downcast_ref::<String>() {
            s.as_str()
        } else {
            "panic occurred"
        };
        let location = info
            .location()
            .map(|l| format!("{}:{}", l.file(), l.line()))
            .unwrap_or_else(|| "unknown:0".into());
        log_startup(&format!("panic: {} @ {}", msg, location));
    }));

    log_startup("main: starting tauri builder");
    let approval_broker = ApprovalBroker::new();
    let mcp_config = Arc::new(match McpConfigService::load() {
        Ok(service) => service,
        Err(err) => {
            log_startup(&format!("failed to load MCP profiles: {err}"));
            match McpConfigService::reset() {
                Ok(service) => service,
                Err(reset_err) => {
                    log_startup(&format!("failed to reset MCP profiles: {reset_err}"));
                    McpConfigService::load().expect("reinitialised MCP profiles")
                }
            }
        }
    });
    let mcp_registry = Arc::new(
        match McpServerRegistry::from_config_service(mcp_config.clone()) {
            Ok(registry) => registry,
            Err(err) => {
                log_startup(&format!("failed to load MCP manifest: {err}"));
                McpServerRegistry::empty(mcp_config.clone())
            }
        },
    );
    let agent_apps = Arc::new(match AgentAppRegistry::load_default() {
        Ok(registry) => registry,
        Err(err) => {
            log_startup(&format!("failed to load agent apps: {err}"));
            AgentAppRegistry::empty()
        }
    });
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState {
            current_url: Mutex::new("about:home".to_string()),
            browser_engine: Arc::new(BrowserEngine::new()),
            protocol_handler: Arc::new(Mutex::new(ProtocolHandler::new())),
            security_manager: Arc::new(Mutex::new(SecurityManager::new())),
            telemetry_manager: Arc::new(Mutex::new(TelemetryManager::new())),
            wallet_store: Arc::new(Mutex::new(WalletStore::new().unwrap_or_else(|_| WalletStore::default()))),
            agent_manager: Arc::new(AsyncMutex::new(None)),
            approval_broker: approval_broker.clone(),
            afm_node_controller: Arc::new(AsyncMutex::new(None)),
            afm_node_handle: Arc::new(Mutex::new(None)),
            afm_node_config: Arc::new(Mutex::new(AfmNodeConfig::default())),
            mcp_registry: mcp_registry.clone(),
            mcp_config: mcp_config.clone(),
            agent_apps: agent_apps.clone(),
        })
        .setup(|app| {
            log_startup("setup: entered");
            create_browser_window(app.app_handle(), None)?;

            if let Some(state) = app.app_handle().try_state::<AppState>() {
                if let Err(err) = apply_persisted_settings(&state) {
                    log_startup(&format!("failed to apply persisted settings: {err}"));
                }
            }

            if let Some(state) = app.app_handle().try_state::<AppState>() {
                let agent_mutex = state.agent_manager.clone();
                let app_handle = app.app_handle().clone();
                match AgentManager::new(app_handle, &*state, state.approval_broker.clone()) {
                    Ok(manager) => {
                        tauri::async_runtime::block_on(async move {
                            let mut slot = agent_mutex.lock().await;
                            *slot = Some(manager);
                        });
                    }
                    Err(err) => {
                        log_startup(&format!("agent initialisation failed: {err}"));
                    }
                }
            }

            if let Some(state) = app.app_handle().try_state::<AppState>() {
                let telemetry = state.telemetry_manager.clone();
                let app_handle = app.app_handle().clone();

                std::thread::spawn(move || {
                    if let Ok(manager) = telemetry.lock() {
                        let result = tauri::async_runtime::block_on(manager.check_for_updates());
                        let update_payload = manager
                            .update_info
                            .lock()
                            .ok()
                            .and_then(|info| info.clone());
                        drop(manager);

                        if let Err(err) = result {
                            log_startup(&format!("initial update check failed: {err}"));
                        }

                        if let Some(info) = update_payload {
                            if let Err(err) = app_handle.emit("update-status", info) {
                                log_startup(&format!("failed to emit update-status event: {err}"));
                            }
                        }
                    }
                });
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            agent_list_tools,
            agent_run_task,
            list_agent_apps,
            launch_agent_app,
            agent_list_skills,
            agent_get_credits,
            agent_top_up_credits,
            agent_set_no_egress,
            agent_resolve_approval,
            navigate_to,
            set_content_bounds,
            get_current_url,
            // Settings
            get_settings,
            update_settings,
            list_mcp_servers,
            save_mcp_servers,
            test_mcp_server,
            list_mcp_profiles,
            set_active_mcp_profile,
            create_mcp_profile,
            import_mcp_profile,
            export_mcp_profile,
            read_mcp_secret,
            create_tab,
            close_tab,
            switch_tab,
            get_tabs,
            add_bookmark,
            get_bookmarks,
            remove_bookmark,
            get_history,
            clear_history,
            resolve_protocol_url,
            update_security_settings,
            get_security_status,
            report_error,
            track_usage,
            record_performance,
            get_error_summary,
            get_performance_summary,
            add_security_alert,
            check_for_updates,
            apply_update,
            export_telemetry,
            set_telemetry_enabled,
            // Wallet
            get_wallet_info,
            connect_wallet,
            disconnect_wallet,
            get_agent_wallet,
            set_agent_wallet_policy,
            evaluate_agent_spend,
            // AFM node controls
            start_afm_node,
            stop_afm_node,
            afm_node_status,
            afm_submit_task,
            afm_feed_gossip
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[tauri::command]
async fn agent_list_tools<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<Vec<McpToolDescription>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let guard = agent_mutex.lock().await;
    let manager = guard
        .as_ref()
        .ok_or_else(|| "agent manager not initialised".to_string())?;
    manager
        .tool_descriptions()
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
async fn agent_run_task<R: Runtime>(
    request: AgentRunRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<AgentRunResponse, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let mut guard = agent_mutex.lock().await;
    let manager = guard
        .as_mut()
        .ok_or_else(|| "agent manager not initialised".to_string())?;

    manager
        .run_task(request)
        .await
        .map_err(|err| err.to_string())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LaunchAgentAppRequest {
    app_id: String,
    #[serde(default)]
    input: Option<String>,
}

#[tauri::command]
async fn list_agent_apps<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<Vec<AgentAppSummary>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    Ok(state.agent_apps.list())
}

#[tauri::command]
async fn launch_agent_app<R: Runtime>(
    request: LaunchAgentAppRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<AgentRunResponse, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_apps = state.agent_apps.clone();
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let app = agent_apps
        .find(&request.app_id)
        .ok_or_else(|| format!("agent app `{}` not found", request.app_id))?;
    let task = app.render_task(request.input.as_deref());

    let mut guard = agent_mutex.lock().await;
    let manager = guard
        .as_mut()
        .ok_or_else(|| "agent manager not initialised".to_string())?;

    manager
        .run_task(AgentRunRequest {
            task,
            skill_id: app.skill_id.clone(),
            no_egress: app.no_egress,
        })
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
async fn agent_list_skills<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<Vec<AgentSkillSummary>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let guard = agent_mutex.lock().await;
    let manager = guard
        .as_ref()
        .ok_or_else(|| "agent manager not initialised".to_string())?;

    Ok(manager.list_skills())
}

#[tauri::command]
async fn agent_get_credits<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<CreditSnapshot, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let guard = agent_mutex.lock().await;
    let manager = guard
        .as_ref()
        .ok_or_else(|| "agent manager not initialised".to_string())?;

    Ok(manager.credit_snapshot().await)
}

#[tauri::command]
async fn agent_top_up_credits<R: Runtime>(
    tokens: u32,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<CreditSnapshot, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let guard = agent_mutex.lock().await;
    let manager = guard
        .as_ref()
        .ok_or_else(|| "agent manager not initialised".to_string())?;

    Ok(manager.top_up_credits(tokens).await)
}

#[tauri::command]
async fn agent_set_no_egress<R: Runtime>(
    enabled: bool,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let guard = agent_mutex.lock().await;
    let manager = guard
        .as_ref()
        .ok_or_else(|| "agent manager not initialised".to_string())?;

    manager.set_no_egress(enabled);
    Ok(())
}

#[tauri::command]
async fn agent_resolve_approval<R: Runtime>(
    request_id: String,
    approved: bool,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    state
        .approval_broker
        .resolve(&request_id, approved)
        .await
        .map_err(|err| err.to_string())
}

// Tauri command to navigate to a URL
#[tauri::command]
async fn navigate_to<R: Runtime>(
    url: String,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    // Update the URL in app state
    if let Some(state) = app_handle.try_state::<AppState>() {
        if let Ok(mut current_url) = state.current_url.lock() {
            *current_url = url.clone();
        }
    }

    // Internal pages are rendered by the main UI; do not navigate the content webview.
    if url.trim_start().to_ascii_lowercase().starts_with("about:") {
        return Ok(());
    }

    let content_webview = app_handle
        .get_webview(CONTENT_WEBVIEW_LABEL)
        .ok_or_else(|| "Content webview not found".to_string())?;

    let target = url::Url::parse(url.trim())
        .or_else(|_| url::Url::parse(&format!("https://{}", url.trim())))
        .map_err(|e| format!("Invalid URL: {e}"))?;

    content_webview
        .navigate(target)
        .map_err(|e| format!("Failed to navigate: {}", e))?;

    Ok(())
}

#[derive(Debug, Deserialize)]
struct ContentBounds {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

// Tauri command to position and show/hide the content webview.
//
// The main UI measures its "content host" DOM rect and sends it here so we can
// align the native child webview with the React layout.
#[tauri::command]
async fn set_content_bounds<R: Runtime>(
    bounds: Option<ContentBounds>,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    use tauri::{LogicalPosition, LogicalSize, Position, Rect, Size};

    let content_webview = app_handle
        .get_webview(CONTENT_WEBVIEW_LABEL)
        .ok_or_else(|| "Content webview not found".to_string())?;

    match bounds {
        Some(bounds) if bounds.width > 1.0 && bounds.height > 1.0 => {
            let rect = Rect {
                position: Position::Logical(LogicalPosition::new(bounds.x, bounds.y)),
                size: Size::Logical(LogicalSize::new(bounds.width, bounds.height)),
            };

            content_webview
                .set_bounds(rect)
                .map_err(|e| format!("Failed to set content bounds: {e}"))?;
            content_webview
                .show()
                .map_err(|e| format!("Failed to show content webview: {e}"))?;
        }
        _ => {
            content_webview
                .hide()
                .map_err(|e| format!("Failed to hide content webview: {e}"))?;
        }
    }

    Ok(())
}

// Tauri command to get the current URL
#[tauri::command]
async fn get_current_url<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<String, String> {
    if let Some(state) = app_handle.try_state::<AppState>() {
        if let Ok(current_url) = state.current_url.lock() {
            return Ok(current_url.clone());
        }
    }
    Ok("about:home".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use afm_node::AfmNodeConfig;
    use gui::agent::McpServerRegistry;
    use gui::agent_apps::AgentAppRegistry;
    use gui::mcp_profiles::McpConfigService;
    use gui::wallet_store::WalletStore;

    #[test]
    fn test_app_state() {
        let mcp_config = Arc::new(
            McpConfigService::load().unwrap_or_else(|_| McpConfigService::reset().unwrap()),
        );
        let state = AppState {
            current_url: Mutex::new("https://example.com".to_string()),
            browser_engine: Arc::new(BrowserEngine::new()),
            protocol_handler: Arc::new(Mutex::new(ProtocolHandler::new())),
            security_manager: Arc::new(Mutex::new(SecurityManager::new())),
            telemetry_manager: Arc::new(Mutex::new(TelemetryManager::new())),
            wallet_store: Arc::new(Mutex::new(WalletStore::new().unwrap_or_else(|_| WalletStore::default()))),
            agent_manager: Arc::new(AsyncMutex::new(None)),
            approval_broker: ApprovalBroker::new(),
            afm_node_controller: Arc::new(AsyncMutex::new(None)),
            afm_node_handle: Arc::new(Mutex::new(None)),
            afm_node_config: Arc::new(Mutex::new(AfmNodeConfig::default())),
            mcp_registry: Arc::new(
                McpServerRegistry::from_config_service(mcp_config.clone())
                    .unwrap_or_else(|_| McpServerRegistry::empty(mcp_config.clone())),
            ),
            mcp_config,
            agent_apps: Arc::new(AgentAppRegistry::empty()),
        };

        let url = state.current_url.lock().unwrap();
        assert_eq!(*url, "https://example.com");
    }
}
