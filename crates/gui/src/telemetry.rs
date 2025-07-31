use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::interval;

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
    pub release_notes: Option<String>,
    pub download_url: Option<String>,
    pub security_update: bool,
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
#[derive(Debug)]
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
}

impl TelemetryManager {
    pub fn new() -> Self {
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
        }
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
    pub fn report_error(&self, error_type: &str, message: &str, context: HashMap<String, String>) -> Result<()> {
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
    pub fn track_usage(&self, event_type: &str, event_data: HashMap<String, String>, duration_ms: Option<u64>) -> Result<()> {
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
    pub fn record_performance(&self, memory_mb: f64, cpu_percent: f64, network_latency: f64, page_load_time: f64, startup_time: f64) -> Result<()> {
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
    pub fn report_crash(&self, crash_type: &str, signal: Option<i32>, stack_trace: &str, system_info: HashMap<String, String>) -> Result<()> {
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
    pub fn update_server_status(&self, service_name: &str, status: ServiceStatus, response_time: f64, error_message: Option<String>) -> Result<()> {
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
    pub fn update_network_health(&self, connection_type: &str, bandwidth: f64, latency: f64, packet_loss: f64, dns_time: f64) -> Result<()> {
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
        // Simulate update check - in production, this would call a real update service
        let current_version = env!("CARGO_PKG_VERSION").to_string();
        
        // Mock update info - in production, this would fetch from GitHub releases or update server
        let update_info = UpdateInfo {
            current_version: current_version.clone(),
            latest_version: current_version, // No update available in this example
            update_available: false,
            release_notes: None,
            download_url: None,
            security_update: false,
        };

        if let Ok(mut update_info_lock) = self.update_info.lock() {
            *update_info_lock = Some(update_info);
        }

        Ok(())
    }

    /// Add security alert
    pub fn add_security_alert(&self, severity: SecuritySeverity, alert_type: &str, message: &str, affected_components: Vec<String>, mitigation_steps: Vec<String>) -> Result<()> {
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
            "wifi",
            100.0, // bandwidth
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
            150.0, // memory usage
            15.0,  // CPU usage
            20.0,  // network latency
            800.0, // page load time
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
        
        manager.report_error("network_error", "Failed to connect", context).unwrap();
        
        let summary = manager.get_error_summary().unwrap();
        assert_eq!(summary.get("network_error"), Some(&1));
    }

    #[test]
    fn test_usage_tracking() {
        let manager = TelemetryManager::new();
        let mut event_data = HashMap::new();
        event_data.insert("url".to_string(), "https://example.com".to_string());
        
        manager.track_usage("page_visit", event_data, Some(5000)).unwrap();
        
        if let Ok(usage_stats) = manager.usage_stats.lock() {
            assert_eq!(usage_stats.len(), 1);
            assert_eq!(usage_stats[0].event_type, "page_visit");
        }
    }

    #[test]
    fn test_performance_metrics() {
        let manager = TelemetryManager::new();
        
        manager.record_performance(100.0, 10.0, 15.0, 500.0, 1500.0).unwrap();
        
        let summary = manager.get_performance_summary().unwrap();
        assert_eq!(summary.get("avg_memory_mb"), Some(&100.0));
        assert_eq!(summary.get("avg_cpu_percent"), Some(&10.0));
    }

    #[test]
    fn test_security_alerts() {
        let manager = TelemetryManager::new();
        
        manager.add_security_alert(
            SecuritySeverity::High,
            "certificate_error",
            "Invalid SSL certificate detected",
            vec!["network_module".to_string()],
            vec!["Update certificates".to_string()],
        ).unwrap();
        
        if let Ok(alerts) = manager.security_alerts.lock() {
            assert_eq!(alerts.len(), 1);
            assert_eq!(alerts[0].alert_type, "certificate_error");
        }
    }

    #[tokio::test]
    async fn test_update_check() {
        let manager = TelemetryManager::new();
        
        manager.check_for_updates().await.unwrap();
        
        if let Ok(update_info) = manager.update_info.lock() {
            assert!(update_info.is_some());
        }
    }
}
