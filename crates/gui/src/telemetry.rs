use anyhow::{anyhow, Result};
use cid::Cid;
use ed25519_dalek::VerifyingKey;
use hex::decode;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::interval;
use updater::{AvailableUpdate, IpfsFetcher, IpfsGatewayClient, UpdateStatus, Updater};
use url::Url;

/// Error report structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorReport {
    pub id: String,
    pub timestamp: u64,
    pub error_type: String,
    pub message: String,
    pub stack_trace: Option<String>,
    pub context: HashMap<String, String>,
    pub user_agent: String,
    pub app_version: String,
}

/// Usage statistics structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UsageStats {
    pub session_id: String,
    pub timestamp: u64,
    pub event_type: String,
    pub event_data: HashMap<String, String>,
    pub duration_ms: Option<u64>,
}

/// Performance metrics structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub timestamp: u64,
    pub memory_usage_mb: f64,
    pub cpu_usage_percent: f64,
    pub network_latency_ms: f64,
    pub page_load_time_ms: f64,
    pub startup_time_ms: f64,
}

/// Crash report structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrashReport {
    pub id: String,
    pub timestamp: u64,
    pub crash_type: String,
    pub signal: Option<i32>,
    pub stack_trace: String,
    pub system_info: HashMap<String, String>,
    pub app_version: String,
}

/// Server status information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerStatus {
    pub timestamp: u64,
    pub service_name: String,
    pub status: ServiceStatus,
    pub response_time_ms: f64,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ServiceStatus {
    Online,
    Offline,
    Degraded,
    Unknown,
}

/// Network health information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkHealth {
    pub timestamp: u64,
    pub connection_type: String,
    pub bandwidth_mbps: f64,
    pub latency_ms: f64,
    pub packet_loss_percent: f64,
    pub dns_resolution_time_ms: f64,
}

/// Update availability information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdateInfo {
    pub current_version: String,
    pub latest_version: String,
    pub update_available: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub release_notes: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub download_url: Option<String>,
    pub security_update: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manifest_cid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub binary_cid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub binary_sha256: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub binary_size: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub release_notes_cid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ipfs_uri: Option<String>,
    pub checked_at: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub release_notes_text: Option<String>,
    pub can_apply: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub applied_version: Option<String>,
    pub apply_requires_restart: bool,
}

const UPDATE_MANIFEST_ENV: &str = "BROWSER_UPDATE_MANIFEST_CID";
const UPDATE_PUBLIC_KEY_ENV: &str = "BROWSER_UPDATE_PUBLIC_KEY_HEX";
const UPDATE_GATEWAY_ENV: &str = "BROWSER_UPDATE_GATEWAY";
const UPDATE_TARGET_PATH_ENV: &str = "BROWSER_UPDATE_TARGET_PATH";
const MAX_RELEASE_NOTES_BYTES: usize = 128 * 1024;

#[derive(Clone)]
struct UpdateConfig {
    manifest_cid: Cid,
    verifying_key: VerifyingKey,
    gateway_base: Option<Url>,
    target_path: Option<PathBuf>,
}

/// Security alert information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecurityAlert {
    pub id: String,
    pub timestamp: u64,
    pub severity: SecuritySeverity,
    pub alert_type: String,
    pub message: String,
    pub affected_components: Vec<String>,
    pub mitigation_steps: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SecuritySeverity {
    Low,
    Medium,
    High,
    Critical,
}

/// Telemetry manager
pub struct TelemetryManager {
    pub enabled: bool,
    pub session_id: String,
    pub error_reports: Arc<Mutex<Vec<ErrorReport>>>,
    pub usage_stats: Arc<Mutex<Vec<UsageStats>>>,
    pub performance_metrics: Arc<Mutex<Vec<PerformanceMetrics>>>,
    pub crash_reports: Arc<Mutex<Vec<CrashReport>>>,
    pub server_status: Arc<Mutex<HashMap<String, ServerStatus>>>,
    pub network_health: Arc<Mutex<NetworkHealth>>,
    pub update_info: Arc<Mutex<Option<UpdateInfo>>>,
    pub security_alerts: Arc<Mutex<Vec<SecurityAlert>>>,
    update_config: Option<UpdateConfig>,
    available_update: Arc<Mutex<Option<AvailableUpdate>>>,
}

impl TelemetryManager {
    pub fn new() -> Self {
        let update_config = Self::load_update_config();
        Self {
            enabled: true,
            session_id: uuid::Uuid::new_v4().to_string(),
            error_reports: Arc::new(Mutex::new(Vec::new())),
            usage_stats: Arc::new(Mutex::new(Vec::new())),
            performance_metrics: Arc::new(Mutex::new(Vec::new())),
            crash_reports: Arc::new(Mutex::new(Vec::new())),
            server_status: Arc::new(Mutex::new(HashMap::new())),
            network_health: Arc::new(Mutex::new(NetworkHealth {
                timestamp: Self::current_timestamp(),
                connection_type: "unknown".to_string(),
                bandwidth_mbps: 0.0,
                latency_ms: 0.0,
                packet_loss_percent: 0.0,
                dns_resolution_time_ms: 0.0,
            })),
            update_info: Arc::new(Mutex::new(None)),
            security_alerts: Arc::new(Mutex::new(Vec::new())),
            update_config,
            available_update: Arc::new(Mutex::new(None)),
        }
    }

    fn load_update_config() -> Option<UpdateConfig> {
        let manifest_str = match env::var(UPDATE_MANIFEST_ENV) {
            Ok(value) => value,
            Err(_) => return None,
        };

        let public_key_hex = match env::var(UPDATE_PUBLIC_KEY_ENV) {
            Ok(value) => value,
            Err(_) => {
                log::warn!(
                    "update manifest CID provided but {} is missing",
                    UPDATE_PUBLIC_KEY_ENV
                );
                return None;
            }
        };

        let manifest_cid = match Cid::try_from(manifest_str.as_str()) {
            Ok(cid) => cid,
            Err(err) => {
                log::warn!(
                    "failed to parse manifest CID from {}: {}",
                    UPDATE_MANIFEST_ENV,
                    err
                );
                return None;
            }
        };

        let key_bytes = match decode(public_key_hex.trim()) {
            Ok(bytes) => bytes,
            Err(err) => {
                log::warn!("invalid updater public key hex: {}", err);
                return None;
            }
        };

        if key_bytes.len() != 32 {
            log::warn!(
                "updater public key must be exactly 32 bytes (found {} bytes)",
                key_bytes.len()
            );
            return None;
        }

        let mut key_array = [0u8; 32];
        key_array.copy_from_slice(&key_bytes);

        let verifying_key = match VerifyingKey::from_bytes(&key_array) {
            Ok(key) => key,
            Err(err) => {
                log::warn!("failed to construct verifying key: {}", err);
                return None;
            }
        };

        let gateway_base = match env::var(UPDATE_GATEWAY_ENV) {
            Ok(url) if !url.trim().is_empty() => match Url::parse(url.trim()) {
                Ok(parsed) => Some(parsed),
                Err(err) => {
                    log::warn!("invalid IPFS gateway URL: {}", err);
                    None
                }
            },
            _ => None,
        };

        let target_path = match env::var(UPDATE_TARGET_PATH_ENV) {
            Ok(path) if !path.trim().is_empty() => {
                let buf = PathBuf::from(path.trim());
                if buf.is_absolute() {
                    Some(buf)
                } else {
                    log::warn!(
                        "update target path must be absolute ({} provided)",
                        buf.display()
                    );
                    None
                }
            }
            _ => None,
        };

        Some(UpdateConfig {
            manifest_cid,
            verifying_key,
            gateway_base,
            target_path,
        })
    }

    fn build_fetcher(&self, config: &UpdateConfig) -> Result<IpfsGatewayClient> {
        let mut builder = IpfsGatewayClient::builder();
        if let Some(base) = &config.gateway_base {
            builder = builder.base_url(base.clone());
        }
        Ok(builder.build()?)
    }

    async fn fetch_release_notes(
        &self,
        fetcher: &IpfsGatewayClient,
        update: &AvailableUpdate,
    ) -> Result<Option<String>> {
        let signed = &update.manifest().signed;
        let cid_str = match &signed.release_notes_cid {
            Some(cid) => cid,
            None => return Ok(None),
        };

        let cid = Cid::try_from(cid_str.as_str())
            .map_err(|err| anyhow!("invalid release notes cid: {}", err))?;
        let mut notes = fetcher.fetch_bytes(&cid, None).await?;

        if notes.len() > MAX_RELEASE_NOTES_BYTES {
            log::warn!(
                "release notes truncated to {} bytes (original size: {} bytes)",
                MAX_RELEASE_NOTES_BYTES,
                notes.len()
            );
            notes.truncate(MAX_RELEASE_NOTES_BYTES);
        }

        match String::from_utf8(notes) {
            Ok(text) => Ok(Some(text)),
            Err(err) => {
                log::warn!("release notes are not valid UTF-8: {}", err);
                Ok(None)
            }
        }
    }

    async fn perform_update_check(
        &self,
        current_version: &str,
        config: &UpdateConfig,
    ) -> Result<UpdateInfo> {
        let fetcher = self.build_fetcher(config)?;
        let updater = Updater::new(fetcher.clone(), config.verifying_key.clone());

        match updater
            .check_for_update_str(current_version, &config.manifest_cid)
            .await?
        {
            UpdateStatus::UpToDate => {
                if let Ok(mut pending) = self.available_update.lock() {
                    *pending = None;
                }

                Ok(UpdateInfo {
                    current_version: current_version.to_string(),
                    latest_version: current_version.to_string(),
                    update_available: false,
                    release_notes: None,
                    download_url: None,
                    security_update: false,
                    manifest_cid: Some(config.manifest_cid.to_string()),
                    binary_cid: None,
                    binary_sha256: None,
                    binary_size: None,
                    release_notes_cid: None,
                    ipfs_uri: None,
                    checked_at: Self::current_timestamp(),
                    release_notes_text: None,
                    can_apply: config.target_path.is_some(),
                    applied_version: None,
                    apply_requires_restart: false,
                })
            }
            UpdateStatus::Available(update) => {
                if let Ok(mut pending) = self.available_update.lock() {
                    *pending = Some(update.clone());
                }

                let manifest = update.manifest();
                let signed = &manifest.signed;
                let ipfs_uri = Some(format!("ipfs://{}", signed.binary_cid));
                let download_url = config
                    .gateway_base
                    .as_ref()
                    .and_then(|base| base.join(&format!("ipfs/{}", signed.binary_cid)).ok())
                    .map(|url| url.to_string());
                let release_notes_link = signed
                    .release_notes_cid
                    .as_ref()
                    .map(|cid| format!("ipfs://{}", cid));
                let release_notes_text = self.fetch_release_notes(&fetcher, &update).await?;

                Ok(UpdateInfo {
                    current_version: current_version.to_string(),
                    latest_version: signed.version.clone(),
                    update_available: true,
                    release_notes: release_notes_link,
                    download_url,
                    security_update: false,
                    manifest_cid: Some(config.manifest_cid.to_string()),
                    binary_cid: Some(signed.binary_cid.clone()),
                    binary_sha256: Some(signed.binary_sha256.clone()),
                    binary_size: Some(signed.binary_size),
                    release_notes_cid: signed.release_notes_cid.clone(),
                    ipfs_uri,
                    checked_at: Self::current_timestamp(),
                    release_notes_text,
                    can_apply: config.target_path.is_some(),
                    applied_version: None,
                    apply_requires_restart: false,
                })
            }
        }
    }

    pub async fn apply_pending_update(&self) -> Result<(ApplyUpdateSummary, UpdateInfo)> {
        let config = self
            .update_config
            .as_ref()
            .ok_or_else(|| anyhow!("update configuration unavailable"))?;

        let target_path = config
            .target_path
            .clone()
            .ok_or_else(|| anyhow!("BROWSER_UPDATE_TARGET_PATH not set or invalid"))?;

        let pending_update = {
            self.available_update
                .lock()
                .map_err(|_| anyhow!("pending update lock poisoned"))?
                .clone()
        };

        let update = pending_update.ok_or_else(|| anyhow!("no pending update available"))?;

        let fetcher = self.build_fetcher(config)?;
        let updater = Updater::new(fetcher, config.verifying_key.clone());
        let outcome = updater
            .download_and_apply(&update, target_path.as_path())
            .await?;

        if let Ok(mut guard) = self.available_update.lock() {
            *guard = None;
        }

        let summary = ApplyUpdateSummary {
            new_version: outcome.new_version.to_string(),
            target_path: outcome.target_path.to_string_lossy().into_owned(),
            backup_path: outcome
                .backup_path
                .as_ref()
                .map(|p| p.to_string_lossy().into_owned()),
            requires_restart: true,
        };

        let mut updated_info = None;
        if let Ok(mut info_guard) = self.update_info.lock() {
            let mut info = info_guard.clone().unwrap_or_else(|| UpdateInfo {
                current_version: env!("CARGO_PKG_VERSION").to_string(),
                latest_version: summary.new_version.clone(),
                update_available: false,
                release_notes: None,
                download_url: None,
                security_update: false,
                manifest_cid: Some(config.manifest_cid.to_string()),
                binary_cid: None,
                binary_sha256: None,
                binary_size: None,
                release_notes_cid: None,
                ipfs_uri: None,
                checked_at: Self::current_timestamp(),
                release_notes_text: None,
                can_apply: config.target_path.is_some(),
                applied_version: None,
                apply_requires_restart: false,
            });

            info.update_available = false;
            info.latest_version = summary.new_version.clone();
            info.applied_version = Some(summary.new_version.clone());
            info.apply_requires_restart = true;
            info.checked_at = Self::current_timestamp();
            info.binary_cid = None;
            info.binary_sha256 = None;
            info.binary_size = None;
            info.ipfs_uri = None;
            info.can_apply = config.target_path.is_some();

            *info_guard = Some(info.clone());
            updated_info = Some(info);
        }

        let updated_info = updated_info.ok_or_else(|| anyhow!("failed to update status"))?;

        Ok((summary, updated_info))
    }
    /// Enable or disable telemetry
    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
    }

    /// Get current timestamp
    fn current_timestamp() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
    }

    /// Report an error
    pub fn report_error(
        &self,
        error_type: &str,
        message: &str,
        context: HashMap<String, String>,
    ) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        let report = ErrorReport {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: Self::current_timestamp(),
            error_type: error_type.to_string(),
            message: message.to_string(),
            stack_trace: None, // Could be populated with backtrace
            context,
            user_agent: "Decentralized Browser".to_string(),
            app_version: env!("CARGO_PKG_VERSION").to_string(),
        };

        if let Ok(mut reports) = self.error_reports.lock() {
            reports.push(report);

            // Keep only the last 1000 error reports
            let reports_len = reports.len();
            if reports_len > 1000 {
                reports.drain(0..reports_len - 1000);
            }
        }

        Ok(())
    }

    /// Track usage statistics
    pub fn track_usage(
        &self,
        event_type: &str,
        event_data: HashMap<String, String>,
        duration_ms: Option<u64>,
    ) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        let stats = UsageStats {
            session_id: self.session_id.clone(),
            timestamp: Self::current_timestamp(),
            event_type: event_type.to_string(),
            event_data,
            duration_ms,
        };

        if let Ok(mut usage_stats) = self.usage_stats.lock() {
            usage_stats.push(stats);

            // Keep only the last 5000 usage events
            let usage_stats_len = usage_stats.len();
            if usage_stats_len > 5000 {
                usage_stats.drain(0..usage_stats_len - 5000);
            }
        }

        Ok(())
    }

    /// Record performance metrics
    pub fn record_performance(
        &self,
        memory_mb: f64,
        cpu_percent: f64,
        network_latency: f64,
        page_load_time: f64,
        startup_time: f64,
    ) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }

        let metrics = PerformanceMetrics {
            timestamp: Self::current_timestamp(),
            memory_usage_mb: memory_mb,
            cpu_usage_percent: cpu_percent,
            network_latency_ms: network_latency,
            page_load_time_ms: page_load_time,
            startup_time_ms: startup_time,
        };

        if let Ok(mut performance_metrics) = self.performance_metrics.lock() {
            performance_metrics.push(metrics);

            // Keep only the last 1000 performance metrics
            let metrics_len = performance_metrics.len();
            if metrics_len > 1000 {
                performance_metrics.drain(0..metrics_len - 1000);
            }
        }

        Ok(())
    }

    /// Report a crash
    pub fn report_crash(
        &self,
        crash_type: &str,
        signal: Option<i32>,
        stack_trace: &str,
        system_info: HashMap<String, String>,
    ) -> Result<()> {
        let report = CrashReport {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: Self::current_timestamp(),
            crash_type: crash_type.to_string(),
            signal,
            stack_trace: stack_trace.to_string(),
            system_info,
            app_version: env!("CARGO_PKG_VERSION").to_string(),
        };

        if let Ok(mut crash_reports) = self.crash_reports.lock() {
            crash_reports.push(report);
        }

        Ok(())
    }

    /// Update server status
    pub fn update_server_status(
        &self,
        service_name: &str,
        status: ServiceStatus,
        response_time: f64,
        error_message: Option<String>,
    ) -> Result<()> {
        let server_status = ServerStatus {
            timestamp: Self::current_timestamp(),
            service_name: service_name.to_string(),
            status,
            response_time_ms: response_time,
            error_message,
        };

        if let Ok(mut status_map) = self.server_status.lock() {
            status_map.insert(service_name.to_string(), server_status);
        }

        Ok(())
    }

    /// Update network health
    pub fn update_network_health(
        &self,
        connection_type: &str,
        bandwidth: f64,
        latency: f64,
        packet_loss: f64,
        dns_time: f64,
    ) -> Result<()> {
        let health = NetworkHealth {
            timestamp: Self::current_timestamp(),
            connection_type: connection_type.to_string(),
            bandwidth_mbps: bandwidth,
            latency_ms: latency,
            packet_loss_percent: packet_loss,
            dns_resolution_time_ms: dns_time,
        };

        if let Ok(mut network_health) = self.network_health.lock() {
            *network_health = health;
        }

        Ok(())
    }

    /// Check for updates
    pub async fn check_for_updates(&self) -> Result<()> {
        let current_version = env!("CARGO_PKG_VERSION").to_string();

        let update_info = if let Some(config) = &self.update_config {
            self.perform_update_check(&current_version, config).await?
        } else {
            UpdateInfo {
                current_version: current_version.clone(),
                latest_version: current_version,
                update_available: false,
                release_notes: None,
                download_url: None,
                security_update: false,
                manifest_cid: None,
                binary_cid: None,
                binary_sha256: None,
                binary_size: None,
                release_notes_cid: None,
                ipfs_uri: None,
                checked_at: Self::current_timestamp(),
                release_notes_text: None,
                can_apply: false,
                applied_version: None,
                apply_requires_restart: false,
            }
        };

        if let Ok(mut update_info_lock) = self.update_info.lock() {
            *update_info_lock = Some(update_info);
        }

        Ok(())
    }

    /// Add security alert
    pub fn add_security_alert(
        &self,
        severity: SecuritySeverity,
        alert_type: &str,
        message: &str,
        affected_components: Vec<String>,
        mitigation_steps: Vec<String>,
    ) -> Result<()> {
        let alert = SecurityAlert {
            id: uuid::Uuid::new_v4().to_string(),
            timestamp: Self::current_timestamp(),
            severity,
            alert_type: alert_type.to_string(),
            message: message.to_string(),
            affected_components,
            mitigation_steps,
        };

        if let Ok(mut security_alerts) = self.security_alerts.lock() {
            security_alerts.push(alert);

            // Keep only the last 100 security alerts
            let len = security_alerts.len();
            if len > 100 {
                security_alerts.drain(0..len - 100);
            }
        }

        Ok(())
    }

    /// Get error reports summary
    pub fn get_error_summary(&self) -> Result<HashMap<String, u32>> {
        let mut summary = HashMap::new();

        if let Ok(reports) = self.error_reports.lock() {
            for report in reports.iter() {
                *summary.entry(report.error_type.clone()).or_insert(0) += 1;
            }
        }

        Ok(summary)
    }

    /// Get performance summary
    pub fn get_performance_summary(&self) -> Result<HashMap<String, f64>> {
        let mut summary = HashMap::new();

        if let Ok(metrics) = self.performance_metrics.lock() {
            if !metrics.is_empty() {
                let count = metrics.len() as f64;
                let avg_memory = metrics.iter().map(|m| m.memory_usage_mb).sum::<f64>() / count;
                let avg_cpu = metrics.iter().map(|m| m.cpu_usage_percent).sum::<f64>() / count;
                let avg_latency = metrics.iter().map(|m| m.network_latency_ms).sum::<f64>() / count;

                summary.insert("avg_memory_mb".to_string(), avg_memory);
                summary.insert("avg_cpu_percent".to_string(), avg_cpu);
                summary.insert("avg_latency_ms".to_string(), avg_latency);
            }
        }

        Ok(summary)
    }

    /// Start monitoring loop
    pub async fn start_monitoring(&self) -> Result<()> {
        let mut interval = interval(Duration::from_secs(60)); // Monitor every minute

        loop {
            interval.tick().await;

            if !self.enabled {
                continue;
            }

            // Check server status
            self.check_server_health().await?;

            // Update network health
            self.measure_network_health().await?;

            // Check for updates
            self.check_for_updates().await?;

            // Record performance metrics
            self.collect_performance_metrics().await?;
        }
    }

    /// Check server health
    async fn check_server_health(&self) -> Result<()> {
        // Mock server health checks - in production, these would be real health checks
        let services = vec![
            ("blockchain_rpc", "https://rpc.polkadot.io"),
            ("ipfs_gateway", "https://ipfs.io"),
            ("ens_resolver", "https://cloudflare-eth.com"),
        ];

        for (service_name, _url) in services {
            // Simulate health check
            let status = ServiceStatus::Online;
            let response_time = 50.0; // Mock response time

            self.update_server_status(service_name, status, response_time, None)?;
        }

        Ok(())
    }

    /// Measure network health
    async fn measure_network_health(&self) -> Result<()> {
        // Mock network health measurement - in production, this would use real network tests
        self.update_network_health(
            "wifi", 100.0, // bandwidth
            20.0,  // latency
            0.1,   // packet loss
            5.0,   // DNS resolution time
        )?;

        Ok(())
    }

    /// Collect performance metrics
    async fn collect_performance_metrics(&self) -> Result<()> {
        // Mock performance collection - in production, this would use system APIs
        self.record_performance(
            150.0,  // memory usage
            15.0,   // CPU usage
            20.0,   // network latency
            800.0,  // page load time
            2000.0, // startup time
        )?;

        Ok(())
    }

    /// Export telemetry data for analysis
    pub fn export_telemetry(&self) -> Result<String> {
        let mut data = HashMap::new();

        if let Ok(errors) = self.error_reports.lock() {
            data.insert("errors", serde_json::to_value(&*errors)?);
        }

        if let Ok(usage) = self.usage_stats.lock() {
            data.insert("usage", serde_json::to_value(&*usage)?);
        }

        if let Ok(performance) = self.performance_metrics.lock() {
            data.insert("performance", serde_json::to_value(&*performance)?);
        }

        if let Ok(crashes) = self.crash_reports.lock() {
            data.insert("crashes", serde_json::to_value(&*crashes)?);
        }

        Ok(serde_json::to_string_pretty(&data)?)
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct ApplyUpdateSummary {
    pub new_version: String,
    pub target_path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backup_path: Option<String>,
    pub requires_restart: bool,
}

impl Default for TelemetryManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_telemetry_manager_creation() {
        let manager = TelemetryManager::new();
        assert!(manager.enabled);
        assert!(!manager.session_id.is_empty());
    }

    #[test]
    fn test_error_reporting() {
        let manager = TelemetryManager::new();
        let mut context = HashMap::new();
        context.insert("component".to_string(), "browser_engine".to_string());

        manager
            .report_error("network_error", "Failed to connect", context)
            .unwrap();

        let summary = manager.get_error_summary().unwrap();
        assert_eq!(summary.get("network_error"), Some(&1));
    }

    #[test]
    fn test_usage_tracking() {
        let manager = TelemetryManager::new();
        let mut event_data = HashMap::new();
        event_data.insert("url".to_string(), "https://example.com".to_string());

        manager
            .track_usage("page_visit", event_data, Some(5000))
            .unwrap();

        if let Ok(usage_stats) = manager.usage_stats.lock() {
            assert_eq!(usage_stats.len(), 1);
            assert_eq!(usage_stats[0].event_type, "page_visit");
        };
    }

    #[test]
    fn test_performance_metrics() {
        let manager = TelemetryManager::new();

        manager
            .record_performance(100.0, 10.0, 15.0, 500.0, 1500.0)
            .unwrap();

        let summary = manager.get_performance_summary().unwrap();
        assert_eq!(summary.get("avg_memory_mb"), Some(&100.0));
        assert_eq!(summary.get("avg_cpu_percent"), Some(&10.0));
    }

    #[test]
    fn test_security_alerts() {
        let manager = TelemetryManager::new();

        manager
            .add_security_alert(
                SecuritySeverity::High,
                "certificate_error",
                "Invalid SSL certificate detected",
                vec!["network_module".to_string()],
                vec!["Update certificates".to_string()],
            )
            .unwrap();

        if let Ok(alerts) = manager.security_alerts.lock() {
            assert_eq!(alerts.len(), 1);
            assert_eq!(alerts[0].alert_type, "certificate_error");
        };
    }

    #[tokio::test]
    async fn test_update_check() {
        env::remove_var(UPDATE_MANIFEST_ENV);
        env::remove_var(UPDATE_PUBLIC_KEY_ENV);
        env::remove_var(UPDATE_GATEWAY_ENV);
        env::remove_var(UPDATE_TARGET_PATH_ENV);

        let manager = TelemetryManager::new();

        manager.check_for_updates().await.unwrap();

        if let Ok(update_info) = manager.update_info.lock() {
            let info = update_info.as_ref().expect("update info populated");
            assert!(!info.update_available);
            assert_eq!(info.current_version, info.latest_version);
            assert!(!info.can_apply);
            assert!(info.applied_version.is_none());
        };
    }

    #[tokio::test]
    async fn test_apply_without_configuration() {
        env::remove_var(UPDATE_MANIFEST_ENV);
        env::remove_var(UPDATE_PUBLIC_KEY_ENV);
        env::remove_var(UPDATE_GATEWAY_ENV);
        env::remove_var(UPDATE_TARGET_PATH_ENV);

        let manager = TelemetryManager::new();
        assert!(manager.apply_pending_update().await.is_err());
    }
}
