use std::sync::Arc;
use std::time::Duration;
use prometheus::Registry;
use crate::bitswap::circuit_breaker::{CircuitBreaker, CircuitState};
use crate::bitswap::metrics::BitswapMetrics;

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
    std::thread::sleep(Duration::from_millis(150));
    
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
    std::thread::sleep(Duration::from_millis(60));
    
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
    std::thread::sleep(Duration::from_millis(60));
    
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
        let handle = std::thread::spawn(move || {
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
    std::thread::sleep(Duration::from_millis(60));
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
