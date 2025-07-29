use crate::telemetry::{TelemetryManager, SecuritySeverity};
use std::collections::HashMap;
use tauri::{AppHandle, Runtime, State};

/// Report an error through telemetry
#[tauri::command]
pub async fn report_error<R: Runtime>(
    error_type: String,
    message: String,
    context: HashMap<String, String>,
    app_handle: AppHandle<R>,
) -> Result<(), String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            telemetry.report_error(&error_type, &message, context)
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Track usage statistics
#[tauri::command]
pub async fn track_usage<R: Runtime>(
    event_type: String,
    event_data: HashMap<String, String>,
    duration_ms: Option<u64>,
    app_handle: AppHandle<R>,
) -> Result<(), String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            telemetry.track_usage(&event_type, event_data, duration_ms)
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Record performance metrics
#[tauri::command]
pub async fn record_performance<R: Runtime>(
    memory_mb: f64,
    cpu_percent: f64,
    network_latency: f64,
    page_load_time: f64,
    startup_time: f64,
    app_handle: AppHandle<R>,
) -> Result<(), String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            telemetry.record_performance(memory_mb, cpu_percent, network_latency, page_load_time, startup_time)
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Get error summary
#[tauri::command]
pub async fn get_error_summary<R: Runtime>(
    app_handle: AppHandle<R>,
) -> Result<HashMap<String, u32>, String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            return telemetry.get_error_summary()
                .map_err(|e| e.to_string());
        }
    }
    Ok(HashMap::new())
}

/// Get performance summary
#[tauri::command]
pub async fn get_performance_summary<R: Runtime>(
    app_handle: AppHandle<R>,
) -> Result<HashMap<String, f64>, String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            return telemetry.get_performance_summary()
                .map_err(|e| e.to_string());
        }
    }
    Ok(HashMap::new())
}

/// Add security alert
#[tauri::command]
pub async fn add_security_alert<R: Runtime>(
    severity: String,
    alert_type: String,
    message: String,
    affected_components: Vec<String>,
    mitigation_steps: Vec<String>,
    app_handle: AppHandle<R>,
) -> Result<(), String> {
    let severity = match severity.as_str() {
        "low" => SecuritySeverity::Low,
        "medium" => SecuritySeverity::Medium,
        "high" => SecuritySeverity::High,
        "critical" => SecuritySeverity::Critical,
        _ => SecuritySeverity::Medium,
    };

    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            telemetry.add_security_alert(severity, &alert_type, &message, affected_components, mitigation_steps)
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Check for updates
#[tauri::command]
pub async fn check_for_updates<R: Runtime>(
    app_handle: AppHandle<R>,
) -> Result<(), String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            telemetry.check_for_updates().await
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

/// Export telemetry data
#[tauri::command]
pub async fn export_telemetry<R: Runtime>(
    app_handle: AppHandle<R>,
) -> Result<String, String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(telemetry) = state.telemetry_manager.lock() {
            return telemetry.export_telemetry()
                .map_err(|e| e.to_string());
        }
    }
    Ok("{}".to_string())
}

/// Enable or disable telemetry
#[tauri::command]
pub async fn set_telemetry_enabled<R: Runtime>(
    enabled: bool,
    app_handle: AppHandle<R>,
) -> Result<(), String> {
    if let Some(state) = app_handle.try_state::<crate::AppState>() {
        if let Ok(mut telemetry) = state.telemetry_manager.lock() {
            telemetry.set_enabled(enabled);
        }
    }
    Ok(())
}
