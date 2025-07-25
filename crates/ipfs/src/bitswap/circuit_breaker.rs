use std::sync::atomic::{AtomicU32, AtomicBool, Ordering};
use std::time::{Duration, Instant};
use libp2p::PeerId;
use prometheus::{IntCounter, IntGauge, IntCounterVec, IntGaugeVec, Registry};
use crate::bitswap::metrics::BitswapMetrics;

/// Tracks the state of a circuit breaker
#[derive(Debug)]
pub(crate) struct CircuitBreaker {
    /// Name of the circuit (used for metrics)
    name: &'static str,
    /// Number of consecutive failures before opening the circuit
    failure_threshold: u32,
    /// Duration to keep the circuit open before attempting to close it
    reset_timeout: Duration,
    /// Current failure count
    failures: AtomicU32,
    /// When the circuit was last opened
    last_failure: parking_lot::Mutex<Option<Instant>>,
    /// Whether the circuit is currently open
    is_open: AtomicBool,
    /// Whether the circuit is in half-open state
    is_half_open: AtomicBool,
    /// Reference to the metrics
    metrics: BitswapMetrics,
}

/// Represents the state of a circuit breaker
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CircuitState {
    Closed = 0,
    HalfOpen = 1,
    Open = 2,
}

impl CircuitBreaker {
    /// Creates a new circuit breaker with the given configuration
    pub fn new(
        failure_threshold: u32,
        reset_timeout: Duration,
        metrics: BitswapMetrics,
        name: &'static str,
    ) -> Self {
        // Initialize the circuit state in metrics
        metrics.circuit_state.with_label_values(&[name]).set(CircuitState::Closed as i64);
        
        Self {
            name,
            failure_threshold,
            reset_timeout,
            failures: AtomicU32::new(0),
            last_failure: parking_lot::Mutex::new(None),
            is_open: AtomicBool::new(false),
            is_half_open: AtomicBool::new(false),
            metrics,
        }
    }

    /// Records a successful operation and resets the failure count
    pub fn success(&self) {
        self.failures.store(0, Ordering::SeqCst);
        
        if self.is_open.load(Ordering::SeqCst) || self.is_half_open.load(Ordering::SeqCst) {
            // If we were open or half-open, we can close the circuit
            self.is_open.store(false, Ordering::SeqCst);
            self.is_half_open.store(false, Ordering::SeqCst);
            self.metrics.circuit_closed.with_label_values(&[self.name]).inc();
            self.metrics.circuit_state.with_label_values(&[self.name]).set(CircuitState::Closed as i64);
        }
    }

    /// Records a failed operation and updates the circuit state
    pub fn failure(&self) -> bool {
        let failures = self.failures.fetch_add(1, Ordering::SeqCst) + 1;
        
        // Update failure counter in metrics
        self.metrics.circuit_failures.with_label_values(&[self.name]).inc();
        
        if failures >= self.failure_threshold {
            let now = Instant::now();
            let mut last_failure = self.last_failure.lock();
            
            // Only update if we're not already open or if the reset timeout has passed
            if !self.is_open.load(Ordering::SeqCst) || 
               last_failure.map_or(true, |t| now.duration_since(t) >= self.reset_timeout) 
            {
                *last_failure = Some(now);
                let was_open = self.is_open.load(Ordering::SeqCst);
                self.is_open.store(true, Ordering::SeqCst);
                self.is_half_open.store(false, Ordering::SeqCst);
                
                if !was_open {
                    // Only increment the counter if we're transitioning from closed to open
                    self.metrics.circuit_opened.with_label_values(&[self.name]).inc();
                }
                
                self.metrics.circuit_state.with_label_values(&[self.name]).set(CircuitState::Open as i64);
                return true;
            }
        }
        false
    }

    /// Checks if the circuit is open and should block the operation
    pub fn is_blocked(&self) -> bool {
        if !self.is_open.load(Ordering::SeqCst) {
            return false;
        }

        // Check if we should transition to half-open
        if let Some(last_failure) = *self.last_failure.lock() {
            let now = Instant::now();
            if now.duration_since(last_failure) >= self.reset_timeout {
                // Try to transition to half-open state
                if self.is_half_open.compare_exchange(
                    false, 
                    true,
                    Ordering::SeqCst,
                    Ordering::Relaxed
                ).is_ok() {
                    self.metrics.circuit_state.with_label_values(&[self.name]).set(CircuitState::HalfOpen as i64);
                }
                return false;
            }
        }

        // Circuit is open and not ready to transition to half-open
        self.metrics.requests_rejected.with_label_values(&[self.name]).inc();
        true
    }
    
    /// Returns the current state of the circuit breaker
    pub fn state(&self) -> CircuitState {
        if self.is_open.load(Ordering::SeqCst) {
            if self.is_half_open.load(Ordering::SeqCst) {
                CircuitState::HalfOpen
            } else {
                CircuitState::Open
            }
        } else {
            CircuitState::Closed
        }
    }
    
    /// Returns the number of consecutive failures
    pub fn failure_count(&self) -> u32 {
        self.failures.load(Ordering::SeqCst)
    }
    
    /// Returns the time since the last failure, or None if there were no failures
    fn time_since_last_failure(&self) -> Option<Duration> {
        self.last_failure.lock().map(|t| t.elapsed())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::thread;

    // Helper function to create a test metrics instance
    fn create_test_metrics() -> BitswapMetrics {
        let registry = Registry::new();
        BitswapMetrics::new(&registry).expect("Failed to create test metrics")
    }

    #[test]
    fn test_circuit_initial_state() {
        let metrics = create_test_metrics();
        let cb = CircuitBreaker::new(3, Duration::from_secs(1), metrics, "test");
        
        assert_eq!(cb.state(), CircuitState::Closed);
        assert_eq!(cb.failure_count(), 0);
        assert!(!cb.is_blocked());
    }

    #[test]
    fn test_circuit_opens_after_threshold() {
        let metrics = create_test_metrics();
        let cb = Arc::new(CircuitBreaker::new(3, Duration::from_secs(1), metrics, "test"));
        
        // First two failures should not open the circuit
        assert!(!cb.failure());
        assert!(!cb.failure());
        assert_eq!(cb.failure_count(), 2);
        assert_eq!(cb.state(), CircuitState::Closed);
        
        // Third failure should open the circuit
        assert!(cb.failure());
        assert_eq!(cb.state(), CircuitState::Open);
        assert!(cb.is_blocked());
    }

    #[test]
    fn test_circuit_reset_after_timeout() {
        let metrics = create_test_metrics();
        let cb = Arc::new(CircuitBreaker::new(3, Duration::from_millis(100), metrics, "test"));
        
        // Open the circuit
        for _ in 0..3 {
            cb.failure();
        }
        assert_eq!(cb.state(), CircuitState::Open);
        
        // Wait for reset timeout
        thread::sleep(Duration::from_millis(150));
        
        // Should be in half-open state
        assert!(!cb.is_blocked());
        assert_eq!(cb.state(), CircuitState::HalfOpen);
    }

    #[test]
    fn test_success_resets_failure_count() {
        let metrics = create_test_metrics();
        let cb = Arc::new(CircuitBreaker::new(3, Duration::from_secs(1), metrics, "test"));
        
        // Add some failures
        cb.failure();
        cb.failure();
        assert_eq!(cb.failure_count(), 2);
        
        // Success should reset the counter
        cb.success();
        assert_eq!(cb.failure_count(), 0);
        assert_eq!(cb.state(), CircuitState::Closed);
    }

    #[test]
    fn test_half_open_to_closed_on_success() {
        let metrics = create_test_metrics();
        let cb = Arc::new(CircuitBreaker::new(3, Duration::from_millis(50), metrics, "test"));
        
        // Open the circuit
        for _ in 0..3 { cb.failure(); }
        
        // Wait for half-open
        thread::sleep(Duration::from_millis(60));
        
        // Should be in half-open state
        assert!(!cb.is_blocked());
        
        // Success should close the circuit
        cb.success();
        assert_eq!(cb.state(), CircuitState::Closed);
        
        // Should be able to fail again
        assert!(!cb.failure());
    }

    #[test]
    fn test_half_open_back_to_open_on_failure() {
        let metrics = create_test_metrics();
        let cb = Arc::new(CircuitBreaker::new(2, Duration::from_millis(50), metrics, "test"));
        
        // Open the circuit
        cb.failure();
        cb.failure();
        
        // Wait for half-open
        thread::sleep(Duration::from_millis(60));
        
        // Should be in half-open state
        assert!(!cb.is_blocked());
        
        // Another failure should re-open the circuit
        assert!(cb.failure());
        assert_eq!(cb.state(), CircuitState::Open);
        assert!(cb.is_blocked());
    }

    #[test]
    fn test_concurrent_access() {
        let metrics = create_test_metrics();
        let cb = Arc::new(CircuitBreaker::new(100, Duration::from_secs(1), metrics, "test"));
        let mut handles = vec![];
        
        // Spawn multiple threads to increment failure count
        for _ in 0..10 {
            let cb_clone = cb.clone();
            let handle = thread::spawn(move || {
                for _ in 0..10 {
                    cb_clone.failure();
                }
            });
            handles.push(handle);
        }
        
        // Wait for all threads to complete
        for handle in handles {
            handle.join().unwrap();
        }
        
        // Should have 100 failures total
        assert_eq!(cb.failure_count(), 100);
        assert_eq!(cb.state(), CircuitState::Open);
    }

    #[test]
    fn test_metrics_updates() {
        let metrics = create_test_metrics();
        let cb = CircuitBreaker::new(2, Duration::from_millis(50), metrics.clone(), "test_metrics");
        
        // Initial state
        assert_eq!(
            metrics.circuit_state.with_label_values(&["test_metrics"]).get(),
            CircuitState::Closed as i64
        );
        
        // After one failure
        cb.failure();
        assert_eq!(
            metrics.circuit_state.with_label_values(&["test_metrics"]).get(),
            CircuitState::Closed as i64
        );
        
        // After second failure (should open)
        cb.failure();
        assert_eq!(
            metrics.circuit_state.with_label_values(&["test_metrics"]).get(),
            CircuitState::Open as i64
        );
        
        // After reset timeout
        thread::sleep(Duration::from_millis(60));
        assert!(!cb.is_blocked()); // Triggers half-open state
        assert_eq!(
            metrics.circuit_state.with_label_values(&["test_metrics"]).get(),
            CircuitState::HalfOpen as i64
        );
        
        // After success
        cb.success();
        assert_eq!(
            metrics.circuit_state.with_label_values(&["test_metrics"]).get(),
            CircuitState::Closed as i64
        );
    }
}
