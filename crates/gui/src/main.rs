#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

use std::sync::{Arc, Mutex};
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use tauri::{
    menu::{IsMenuItem, Menu, MenuItem, Submenu},
    Runtime, WebviewWindowBuilder,
};
use tauri::Manager; // bring Manager trait into scope
use tauri_plugin_dialog;

// Use the library crate modules
use gui::browser_engine::BrowserEngine;
use gui::protocol_handlers::ProtocolHandler;
use gui::security::SecurityManager;
use gui::telemetry::TelemetryManager;
use gui::commands::*;
use gui::telemetry_commands::*;
use gui::app_state::AppState;

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
    let select_all = MenuItem::with_id(manager, "select_all", "Select All", true, Some("CmdOrCtrl+A"))?;
    
    let edit_menu = Submenu::with_items(
        manager,
        "Edit",
        true,
        &[
            &cut as &dyn IsMenuItem<R>,
            &copy,
            &paste,
            &select_all,
        ],
    )?;

    // Create view menu
    let zoom_in = MenuItem::with_id(manager, "zoomin", "Zoom In", true, Some("CmdOrCtrl+Plus"))?;
    let zoom_out = MenuItem::with_id(manager, "zoomout", "Zoom Out", true, Some("CmdOrCtrl+-"))?;
    let reset_zoom = MenuItem::with_id(manager, "resetzoom", "Reset Zoom", true, Some("CmdOrCtrl+0"))?;
    
    let view_menu = Submenu::with_items(
        manager,
        "View",
        true,
        &[
            &zoom_in as &dyn IsMenuItem<R>,
            &zoom_out,
            &reset_zoom,
        ],
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

    let webview = WebviewWindowBuilder::new(
        app,
        "main",
        tauri::WebviewUrl::App("index.html".into()),
    )
    .title("Decentralized Browser")
    .inner_size(1200.0, 800.0)
    .min_inner_size(800.0, 600.0)
    .menu(menu)
    .build()?;
    log_startup("create_browser_window: webview built");

    // Store the initial URL in the app state
    if let Some(state) = app.try_state::<AppState>() {
        if let Ok(mut current_url) = state.current_url.lock() {
            *current_url = initial_url.to_string();
        }
    }

    // Enable dev tools in debug mode
    #[cfg(debug_assertions)]
    webview.open_devtools();
    
    // Setup menu event handlers
    let webview_ = webview.clone();
    webview.on_menu_event(move |_webview, event| {
        let webview = webview_.clone();
        tauri::async_runtime::spawn(async move {
            let id = event.id().as_ref();
            if id == "new_tab" {
                println!("New tab requested");
            } else if id == "new_window" {
                println!("New window requested");
            } else if id == "settings" {
                println!("Settings requested");
            } else if id == "zoomin" {
                if let Err(e) = webview.eval("document.getElementById('webview').setZoomLevel(0.5);") {
                    eprintln!("Zoom in failed: {}", e);
                }
            } else if id == "zoomout" {
                if let Err(e) = webview.eval("document.getElementById('webview').setZoomLevel(-0.5);") {
                    eprintln!("Zoom out failed: {}", e);
                }
            } else if id == "resetzoom" {
                if let Err(e) = webview.eval("document.getElementById('webview').setZoomLevel(0);") {
                    eprintln!("Reset zoom failed: {}", e);
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
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState {
            current_url: Mutex::new("about:home".to_string()),
            browser_engine: Arc::new(BrowserEngine::new()),
            protocol_handler: Arc::new(Mutex::new(ProtocolHandler::new())),
            security_manager: Arc::new(Mutex::new(SecurityManager::new())),
            telemetry_manager: Arc::new(Mutex::new(TelemetryManager::new())),
        })
        .setup(|app| {
            log_startup("setup: entered");
            create_browser_window(app.app_handle(), None)?;
            
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            navigate_to,
            get_current_url,
            execute_script,
            // Settings
            get_settings,
            update_settings,
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
            export_telemetry,
            set_telemetry_enabled
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

// Tauri command to navigate to a URL
#[tauri::command]
async fn navigate_to<R: Runtime>(
    url: String,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let webview = match app_handle.get_webview_window("main") {
        Some(webview) => webview,
        None => return Err("Webview not found".to_string()),
    };
    
    // Update the URL in app state
    if let Some(state) = app_handle.try_state::<AppState>() {
        if let Ok(mut current_url) = state.current_url.lock() {
            *current_url = url.clone();
        }
    }
    
    // Execute navigation in the webview
    // The React UI may render certain about:* pages natively and not include the iframe.
    // Guard against missing element to avoid console errors.
    let script = format!(
        "(function() {{ var el = document.getElementById('webview'); if (el) {{ el.src = '{}'; }} }})();",
        url
    );
    if let Err(e) = webview.eval(&script) {
        return Err(format!("Failed to navigate: {}", e));
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

// Tauri command to execute JavaScript in the webview
#[tauri::command]
async fn execute_script<R: Runtime>(
    script: String,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let webview = match app_handle.get_webview_window("main") {
        Some(webview) => webview,
        None => return Err("Webview not found".to_string()),
    };
    
    if let Err(e) = webview.eval(&script) {
        return Err(format!("Failed to execute script: {}", e));
    }
    
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_app_state() {
        let state = AppState {
            current_url: Mutex::new("https://example.com".to_string()),
            browser_engine: Arc::new(BrowserEngine::new()),
            protocol_handler: Arc::new(Mutex::new(ProtocolHandler::new())),
            security_manager: Arc::new(Mutex::new(SecurityManager::new())),
            telemetry_manager: Arc::new(Mutex::new(TelemetryManager::new())),
        };
        
        let url = state.current_url.lock().unwrap();
        assert_eq!(*url, "https://example.com");
    }
}
