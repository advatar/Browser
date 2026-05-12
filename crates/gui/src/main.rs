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
use std::time::{Duration, SystemTime, UNIX_EPOCH};
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
    AgentManager, AgentRunRequest, AgentRunResponse, AgentRunSummary, AgentSkillSummary,
    ApprovalBroker, CreditSnapshot, McpServerRegistry,
};
use gui::agent_app_schedules::{
    AgentAppScheduleDraft, AgentAppScheduleRegistry, AgentAppScheduleSummary,
};
use gui::agent_apps::{AgentAppRegistry, AgentAppSummary};
use gui::app_state::{AppState, ContentWebviewBounds};
use gui::browser_engine::BrowserEngine;
use gui::commands::*;
use gui::mcp_profiles::McpConfigService;
use gui::protocol_handlers::ProtocolHandler;
use gui::security::SecurityManager;
use gui::telemetry::TelemetryManager;
use gui::telemetry_commands::*;
use gui::wallet_store::WalletStore;

const MAIN_WEBVIEW_LABEL: &str = "main";
const CONTENT_WEBVIEW_PREFIX: &str = "content-tab-";

fn runtime_logging_enabled() -> bool {
    if cfg!(debug_assertions) {
        return true;
    }

    matches!(
        std::env::var("BROWSER_DEBUG_LOG"),
        Ok(value)
            if matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            )
    )
}

fn application_logs_dir() -> PathBuf {
    if let Some(home) = std::env::var_os("HOME") {
        if cfg!(target_os = "macos") {
            return PathBuf::from(home)
                .join("Library")
                .join("Logs")
                .join("DecentralizedBrowser");
        }

        if let Some(xdg_state) = std::env::var_os("XDG_STATE_HOME") {
            return PathBuf::from(xdg_state)
                .join("decentralized-browser")
                .join("logs");
        }

        return PathBuf::from(home)
            .join(".local")
            .join("state")
            .join("decentralized-browser")
            .join("logs");
    }

    if let Some(app_data) = std::env::var_os("LOCALAPPDATA").or_else(|| std::env::var_os("APPDATA"))
    {
        return PathBuf::from(app_data)
            .join("DecentralizedBrowser")
            .join("Logs");
    }

    PathBuf::from(".")
        .join(".decentralized-browser")
        .join("logs")
}

fn log_path() -> PathBuf {
    let mut base = application_logs_dir();
    let _ = create_dir_all(&base);
    base.push("gui.log");
    base
}

fn log_startup(msg: &str) {
    if !runtime_logging_enabled() {
        return;
    }
    let path = log_path();
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(file, "{} | {}", chrono_like_timestamp(), msg);
    }
}

fn log_command(cmd: &str, details: &str) {
    let compact = details.split_whitespace().collect::<Vec<_>>().join(" ");
    let truncated = if compact.len() > 240 {
        format!("{}...", &compact[..240])
    } else {
        compact
    };
    log_startup(&format!("{} | {}", cmd, truncated));
}

fn protocol_response(
    status: tauri::http::StatusCode,
    content_type: &str,
    body: Vec<u8>,
) -> tauri::http::Response<Vec<u8>> {
    tauri::http::Response::builder()
        .status(status)
        .header(tauri::http::header::CONTENT_TYPE, content_type)
        .header(tauri::http::header::CACHE_CONTROL, "no-store")
        .body(body)
        .expect("valid protocol response")
}

fn protocol_response_with_security_headers<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
    status: tauri::http::StatusCode,
    content_type: &str,
    body: Vec<u8>,
) -> tauri::http::Response<Vec<u8>> {
    let mut builder = tauri::http::Response::builder()
        .status(status)
        .header(tauri::http::header::CONTENT_TYPE, content_type)
        .header(tauri::http::header::CACHE_CONTROL, "no-store");

    if let Some(state) = app_handle.try_state::<AppState>() {
        if let Ok(security_manager) = state.security_manager.lock() {
            for (name, value) in security_manager.get_privacy_headers() {
                builder = builder.header(name, value);
            }
        }
    }

    builder.body(body).expect("valid protocol response")
}

fn protocol_error_response(
    status: tauri::http::StatusCode,
    message: impl Into<String>,
) -> tauri::http::Response<Vec<u8>> {
    protocol_response(
        status,
        "text/plain; charset=utf-8",
        message.into().into_bytes(),
    )
}

async fn build_decentralized_protocol_response<R: Runtime>(
    app_handle: tauri::AppHandle<R>,
    request_url: String,
    fallback_scheme: &'static str,
    head_only: bool,
) -> tauri::http::Response<Vec<u8>> {
    let handler = match app_handle.try_state::<AppState>() {
        Some(state) => match state.protocol_handler.lock() {
            Ok(handler) => handler.clone(),
            Err(_) => {
                return protocol_error_response(
                    tauri::http::StatusCode::INTERNAL_SERVER_ERROR,
                    "protocol handler unavailable",
                );
            }
        },
        None => {
            return protocol_error_response(
                tauri::http::StatusCode::INTERNAL_SERVER_ERROR,
                "application state unavailable",
            );
        }
    };

    match handler
        .load_custom_protocol_url(&request_url, fallback_scheme)
        .await
    {
        Ok(content) => {
            let body = if head_only { Vec::new() } else { content.data };
            protocol_response_with_security_headers(
                &app_handle,
                tauri::http::StatusCode::OK,
                &content.content_type,
                body,
            )
        }
        Err(err) => {
            log_startup(&format!(
                "custom protocol resolve failed scheme={fallback_scheme} url={request_url} error={err}"
            ));
            protocol_error_response(
                tauri::http::StatusCode::NOT_FOUND,
                format!("Failed to resolve {request_url}: {err}"),
            )
        }
    }
}

fn register_decentralized_protocols<R: Runtime>(builder: tauri::Builder<R>) -> tauri::Builder<R> {
    builder
        .register_asynchronous_uri_scheme_protocol("ipfs", |ctx, request, responder| {
            let app_handle = ctx.app_handle().clone();
            let request_url = request.uri().to_string();
            let head_only = request.method() == tauri::http::Method::HEAD;
            tauri::async_runtime::spawn(async move {
                responder.respond(
                    build_decentralized_protocol_response(
                        app_handle,
                        request_url,
                        "ipfs",
                        head_only,
                    )
                    .await,
                );
            });
        })
        .register_asynchronous_uri_scheme_protocol("ipns", |ctx, request, responder| {
            let app_handle = ctx.app_handle().clone();
            let request_url = request.uri().to_string();
            let head_only = request.method() == tauri::http::Method::HEAD;
            tauri::async_runtime::spawn(async move {
                responder.respond(
                    build_decentralized_protocol_response(
                        app_handle,
                        request_url,
                        "ipns",
                        head_only,
                    )
                    .await,
                );
            });
        })
}

fn chrono_like_timestamp() -> String {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(dur) => format!("{}.{:03}", dur.as_secs(), dur.subsec_millis()),
        Err(_) => "0".to_string(),
    }
}

fn unix_time_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn is_internal_url(url: &str) -> bool {
    url.trim_start().to_ascii_lowercase().starts_with("about:")
}

fn parse_external_url(url: &str) -> Result<url::Url, String> {
    url::Url::parse(url.trim())
        .or_else(|_| url::Url::parse(&format!("https://{}", url.trim())))
        .map_err(|e| format!("Invalid URL: {e}"))
}

fn ensure_browser_engine_tab(
    state: &AppState,
    tab_id: &str,
    url: &str,
    active: bool,
) -> Result<(), String> {
    state
        .browser_engine
        .ensure_tab(tab_id, url)
        .map_err(|err| err.to_string())?;
    if active {
        state
            .browser_engine
            .set_active_tab_id(Some(tab_id.to_string()))
            .map_err(|err| err.to_string())?;
    }
    Ok(())
}

fn validate_runtime_navigation<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
    url: &str,
) -> Result<(), String> {
    if is_internal_url(url) {
        return Ok(());
    }

    let candidate = match url::Url::parse(url.trim()) {
        Ok(parsed) => parsed,
        Err(_) => parse_external_url(url)?,
    };

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let security_manager = state.security_manager.lock().map_err(|e| e.to_string())?;
    let allowed = security_manager
        .validate_url_security(candidate.as_str())
        .map_err(|e| e.to_string())?;
    if allowed {
        Ok(())
    } else {
        Err(format!(
            "navigation blocked by security policy: {}",
            candidate.as_str()
        ))
    }
}

fn emit_blocked_navigation<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
    tab_id: Option<&str>,
    url: &str,
    reason: &str,
) {
    let _ = emit_navigation_blocked(
        app_handle,
        &NavigationBlockedEvent {
            tab_id: tab_id.map(str::to_string),
            url: url.to_string(),
            reason: reason.to_string(),
        },
    );
    log_command(
        "navigation_blocked",
        &format!(
            "tab_id={} url={} reason={reason}",
            tab_id.unwrap_or("<none>"),
            url
        ),
    );
}

fn emit_runtime_tab_state<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
    tab_id: &str,
    url: Option<&str>,
    title: Option<&str>,
    loading: Option<bool>,
) {
    let _ = emit_tab_state_updated(
        app_handle,
        &TabStateUpdate {
            tab_id: tab_id.to_string(),
            url: url.map(str::to_string),
            title: title.map(str::to_string),
            loading,
        },
    );
}

fn sync_runtime_tab_event<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
    tab_id: &str,
    url: &str,
    loading: bool,
    record_history: bool,
) -> Result<(), String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    ensure_browser_engine_tab(&state, tab_id, url, true)?;
    state
        .browser_engine
        .update_tab(tab_id, None, Some(url.to_string()), Some(loading))
        .map_err(|err| err.to_string())?;

    if let Ok(mut current_url) = state.current_url.lock() {
        *current_url = url.to_string();
    }

    if record_history && !is_internal_url(url) {
        state
            .browser_engine
            .add_to_history(url.to_string(), url.to_string())
            .map_err(|err| err.to_string())?;
        emit_history_updated(app_handle, &state)?;
    }

    emit_runtime_tab_state(app_handle, tab_id, Some(url), None, Some(loading));
    Ok(())
}

fn spawn_agent_app_scheduler<R: Runtime>(app_handle: tauri::AppHandle<R>) {
    tauri::async_runtime::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(30));
        loop {
            interval.tick().await;

            let (apps, schedules) = match app_handle.try_state::<AppState>() {
                Some(state) => (state.agent_apps.clone(), state.agent_app_schedules.clone()),
                None => continue,
            };

            let due_schedules = match schedules.claim_due(unix_time_ms()) {
                Ok(schedules) => schedules,
                Err(err) => {
                    log_startup(&format!("agent app scheduler claim failed: {err}"));
                    continue;
                }
            };

            if due_schedules.is_empty() {
                continue;
            }

            for schedule in due_schedules {
                let app = match apps.find(&schedule.app_id) {
                    Some(app) => app,
                    None => {
                        let _ = schedules.record_run_result(&schedule.id, "missing_app");
                        log_startup(&format!(
                            "agent app scheduler missing app id={} schedule={}",
                            schedule.app_id, schedule.id
                        ));
                        continue;
                    }
                };

                let manager = match get_agent_manager(&app_handle).await {
                    Ok(manager) => manager,
                    Err(err) => {
                        let _ = schedules.record_run_result(&schedule.id, "manager_unavailable");
                        log_startup(&format!(
                            "agent app scheduler unavailable schedule={} error={err}",
                            schedule.id
                        ));
                        continue;
                    }
                };

                let schedules = schedules.clone();
                tauri::async_runtime::spawn(async move {
                    let outcome = manager
                        .run_task(AgentRunRequest {
                            task: app.render_task(schedule.input.as_deref()),
                            skill_id: app.skill_id.clone(),
                            no_egress: app.no_egress,
                            label: Some(schedule.label.clone()),
                            app_id: Some(app.id.clone()),
                            schedule_id: Some(schedule.id.clone()),
                        })
                        .await;

                    let status = match outcome {
                        Ok(response) if response.cancelled => "cancelled",
                        Ok(_) => "completed",
                        Err(_) => "failed",
                    };
                    let _ = schedules.record_run_result(&schedule.id, status);
                });
            }
        }
    });
}

fn tab_webview_label(tab_id: &str) -> String {
    let sanitized = tab_id
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect::<String>();
    format!("{CONTENT_WEBVIEW_PREFIX}{sanitized}")
}

fn read_tab_label(state: &AppState, tab_id: &str) -> Result<Option<String>, String> {
    state
        .content_tab_webviews
        .lock()
        .map_err(|_| "content webview map mutex poisoned".to_string())
        .map(|map| map.get(tab_id).cloned())
}

fn active_tab_id(state: &AppState) -> Result<Option<String>, String> {
    state
        .active_content_tab
        .lock()
        .map_err(|_| "active tab mutex poisoned".to_string())
        .map(|active| active.clone())
}

fn ensure_tab_webview<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
    tab_id: &str,
    initial_url: Option<&str>,
) -> Result<tauri::webview::Webview<R>, String> {
    log_command(
        "ensure_tab_webview",
        &format!(
            "tab_id={} initial_url={}",
            tab_id,
            initial_url.unwrap_or("<none>")
        ),
    );

    use tauri::webview::{PageLoadEvent, WebviewBuilder};
    use tauri::{LogicalPosition, LogicalSize};

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    let initial_browser_url = initial_url.unwrap_or("about:blank");
    ensure_browser_engine_tab(&state, tab_id, initial_browser_url, false)?;

    let existing_label = read_tab_label(&state, tab_id)?;
    if let Some(existing_label) = &existing_label {
        if let Some(existing) = app_handle.get_webview(existing_label) {
            log_command(
                "ensure_tab_webview",
                &format!("reuse existing_label={existing_label}"),
            );
            return Ok(existing);
        }
        log_command(
            "ensure_tab_webview",
            &format!("stale label cache existing_label={existing_label}"),
        );
    }

    let label = existing_label.unwrap_or_else(|| tab_webview_label(tab_id));
    if let Some(existing) = app_handle.get_webview(&label) {
        log_command(
            "ensure_tab_webview",
            &format!("reuse existing label={label} (stale cache path)"),
        );
        if let Ok(mut map) = state.content_tab_webviews.lock() {
            map.insert(tab_id.to_string(), label.clone());
        }
        return Ok(existing);
    }

    log_command(
        "ensure_tab_webview",
        &format!("creating child label={label} tab_id={tab_id}"),
    );

    let initial_webview_url = if let Some(url) = initial_url {
        validate_runtime_navigation(app_handle, url)?;
        if is_internal_url(url) {
            tauri::WebviewUrl::External(
                url::Url::parse("about:blank")
                    .map_err(|e| format!("Failed to parse about:blank URL: {e}"))?,
            )
        } else {
            tauri::WebviewUrl::External(parse_external_url(url)?)
        }
    } else {
        tauri::WebviewUrl::External(
            url::Url::parse("about:blank")
                .map_err(|e| format!("Failed to parse about:blank URL: {e}"))?,
        )
    };

    let window = app_handle
        .get_webview_window(MAIN_WEBVIEW_LABEL)
        .or_else(|| {
            log_command(
                "ensure_tab_webview",
                "main window label missing; using first managed webview window",
            );
            app_handle
                .webview_windows()
                .into_iter()
                .next()
                .map(|(_, fallback_window)| fallback_window)
        })
        .ok_or_else(|| "Main webview window not found".to_string())?
        .as_ref()
        .window();

    let label_for_navigation = label.clone();
    let label_for_page_load = label.clone();
    let app_handle_for_navigation = app_handle.clone();
    let app_handle_for_page_load = app_handle.clone();
    let tab_id_for_navigation = tab_id.to_string();
    let tab_id_for_page_load = tab_id.to_string();
    let builder = WebviewBuilder::new(&label, initial_webview_url)
        .on_navigation(move |url| {
            let candidate = url.as_str();
            match validate_runtime_navigation(&app_handle_for_navigation, candidate) {
                Ok(()) => {
                    log_command(
                        "content_tab_navigation",
                        &format!("label={label_for_navigation} allowed url={candidate}"),
                    );
                    true
                }
                Err(reason) => {
                    emit_blocked_navigation(
                        &app_handle_for_navigation,
                        Some(&tab_id_for_navigation),
                        candidate,
                        &reason,
                    );
                    false
                }
            }
        })
        .on_page_load(move |_webview, payload| {
            let event_name = match payload.event() {
                PageLoadEvent::Started => "started",
                PageLoadEvent::Finished => "finished",
            };
            log_command(
                "content_tab_page_load",
                &format!(
                    "label={label_for_page_load} event={event_name} url={}",
                    payload.url()
                ),
            );

            let url = payload.url();
            let update = match payload.event() {
                PageLoadEvent::Started => sync_runtime_tab_event(
                    &app_handle_for_page_load,
                    &tab_id_for_page_load,
                    url.as_str(),
                    true,
                    false,
                ),
                PageLoadEvent::Finished => sync_runtime_tab_event(
                    &app_handle_for_page_load,
                    &tab_id_for_page_load,
                    url.as_str(),
                    false,
                    true,
                ),
            };

            if let Err(err) = update {
                log_command(
                    "content_tab_page_load",
                    &format!(
                        "label={label_for_page_load} failed to sync tab state event={event_name} err={err}"
                    ),
                );
            }
        });

    let child = match window.add_child(
        builder,
        LogicalPosition::new(0.0, 0.0),
        LogicalSize::new(0.0, 0.0),
    ) {
        Ok(child) => child,
        Err(err) => {
            let err = format!("Failed to create tab webview: {err}");
            log_command(
                "ensure_tab_webview",
                &format!("create failed label={label} {err}"),
            );

            if let Some(existing) = app_handle.get_webview(&label) {
                log_command(
                    "ensure_tab_webview",
                    &format!("create raced with existing label={label}, reusing"),
                );
                if let Ok(mut map) = state.content_tab_webviews.lock() {
                    map.insert(tab_id.to_string(), label.clone());
                }
                return Ok(existing);
            }

            Err(err)?
        }
    };

    let _ = child.hide();
    log_command(
        "ensure_tab_webview",
        &format!("created hidden child label={label}"),
    );

    if let Ok(mut map) = state.content_tab_webviews.lock() {
        map.insert(tab_id.to_string(), label);
    } else {
        log_command(
            "ensure_tab_webview",
            &format!("failed to cache label for tab_id={tab_id} due poisoned map mutex"),
        );
    }

    Ok(child)
}

fn active_tab_webview<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
) -> Result<Option<tauri::webview::Webview<R>>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    let Some(active_tab_id) = active_tab_id(&state)? else {
        return Ok(None);
    };

    let Some(label) = read_tab_label(&state, &active_tab_id)? else {
        return Ok(None);
    };

    Ok(app_handle.get_webview(&label))
}

fn normalize_content_bounds(bounds: ContentWebviewBounds) -> ContentWebviewBounds {
    const CONTENT_WEBVIEW_Y_OFFSET: f64 = 0.0;
    let width = if bounds.width.is_finite() && bounds.width >= 0.0 {
        bounds.width.round().max(0.0)
    } else {
        0.0
    };
    let height = if bounds.height.is_finite() && bounds.height >= 0.0 {
        bounds.height.round().max(0.0)
    } else {
        0.0
    };

    let x = if bounds.x.is_finite() {
        bounds.x.round()
    } else {
        0.0
    };

    let y = if bounds.y.is_finite() {
        (bounds.y + CONTENT_WEBVIEW_Y_OFFSET).round()
    } else {
        CONTENT_WEBVIEW_Y_OFFSET
    };

    ContentWebviewBounds {
        x,
        y,
        width,
        height,
    }
}

fn apply_bounds_to_active_webview<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
) -> Result<(), String> {
    use tauri::{LogicalPosition, LogicalSize, Position, Rect, Size};

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    let Some(active_tab_id) = active_tab_id(&state)? else {
        log_command("apply_bounds_to_active_webview", "no active tab");
        return Ok(());
    };
    let Some(label) = read_tab_label(&state, &active_tab_id)? else {
        log_command(
            "apply_bounds_to_active_webview",
            &format!("active tab missing label tab_id={active_tab_id}"),
        );
        return Ok(());
    };
    let Some(webview) = app_handle.get_webview(&label) else {
        log_command(
            "apply_bounds_to_active_webview",
            &format!("label missing webview label={label}"),
        );
        return Ok(());
    };

    let bounds = state
        .content_bounds
        .lock()
        .map_err(|_| "content bounds mutex poisoned".to_string())?
        .as_ref()
        .map(|bounds| normalize_content_bounds(*bounds));
    let mut last_bounds_slot = state
        .last_content_bounds
        .lock()
        .map_err(|_| "content bounds mutex poisoned".to_string())?;
    let mut visible_slot = state
        .content_webview_visible
        .lock()
        .map_err(|_| "content visibility mutex poisoned".to_string())?;

    let desired_visible = matches!(bounds, Some(bounds) if bounds.is_visible());
    if !desired_visible {
        if *visible_slot {
            webview
                .hide()
                .map_err(|e| format!("Failed to hide content webview: {e}"))?;
            *visible_slot = false;
            *last_bounds_slot = None;
        }
        log_command(
            "apply_bounds_to_active_webview",
            &format!("hide tab_id={active_tab_id} label={label}"),
        );
        return Ok(());
    }

    let Some(bounds) = bounds else {
        return Err("content bounds unexpectedly unavailable while visible".to_string());
    };
    let should_set_bounds = last_bounds_slot.as_ref() != Some(&bounds);
    if should_set_bounds {
        let rect = Rect {
            position: Position::Logical(LogicalPosition::new(bounds.x, bounds.y)),
            size: Size::Logical(LogicalSize::new(bounds.width, bounds.height)),
        };
        log_command(
            "apply_bounds_to_active_webview",
            &format!(
                "set+show tab_id={active_tab_id} label={label} x={} y={} width={} height={}",
                bounds.x, bounds.y, bounds.width, bounds.height
            ),
        );
        webview.set_bounds(rect).map_err(|e| {
            let err = format!("Failed to set content bounds: {e}");
            log_command(
                "apply_bounds_to_active_webview",
                &format!("set_bounds failed tab_id={active_tab_id} label={label} {err}"),
            );
            err
        })?;
        *last_bounds_slot = Some(bounds);
    }

    if !*visible_slot {
        log_command(
            "apply_bounds_to_active_webview",
            &format!("show tab_id={active_tab_id} label={label}"),
        );
        webview.show().map_err(|e| {
            let err = format!("Failed to show content webview: {e}");
            log_command(
                "apply_bounds_to_active_webview",
                &format!("show failed tab_id={active_tab_id} label={label} {err}"),
            );
            err
        })?;
        *visible_slot = true;
    }

    if let Err(err) = webview.set_focus() {
        log_command(
            "apply_bounds_to_active_webview",
            &format!("focus failed tab_id={active_tab_id} label={label} err={err}"),
        );
    }

    Ok(())
}
fn create_browser_window<R: Runtime>(
    app: &tauri::AppHandle<R>,
    url: Option<&str>,
) -> tauri::Result<()> {
    log_startup("create_browser_window: start");
    let initial_url = url.unwrap_or("about:home");

    // Create the menu first
    let menu = create_main_menu(app)?;

    let initial_webview_url = if cfg!(debug_assertions) {
        tauri::WebviewUrl::External(
            url::Url::parse("http://localhost:5174").unwrap_or_else(|_| {
                url::Url::parse("about:blank").unwrap_or_else(|_| {
                    url::Url::parse("data:text/plain,about:blank").expect("static fallback URL")
                })
            }),
        )
    } else {
        tauri::WebviewUrl::App("index.html".into())
    };

    log_startup(&format!(
        "create_browser_window: loading {}",
        if cfg!(debug_assertions) {
            "http://localhost:5174"
        } else {
            "app index.html"
        }
    ));

    let webview = WebviewWindowBuilder::new(app, MAIN_WEBVIEW_LABEL, initial_webview_url)
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

    // Setup menu event handlers.
    let zoom_level = Arc::new(Mutex::new(1.0_f64));
    let app_handle = app.clone();
    let zoom_for_menu = zoom_level.clone();
    webview.on_menu_event(move |_webview, event| {
        let app_handle = app_handle.clone();
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

                match active_tab_webview(&app_handle) {
                    Ok(Some(webview)) => {
                        if let Err(e) = webview.set_zoom(*level) {
                            eprintln!("Zoom update failed: {}", e);
                        }
                    }
                    Ok(None) => {}
                    Err(err) => {
                        eprintln!("Failed to resolve active tab webview for zoom: {err}");
                    }
                }
            } else if id == "quit" {
                std::process::exit(0);
            }
        });
    });

    Ok(())
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
                    McpConfigService::load().unwrap_or_else(|reload_err| {
                        panic!("failed to load MCP profiles after reset attempt: {reload_err}")
                    })
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
    let agent_app_schedules = Arc::new(match AgentAppScheduleRegistry::load_default() {
        Ok(registry) => registry,
        Err(err) => {
            log_startup(&format!("failed to load agent app schedules: {err}"));
            AgentAppScheduleRegistry::empty()
        }
    });
    register_decentralized_protocols(tauri::Builder::default())
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState {
            current_url: Mutex::new("about:home".to_string()),
            content_tab_webviews: Mutex::new(std::collections::HashMap::new()),
            active_content_tab: Mutex::new(None),
            content_bounds: Mutex::new(None),
            last_content_bounds: Mutex::new(None),
            content_webview_visible: Mutex::new(false),
            browser_engine: Arc::new(BrowserEngine::new()),
            protocol_handler: Arc::new(Mutex::new(ProtocolHandler::new())),
            security_manager: Arc::new(Mutex::new(SecurityManager::new())),
            telemetry_manager: Arc::new(Mutex::new(TelemetryManager::new())),
            wallet_store: Arc::new(Mutex::new(
                WalletStore::new().unwrap_or_else(|_| WalletStore::default()),
            )),
            agent_manager: Arc::new(AsyncMutex::new(None)),
            approval_broker: approval_broker.clone(),
            afm_node_controller: Arc::new(AsyncMutex::new(None)),
            afm_node_handle: Arc::new(Mutex::new(None)),
            afm_node_config: Arc::new(Mutex::new(AfmNodeConfig::default())),
            mcp_registry: mcp_registry.clone(),
            mcp_config: mcp_config.clone(),
            agent_apps: agent_apps.clone(),
            agent_app_schedules: agent_app_schedules.clone(),
            download_controls: Arc::new(AsyncMutex::new(std::collections::HashMap::new())),
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
                            *slot = Some(Arc::new(manager));
                        });
                    }
                    Err(err) => {
                        log_startup(&format!("agent initialisation failed: {err}"));
                    }
                }
            }

            spawn_agent_app_scheduler(app.app_handle().clone());

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
            log_frontend_event,
            agent_list_tools,
            agent_run_task,
            agent_list_runs,
            agent_cancel_run,
            list_agent_apps,
            launch_agent_app,
            list_agent_app_schedules,
            save_agent_app_schedule,
            delete_agent_app_schedule,
            agent_list_skills,
            agent_get_credits,
            agent_top_up_credits,
            agent_set_no_egress,
            agent_resolve_approval,
            activate_tab_webview,
            close_tab_webview,
            navigate_to,
            set_content_bounds,
            content_go_back,
            content_go_forward,
            content_reload,
            content_stop,
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
            search_history,
            remove_history_entry,
            start_download,
            get_downloads,
            cancel_download,
            reveal_download,
            resolve_protocol_url,
            probe_runtime_url,
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

async fn get_agent_manager<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
) -> Result<Arc<AgentManager>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    let agent_mutex = state.agent_manager.clone();
    drop(state);

    let guard = agent_mutex.lock().await;
    guard
        .as_ref()
        .cloned()
        .ok_or_else(|| "agent manager not initialised".to_string())
}

#[tauri::command]
async fn agent_list_tools<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<Vec<McpToolDescription>, String> {
    let manager = get_agent_manager(&app_handle).await?;
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
    let manager = get_agent_manager(&app_handle).await?;
    manager
        .run_task(request)
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
async fn agent_list_runs<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<Vec<AgentRunSummary>, String> {
    let manager = get_agent_manager(&app_handle).await?;
    Ok(manager.list_runs(24).await)
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentCancelRunRequest {
    run_id: String,
}

#[tauri::command]
async fn agent_cancel_run<R: Runtime>(
    request: AgentCancelRunRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let manager = get_agent_manager(&app_handle).await?;
    let cancelled = manager
        .cancel_run(request.run_id.trim())
        .await
        .map_err(|err| err.to_string())?;
    if cancelled {
        Ok(())
    } else {
        Err(format!("unknown agent run `{}`", request.run_id.trim()))
    }
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
async fn list_agent_app_schedules<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<Vec<AgentAppScheduleSummary>, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    Ok(state.agent_app_schedules.list())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SaveAgentAppScheduleRequest {
    draft: AgentAppScheduleDraft,
}

#[tauri::command]
async fn save_agent_app_schedule<R: Runtime>(
    request: SaveAgentAppScheduleRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<AgentAppScheduleSummary, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    if state.agent_apps.find(&request.draft.app_id).is_none() {
        return Err(format!("agent app `{}` not found", request.draft.app_id));
    }
    state
        .agent_app_schedules
        .upsert(request.draft, unix_time_ms())
        .map_err(|err| err.to_string())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeleteAgentAppScheduleRequest {
    schedule_id: String,
}

#[tauri::command]
async fn delete_agent_app_schedule<R: Runtime>(
    request: DeleteAgentAppScheduleRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<bool, String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;
    state
        .agent_app_schedules
        .delete(request.schedule_id.trim())
        .map_err(|err| err.to_string())
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

    let manager = {
        let guard = agent_mutex.lock().await;
        guard
            .as_ref()
            .cloned()
            .ok_or_else(|| "agent manager not initialised".to_string())?
    };

    manager
        .run_task(AgentRunRequest {
            task,
            skill_id: app.skill_id.clone(),
            no_egress: app.no_egress,
            label: Some(app.name.clone()),
            app_id: Some(app.id.clone()),
            schedule_id: None,
        })
        .await
        .map_err(|err| err.to_string())
}

#[tauri::command]
async fn agent_list_skills<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<Vec<AgentSkillSummary>, String> {
    let manager = get_agent_manager(&app_handle).await?;
    Ok(manager.list_skills())
}

#[tauri::command]
async fn agent_get_credits<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<CreditSnapshot, String> {
    let manager = get_agent_manager(&app_handle).await?;
    Ok(manager.credit_snapshot().await)
}

#[tauri::command]
async fn agent_top_up_credits<R: Runtime>(
    tokens: u32,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<CreditSnapshot, String> {
    let manager = get_agent_manager(&app_handle).await?;
    Ok(manager.top_up_credits(tokens).await)
}

#[tauri::command]
async fn agent_set_no_egress<R: Runtime>(
    enabled: bool,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let manager = get_agent_manager(&app_handle).await?;
    manager.set_no_egress(enabled);
    Ok(())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentResolveApprovalRequest {
    request_id: String,
    approved: bool,
}

#[tauri::command]
async fn agent_resolve_approval<R: Runtime>(
    request: AgentResolveApprovalRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    state
        .approval_broker
        .resolve(&request.request_id, request.approved)
        .await
        .map_err(|err| err.to_string())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ActivateTabWebviewRequest {
    tab_id: String,
    #[serde(default)]
    initial_url: Option<String>,
}

#[tauri::command]
async fn activate_tab_webview<R: Runtime>(
    request: ActivateTabWebviewRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    log_command(
        "activate_tab_webview",
        &format!(
            "tab_id={} initial_url={}",
            request.tab_id,
            request.initial_url.as_deref().unwrap_or("<none>")
        ),
    );

    let tab_id = request.tab_id.trim();
    if tab_id.is_empty() {
        log_command("activate_tab_webview", "invalid request: empty tab_id");
        return Err("tab_id must not be empty".to_string());
    }

    ensure_tab_webview(&app_handle, tab_id, request.initial_url.as_deref())?;

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    ensure_browser_engine_tab(
        &state,
        tab_id,
        request.initial_url.as_deref().unwrap_or("about:blank"),
        true,
    )?;

    if let Some(url) = &request.initial_url {
        if let Ok(mut current_url) = state.current_url.lock() {
            *current_url = url.clone();
        }
    }

    let labels_to_hide = state
        .content_tab_webviews
        .lock()
        .map_err(|_| "content webview map mutex poisoned".to_string())?
        .iter()
        .filter(|(id, _)| id.as_str() != tab_id)
        .map(|(_, label)| label.clone())
        .collect::<Vec<_>>();

    state
        .active_content_tab
        .lock()
        .map_err(|_| "active tab mutex poisoned".to_string())?
        .replace(tab_id.to_string());

    for label in labels_to_hide {
        if let Some(webview) = app_handle.get_webview(&label) {
            log_command(
                "activate_tab_webview",
                &format!("hiding sibling label={label}"),
            );
            let _ = webview.hide();
        }
    }

    match apply_bounds_to_active_webview(&app_handle) {
        Ok(()) => {
            log_command("activate_tab_webview", &format!("success tab_id={tab_id}"));
            Ok(())
        }
        Err(err) => {
            log_command(
                "activate_tab_webview",
                &format!("apply_bounds failed tab_id={tab_id} err={err}"),
            );
            Err(err)
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CloseTabWebviewRequest {
    tab_id: String,
}

#[tauri::command]
async fn close_tab_webview<R: Runtime>(
    request: CloseTabWebviewRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let tab_id = request.tab_id.trim();
    if tab_id.is_empty() {
        return Err("tab_id must not be empty".to_string());
    }

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    let removed_label = state
        .content_tab_webviews
        .lock()
        .map_err(|_| "content webview map mutex poisoned".to_string())?
        .remove(tab_id);

    let was_active = state
        .active_content_tab
        .lock()
        .map_err(|_| "active tab mutex poisoned".to_string())?
        .as_ref()
        .map(|id| id == tab_id)
        .unwrap_or(false);

    if was_active {
        state
            .active_content_tab
            .lock()
            .map_err(|_| "active tab mutex poisoned".to_string())?
            .take();
        let _ = state.browser_engine.set_active_tab_id(None);
    }

    if let Some(label) = removed_label {
        if let Some(webview) = app_handle.get_webview(&label) {
            webview
                .close()
                .map_err(|e| format!("Failed to close tab webview: {e}"))?;
        }
    }

    Ok(())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NavigateToRequest {
    url: String,
    #[serde(default)]
    tab_id: Option<String>,
}

// Tauri command to navigate a tab webview to a URL.
#[tauri::command]
async fn navigate_to<R: Runtime>(
    request: NavigateToRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    log_command(
        "navigate_to",
        &format!(
            "url={} tab_id={}",
            request.url,
            request.tab_id.as_deref().unwrap_or("<auto>")
        ),
    );

    if request.url.trim().is_empty() {
        log_command("navigate_to", "invalid request: empty url");
        return Err("url must not be empty".to_string());
    }

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    let target_tab_id = if let Some(tab_id) = request.tab_id.as_ref() {
        if tab_id.trim().is_empty() {
            log_command("navigate_to", "invalid request: empty tab_id");
            return Err("tab_id must not be empty".to_string());
        }
        tab_id.trim().to_string()
    } else {
        active_tab_id(&state)?.ok_or_else(|| "No active tab webview available".to_string())?
    };

    let active_tab = active_tab_id(&state)?;
    log_command(
        "navigate_to",
        &format!(
            "target_tab_id={target_tab_id} active_tab={}",
            active_tab.as_deref().unwrap_or("<none>")
        ),
    );

    if let Ok(mut current_url) = state.current_url.lock() {
        *current_url = request.url.clone();
    }

    ensure_browser_engine_tab(&state, &target_tab_id, &request.url, true)?;

    let webview = ensure_tab_webview(&app_handle, &target_tab_id, Some(&request.url))?;
    let target_label =
        read_tab_label(&state, &target_tab_id)?.unwrap_or_else(|| "<missing>".to_string());
    log_command(
        "navigate_to",
        &format!("ensure_tab_webview done target_label={target_label}"),
    );

    if is_internal_url(&request.url) {
        log_command(
            "navigate_to",
            &format!("internal URL skip load target_tab_id={target_tab_id}"),
        );
        return Ok(());
    }

    let target = parse_external_url(&request.url)?;
    let target_url = target.to_string();
    log_command("navigate_to", &format!("parsed target_url={target_url}"));

    webview.navigate(target).map_err(|e| {
        let err = format!("Failed to navigate: {e}");
        log_command(
            "navigate_to",
            &format!("navigation failed target_tab_id={target_tab_id} label={target_label} {err}"),
        );
        err
    })?;

    if active_tab.as_deref() == Some(target_tab_id.as_str()) {
        log_command(
            "navigate_to",
            &format!("active tab; applying bounds tab_id={target_tab_id}"),
        );
        apply_bounds_to_active_webview(&app_handle)?;
    }
    log_command("navigate_to", &format!("success tab_id={target_tab_id}"));

    Ok(())
}

#[derive(Debug, Deserialize)]
struct ContentBounds {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SetContentBoundsRequest {
    bounds: Option<ContentBounds>,
    #[serde(default)]
    tab_id: Option<String>,
}

// Tauri command to position and show/hide the active content webview.
#[tauri::command]
async fn set_content_bounds<R: Runtime>(
    request: SetContentBoundsRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    let tab_id = request.tab_id.as_deref().unwrap_or("<auto>");
    let bounds_dbg = request
        .bounds
        .as_ref()
        .map(|b| format!("{}x{} @ {},{}", b.width, b.height, b.x, b.y))
        .unwrap_or_else(|| "<none>".to_string());
    log_command(
        "set_content_bounds",
        &format!("tab_id={tab_id} bounds={bounds_dbg}"),
    );

    let state = app_handle
        .try_state::<AppState>()
        .ok_or_else(|| "application state unavailable".to_string())?;

    if let Some(tab_id) = request.tab_id.as_ref() {
        if tab_id.trim().is_empty() {
            log_command("set_content_bounds", "invalid request: empty tab_id");
            return Err("tab_id must not be empty".to_string());
        }

        ensure_tab_webview(&app_handle, tab_id.trim(), None)?;
        state
            .active_content_tab
            .lock()
            .map_err(|_| "active tab mutex poisoned".to_string())?
            .replace(tab_id.trim().to_string());
    }

    let converted = request.bounds.map(|bounds| ContentWebviewBounds {
        x: bounds.x,
        y: bounds.y,
        width: bounds.width,
        height: bounds.height,
    });

    {
        let mut bounds_slot = state
            .content_bounds
            .lock()
            .map_err(|_| "content bounds mutex poisoned".to_string())?;
        *bounds_slot = converted;
    };

    match apply_bounds_to_active_webview(&app_handle) {
        Ok(()) => {
            log_command("set_content_bounds", "success");
            Ok(())
        }
        Err(err) => {
            log_command(
                "set_content_bounds",
                &format!("apply_bounds failed tab_id={tab_id} err={err}"),
            );
            Err(err)
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TabScopedRequest {
    #[serde(default)]
    tab_id: Option<String>,
}

fn resolve_scoped_webview<R: Runtime>(
    app_handle: &tauri::AppHandle<R>,
    request: &TabScopedRequest,
) -> Result<Option<tauri::webview::Webview<R>>, String> {
    if let Some(tab_id) = request.tab_id.as_ref() {
        if tab_id.trim().is_empty() {
            return Err("tab_id must not be empty".to_string());
        }

        return Ok(Some(ensure_tab_webview(app_handle, tab_id.trim(), None)?));
    }

    active_tab_webview(app_handle)
}

#[derive(Clone, Copy)]
enum StaticContentScript {
    HistoryBack,
    HistoryForward,
    StopLoading,
}

impl StaticContentScript {
    fn source(self) -> &'static str {
        match self {
            Self::HistoryBack => "history.back();",
            Self::HistoryForward => "history.forward();",
            Self::StopLoading => "window.stop();",
        }
    }

    fn error_label(self) -> &'static str {
        match self {
            Self::HistoryBack => "go back",
            Self::HistoryForward => "go forward",
            Self::StopLoading => "stop loading",
        }
    }
}

fn run_static_content_script<R: Runtime>(
    webview: &tauri::webview::Webview<R>,
    script: StaticContentScript,
) -> Result<(), String> {
    // Only allow audited built-in navigation scripts here. User/model-provided
    // JavaScript belongs in the structured automation bridge, which JSON-encodes
    // selector/text inputs before evaluating them.
    webview
        .eval(script.source())
        .map_err(|e| format!("Failed to {}: {e}", script.error_label()))
}

#[tauri::command]
async fn content_go_back<R: Runtime>(
    request: TabScopedRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    if let Some(webview) = resolve_scoped_webview(&app_handle, &request)? {
        run_static_content_script(&webview, StaticContentScript::HistoryBack)?;
    }

    Ok(())
}

#[tauri::command]
async fn content_go_forward<R: Runtime>(
    request: TabScopedRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    if let Some(webview) = resolve_scoped_webview(&app_handle, &request)? {
        run_static_content_script(&webview, StaticContentScript::HistoryForward)?;
    }

    Ok(())
}

#[tauri::command]
async fn content_reload<R: Runtime>(
    request: TabScopedRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    if let Some(webview) = resolve_scoped_webview(&app_handle, &request)? {
        webview
            .reload()
            .map_err(|e| format!("Failed to reload: {e}"))?;
    }

    Ok(())
}

#[tauri::command]
async fn content_stop<R: Runtime>(
    request: TabScopedRequest,
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<(), String> {
    if let Some(webview) = resolve_scoped_webview(&app_handle, &request)? {
        run_static_content_script(&webview, StaticContentScript::StopLoading)?;
    }

    Ok(())
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct FrontendTraceEvent {
    event: String,
    #[serde(default)]
    details: Option<String>,
    #[serde(default)]
    source: Option<String>,
}

#[tauri::command]
async fn log_frontend_event(request: FrontendTraceEvent) -> Result<(), String> {
    let details = request.details.unwrap_or_else(|| "<none>".to_string());
    let source = request.source.unwrap_or_else(|| "frontend".to_string());
    log_startup(&format!(
        "frontend_event | source={} event={} details={}",
        source, request.event, details
    ));
    Ok(())
}

// Tauri command to get the current URL
#[tauri::command]
async fn get_current_url<R: Runtime>(
    _window: tauri::Window<R>,
    app_handle: tauri::AppHandle<R>,
) -> Result<String, String> {
    let current_url = if let Some(state) = app_handle.try_state::<AppState>() {
        if let Ok(current_url) = state.current_url.lock() {
            current_url.clone()
        } else {
            "about:home".to_string()
        }
    } else {
        "about:home".to_string()
    };
    log_command("get_current_url", &format!("return={current_url}"));
    Ok(current_url)
}

#[cfg(test)]
mod tests {
    use super::*;
    use afm_node::AfmNodeConfig;
    use gui::agent::McpServerRegistry;
    use gui::agent_app_schedules::AgentAppScheduleRegistry;
    use gui::agent_apps::AgentAppRegistry;
    use gui::mcp_profiles::McpConfigService;
    use gui::wallet_store::WalletStore;

    #[test]
    #[ignore = "requires tauri runtime"]
    fn test_app_state() {
        let mcp_config = Arc::new(
            McpConfigService::load().unwrap_or_else(|_| McpConfigService::reset().unwrap()),
        );
        let state = AppState {
            current_url: Mutex::new("https://example.com".to_string()),
            content_tab_webviews: Mutex::new(std::collections::HashMap::new()),
            active_content_tab: Mutex::new(None),
            content_bounds: Mutex::new(None),
            last_content_bounds: Mutex::new(None),
            content_webview_visible: Mutex::new(false),
            browser_engine: Arc::new(BrowserEngine::new()),
            protocol_handler: Arc::new(Mutex::new(ProtocolHandler::new())),
            security_manager: Arc::new(Mutex::new(SecurityManager::new())),
            telemetry_manager: Arc::new(Mutex::new(TelemetryManager::new())),
            wallet_store: Arc::new(Mutex::new(WalletStore::default())),
            agent_manager: Arc::new(AsyncMutex::new(None)),
            approval_broker: ApprovalBroker::new(),
            afm_node_controller: Arc::new(AsyncMutex::new(None)),
            afm_node_handle: Arc::new(Mutex::new(None)),
            afm_node_config: Arc::new(Mutex::new(AfmNodeConfig::default())),
            // Keep this unit test hermetic; loading active MCP servers can require
            // environment-specific secret resolution and block in CI.
            mcp_registry: Arc::new(McpServerRegistry::empty(mcp_config.clone())),
            mcp_config,
            agent_apps: Arc::new(AgentAppRegistry::empty()),
            agent_app_schedules: Arc::new(AgentAppScheduleRegistry::empty()),
            download_controls: Arc::new(AsyncMutex::new(std::collections::HashMap::new())),
        };

        let url = state.current_url.lock().unwrap();
        assert_eq!(*url, "https://example.com");
    }
}
