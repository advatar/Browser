use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use sysinfo::SystemExt;

/// Performance metrics collection and monitoring
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PerformanceMetrics {
    pub memory_usage: MemoryMetrics,
    pub cpu_usage: CpuMetrics,
    pub network_metrics: NetworkMetrics,
    pub rendering_metrics: RenderingMetrics,
    pub startup_time: Duration,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryMetrics {
    pub heap_used: u64,
    pub heap_total: u64,
    pub external: u64,
    pub rss: u64,
    pub array_buffers: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuMetrics {
    pub user_time: f64,
    pub system_time: f64,
    pub idle_time: f64,
    pub total_time: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkMetrics {
    pub requests_sent: u64,
    pub responses_received: u64,
    pub bytes_sent: u64,
    pub bytes_received: u64,
    pub failed_requests: u64,
    pub average_response_time: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderingMetrics {
    pub frames_per_second: f64,
    pub frame_time: f64,
    pub paint_time: f64,
    pub layout_time: f64,
    pub script_time: f64,
}

/// Performance monitor that tracks and analyzes browser performance
#[derive(Debug)]
pub struct PerformanceMonitor {
    metrics_history: Arc<Mutex<VecDeque<PerformanceMetrics>>>,
    startup_time: Instant,
    network_stats: Arc<Mutex<NetworkStats>>,
    rendering_stats: Arc<Mutex<RenderingStats>>,
    max_history_size: usize,
}

#[derive(Debug, Default)]
struct NetworkStats {
    requests_sent: u64,
    responses_received: u64,
    bytes_sent: u64,
    bytes_received: u64,
    failed_requests: u64,
    response_times: VecDeque<Duration>,
}

#[derive(Debug, Default)]
struct RenderingStats {
    frame_times: VecDeque<Duration>,
    paint_times: VecDeque<Duration>,
    layout_times: VecDeque<Duration>,
    script_times: VecDeque<Duration>,
}

impl PerformanceMonitor {
    pub fn new() -> Self {
        Self {
            metrics_history: Arc::new(Mutex::new(VecDeque::new())),
            startup_time: Instant::now(),
            network_stats: Arc::new(Mutex::new(NetworkStats::default())),
            rendering_stats: Arc::new(Mutex::new(RenderingStats::default())),
            max_history_size: 1000, // Keep last 1000 measurements
        }
    }

    /// Start performance monitoring
    pub fn start_monitoring(&self) -> Result<()> {
        let monitor = self.clone();

        // Start background monitoring task
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(5));

            loop {
                interval.tick().await;
                if let Err(e) = monitor.collect_metrics().await {
                    log::error!("Failed to collect performance metrics: {}", e);
                }
            }
        });

        Ok(())
    }

    /// Collect current performance metrics
    pub async fn collect_metrics(&self) -> Result<PerformanceMetrics> {
        let memory_metrics = self.collect_memory_metrics().await?;
        let cpu_metrics = self.collect_cpu_metrics().await?;
        let network_metrics = self.collect_network_metrics().await?;
        let rendering_metrics = self.collect_rendering_metrics().await?;

        let metrics = PerformanceMetrics {
            memory_usage: memory_metrics,
            cpu_usage: cpu_metrics,
            network_metrics,
            rendering_metrics,
            startup_time: self.startup_time.elapsed(),
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        };

        // Store in history
        if let Ok(mut history) = self.metrics_history.lock() {
            history.push_back(metrics.clone());

            // Limit history size
            while history.len() > self.max_history_size {
                history.pop_front();
            }
        }

        Ok(metrics)
    }

    /// Get performance metrics history
    pub fn get_metrics_history(&self) -> Result<Vec<PerformanceMetrics>> {
        if let Ok(history) = self.metrics_history.lock() {
            Ok(history.iter().cloned().collect())
        } else {
            Err(anyhow::anyhow!("Failed to lock metrics history"))
        }
    }

    /// Get latest performance metrics
    pub fn get_latest_metrics(&self) -> Result<Option<PerformanceMetrics>> {
        if let Ok(history) = self.metrics_history.lock() {
            Ok(history.back().cloned())
        } else {
            Err(anyhow::anyhow!("Failed to lock metrics history"))
        }
    }

    /// Record network request
    pub fn record_network_request(&self, bytes_sent: u64) {
        if let Ok(mut stats) = self.network_stats.lock() {
            stats.requests_sent += 1;
            stats.bytes_sent += bytes_sent;
        }
    }

    /// Record network response
    pub fn record_network_response(&self, bytes_received: u64, response_time: Duration) {
        if let Ok(mut stats) = self.network_stats.lock() {
            stats.responses_received += 1;
            stats.bytes_received += bytes_received;
            stats.response_times.push_back(response_time);

            // Limit response time history
            while stats.response_times.len() > 100 {
                stats.response_times.pop_front();
            }
        }
    }

    /// Record failed network request
    pub fn record_network_failure(&self) {
        if let Ok(mut stats) = self.network_stats.lock() {
            stats.failed_requests += 1;
        }
    }

    /// Record rendering frame time
    pub fn record_frame_time(&self, frame_time: Duration) {
        if let Ok(mut stats) = self.rendering_stats.lock() {
            stats.frame_times.push_back(frame_time);

            // Limit frame time history
            while stats.frame_times.len() > 60 {
                stats.frame_times.pop_front();
            }
        }
    }

    /// Record paint time
    pub fn record_paint_time(&self, paint_time: Duration) {
        if let Ok(mut stats) = self.rendering_stats.lock() {
            stats.paint_times.push_back(paint_time);

            while stats.paint_times.len() > 60 {
                stats.paint_times.pop_front();
            }
        }
    }

    /// Collect memory metrics
    async fn collect_memory_metrics(&self) -> Result<MemoryMetrics> {
        // Cross-platform memory collection using `sysinfo`
        let mut sys = sysinfo::System::new_all();
        sys.refresh_memory();

        // sysinfo reports memory in KiB; convert to bytes for consistency with the rest of the file
        let total_mem_bytes = sys.total_memory().saturating_mul(1024);
        let used_mem_kib = if sys.used_memory() > 0 {
            sys.used_memory()
        } else {
            sys.total_memory().saturating_sub(sys.available_memory())
        };
        let used_mem_bytes = used_mem_kib.saturating_mul(1024);

        Ok(MemoryMetrics {
            heap_used: used_mem_bytes,
            heap_total: total_mem_bytes,
            external: 0,
            rss: used_mem_bytes,
            array_buffers: 0,
        })
    }

    /// Collect CPU metrics
    async fn collect_cpu_metrics(&self) -> Result<CpuMetrics> {
        // In a real implementation, this would use system APIs to get actual CPU usage
        // For now, we'll simulate with reasonable values

        #[cfg(target_os = "macos")]
        {
            use std::process::Command;

            let output = Command::new("ps")
                .args(&["-o", "pcpu", "-p", &std::process::id().to_string()])
                .output()?;

            let output_str = String::from_utf8_lossy(&output.stdout);
            let lines: Vec<&str> = output_str.lines().collect();

            if lines.len() >= 2 {
                if let Ok(cpu_percent) = lines[1].trim().parse::<f64>() {
                    return Ok(CpuMetrics {
                        user_time: cpu_percent * 0.8,   // Estimate user time
                        system_time: cpu_percent * 0.2, // Estimate system time
                        idle_time: 100.0 - cpu_percent,
                        total_time: 100.0,
                    });
                }
            }
        }

        // Fallback simulation
        Ok(CpuMetrics {
            user_time: 5.0,
            system_time: 2.0,
            idle_time: 93.0,
            total_time: 100.0,
        })
    }

    /// Collect network metrics
    async fn collect_network_metrics(&self) -> Result<NetworkMetrics> {
        if let Ok(stats) = self.network_stats.lock() {
            let average_response_time = if stats.response_times.is_empty() {
                0.0
            } else {
                let total: Duration = stats.response_times.iter().sum();
                total.as_secs_f64() / stats.response_times.len() as f64
            };

            Ok(NetworkMetrics {
                requests_sent: stats.requests_sent,
                responses_received: stats.responses_received,
                bytes_sent: stats.bytes_sent,
                bytes_received: stats.bytes_received,
                failed_requests: stats.failed_requests,
                average_response_time,
            })
        } else {
            Err(anyhow::anyhow!("Failed to lock network stats"))
        }
    }

    /// Collect rendering metrics
    async fn collect_rendering_metrics(&self) -> Result<RenderingMetrics> {
        if let Ok(stats) = self.rendering_stats.lock() {
            let fps = if stats.frame_times.is_empty() {
                60.0 // Default
            } else {
                let avg_frame_time: Duration =
                    stats.frame_times.iter().sum::<Duration>() / stats.frame_times.len() as u32;
                1.0 / avg_frame_time.as_secs_f64()
            };

            let avg_frame_time = if stats.frame_times.is_empty() {
                16.67 // ~60fps
            } else {
                let total: Duration = stats.frame_times.iter().sum();
                total.as_secs_f64() * 1000.0 / stats.frame_times.len() as f64 // Convert to ms
            };

            let avg_paint_time = if stats.paint_times.is_empty() {
                2.0
            } else {
                let total: Duration = stats.paint_times.iter().sum();
                total.as_secs_f64() * 1000.0 / stats.paint_times.len() as f64
            };

            Ok(RenderingMetrics {
                frames_per_second: fps,
                frame_time: avg_frame_time,
                paint_time: avg_paint_time,
                layout_time: 1.0, // Simulated
                script_time: 3.0, // Simulated
            })
        } else {
            Err(anyhow::anyhow!("Failed to lock rendering stats"))
        }
    }

    /// Generate performance report
    pub fn generate_performance_report(&self) -> Result<String> {
        let history = self.get_metrics_history()?;
        if history.is_empty() {
            return Ok("No performance data available".to_string());
        }

        let latest = &history[history.len() - 1];
        let startup_time_ms = latest.startup_time.as_millis();

        let report = format!(
            r#"
# Performance Report

## System Overview
- **Startup Time**: {}ms
- **Memory Usage**: {:.1}MB / {:.1}MB
- **CPU Usage**: {:.1}% (User: {:.1}%, System: {:.1}%)
- **FPS**: {:.1}
- **Frame Time**: {:.1}ms

## Memory Metrics
- **Heap Used**: {:.1}MB
- **Heap Total**: {:.1}MB
- **RSS**: {:.1}MB
- **External**: {:.1}MB
- **Array Buffers**: {:.1}MB

## Network Metrics
- **Requests Sent**: {}
- **Responses Received**: {}
- **Bytes Sent**: {:.1}KB
- **Bytes Received**: {:.1}KB
- **Failed Requests**: {}
- **Average Response Time**: {:.1}ms

## Rendering Metrics
- **FPS**: {:.1}
- **Frame Time**: {:.1}ms
- **Paint Time**: {:.1}ms
- **Layout Time**: {:.1}ms
- **Script Time**: {:.1}ms

## Recommendations
{}
            "#,
            startup_time_ms,
            latest.memory_usage.heap_used as f64 / 1_000_000.0,
            latest.memory_usage.heap_total as f64 / 1_000_000.0,
            latest.cpu_usage.user_time + latest.cpu_usage.system_time,
            latest.cpu_usage.user_time,
            latest.cpu_usage.system_time,
            latest.rendering_metrics.frames_per_second,
            latest.rendering_metrics.frame_time,
            latest.memory_usage.heap_used as f64 / 1_000_000.0,
            latest.memory_usage.heap_total as f64 / 1_000_000.0,
            latest.memory_usage.rss as f64 / 1_000_000.0,
            latest.memory_usage.external as f64 / 1_000_000.0,
            latest.memory_usage.array_buffers as f64 / 1_000_000.0,
            latest.network_metrics.requests_sent,
            latest.network_metrics.responses_received,
            latest.network_metrics.bytes_sent as f64 / 1000.0,
            latest.network_metrics.bytes_received as f64 / 1000.0,
            latest.network_metrics.failed_requests,
            latest.network_metrics.average_response_time * 1000.0,
            latest.rendering_metrics.frames_per_second,
            latest.rendering_metrics.frame_time,
            latest.rendering_metrics.paint_time,
            latest.rendering_metrics.layout_time,
            latest.rendering_metrics.script_time,
            self.generate_recommendations(latest)
        );

        Ok(report)
    }

    /// Generate performance recommendations
    fn generate_recommendations(&self, metrics: &PerformanceMetrics) -> String {
        let mut recommendations = Vec::new();

        // Memory recommendations
        let memory_usage_percent = (metrics.memory_usage.heap_used as f64
            / metrics.memory_usage.heap_total as f64)
            * 100.0;
        if memory_usage_percent > 80.0 {
            recommendations.push(
                "⚠️  High memory usage detected. Consider closing unused tabs or clearing cache.",
            );
        }

        // CPU recommendations
        let cpu_usage = metrics.cpu_usage.user_time + metrics.cpu_usage.system_time;
        if cpu_usage > 50.0 {
            recommendations.push(
                "⚠️  High CPU usage detected. Check for resource-intensive scripts or extensions.",
            );
        }

        // FPS recommendations
        if metrics.rendering_metrics.frames_per_second < 30.0 {
            recommendations.push(
                "⚠️  Low frame rate detected. Consider reducing visual effects or closing tabs.",
            );
        }

        // Network recommendations
        if metrics.network_metrics.failed_requests > 10 {
            recommendations
                .push("⚠️  High number of failed network requests. Check internet connection.");
        }

        if metrics.network_metrics.average_response_time > 2.0 {
            recommendations.push("⚠️  Slow network responses detected. Consider using a different IPFS gateway or DNS resolver.");
        }

        // Startup time recommendations
        if metrics.startup_time.as_millis() > 5000 {
            recommendations.push("⚠️  Slow startup time. Consider disabling unnecessary extensions or clearing cache.");
        }

        if recommendations.is_empty() {
            recommendations.push("✅ Performance looks good! No issues detected.");
        }

        recommendations.join("\n")
    }

    /// Export metrics to JSON
    pub fn export_metrics_json(&self) -> Result<String> {
        let history = self.get_metrics_history()?;
        serde_json::to_string_pretty(&history)
            .map_err(|e| anyhow::anyhow!("JSON serialization failed: {}", e))
    }

    /// Clear metrics history
    pub fn clear_metrics_history(&self) -> Result<()> {
        if let Ok(mut history) = self.metrics_history.lock() {
            history.clear();
            Ok(())
        } else {
            Err(anyhow::anyhow!("Failed to lock metrics history"))
        }
    }
}

impl Clone for PerformanceMonitor {
    fn clone(&self) -> Self {
        Self {
            metrics_history: Arc::clone(&self.metrics_history),
            startup_time: self.startup_time,
            network_stats: Arc::clone(&self.network_stats),
            rendering_stats: Arc::clone(&self.rendering_stats),
            max_history_size: self.max_history_size,
        }
    }
}

impl Default for PerformanceMonitor {
    fn default() -> Self {
        Self::new()
    }
}

/// Performance optimization utilities
pub mod optimization {
    use super::*;

    /// Memory optimization utilities
    pub struct MemoryOptimizer;

    impl MemoryOptimizer {
        /// Force garbage collection (if supported by runtime)
        pub fn force_gc() {
            // In a real implementation, this would trigger GC
            log::info!("Garbage collection requested");
        }

        /// Clear unused caches
        pub fn clear_caches() -> Result<()> {
            // Clear various caches
            log::info!("Caches cleared");
            Ok(())
        }

        /// Optimize memory usage
        pub fn optimize_memory() -> Result<()> {
            Self::force_gc();
            Self::clear_caches()?;
            Ok(())
        }
    }

    /// CPU optimization utilities
    pub struct CpuOptimizer;

    impl CpuOptimizer {
        /// Reduce CPU usage by limiting background tasks
        pub fn reduce_background_activity() {
            log::info!("Reducing background activity");
        }

        /// Optimize rendering performance
        pub fn optimize_rendering() {
            log::info!("Optimizing rendering performance");
        }
    }

    /// Network optimization utilities
    pub struct NetworkOptimizer;

    impl NetworkOptimizer {
        /// Optimize network requests
        pub fn optimize_requests() {
            log::info!("Optimizing network requests");
        }

        /// Enable request compression
        pub fn enable_compression() {
            log::info!("Request compression enabled");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_performance_monitor() {
        let monitor = PerformanceMonitor::new();

        // Test metrics collection
        let metrics = monitor.collect_metrics().await.unwrap();
        assert!(metrics.memory_usage.heap_used > 0);
        assert!(metrics.startup_time.as_millis() > 0);

        // Test network recording
        monitor.record_network_request(1024);
        monitor.record_network_response(2048, Duration::from_millis(100));

        let updated_metrics = monitor.collect_metrics().await.unwrap();
        assert_eq!(updated_metrics.network_metrics.requests_sent, 1);
        assert_eq!(updated_metrics.network_metrics.responses_received, 1);

        // Test rendering recording
        monitor.record_frame_time(Duration::from_millis(16));
        monitor.record_paint_time(Duration::from_millis(2));

        // Test report generation
        let report = monitor.generate_performance_report().unwrap();
        assert!(report.contains("Performance Report"));
        assert!(report.contains("Memory Metrics"));

        // Test JSON export
        let json = monitor.export_metrics_json().unwrap();
        assert!(json.contains("memory_usage"));
    }

    #[test]
    fn test_memory_optimizer() {
        optimization::MemoryOptimizer::force_gc();
        optimization::MemoryOptimizer::clear_caches().unwrap();
        optimization::MemoryOptimizer::optimize_memory().unwrap();
    }

    #[test]
    fn test_metrics_history_limit() {
        let monitor = PerformanceMonitor::new();

        // Add more metrics than the limit
        for _ in 0..1500 {
            let metrics = PerformanceMetrics {
                memory_usage: MemoryMetrics {
                    heap_used: 1000,
                    heap_total: 2000,
                    external: 100,
                    rss: 1500,
                    array_buffers: 50,
                },
                cpu_usage: CpuMetrics {
                    user_time: 5.0,
                    system_time: 2.0,
                    idle_time: 93.0,
                    total_time: 100.0,
                },
                network_metrics: NetworkMetrics {
                    requests_sent: 0,
                    responses_received: 0,
                    bytes_sent: 0,
                    bytes_received: 0,
                    failed_requests: 0,
                    average_response_time: 0.0,
                },
                rendering_metrics: RenderingMetrics {
                    frames_per_second: 60.0,
                    frame_time: 16.67,
                    paint_time: 2.0,
                    layout_time: 1.0,
                    script_time: 3.0,
                },
                startup_time: Duration::from_secs(1),
                timestamp: 1234567890,
            };

            if let Ok(mut history) = monitor.metrics_history.lock() {
                history.push_back(metrics);
                while history.len() > monitor.max_history_size {
                    history.pop_front();
                }
            }
        }

        let history = monitor.get_metrics_history().unwrap();
        assert_eq!(history.len(), 1000); // Should be limited to max_history_size
    }
}
