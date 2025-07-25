use std::sync::atomic::{AtomicU32, AtomicBool, Ordering};
use std::time::{Duration, Instant};
use parking_lot::Mutex;
use prometheus::{Registry, IntGauge};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    Closed = 0,
    HalfOpen = 1,
    Open = 2,
}

#[derive(Debug)]
pub struct CircuitBreaker {
    name: &'static str,
    failure_threshold: u32,
    reset_timeout: Duration,
    failures: AtomicU32,
    last_failure: Mutex<Option<Instant>>,
    is_open: AtomicBool,
    is_half_open: AtomicBool,
    state_metric: IntGauge,
}

impl CircuitBreaker {
    pub fn new(
        failure_threshold: u32,
        reset_timeout: Duration,
        registry: &Registry,
        name: &'static str,
    ) -> Self {
        let state_metric = IntGauge::new(
            format!("circuit_breaker_{}_state", name),
            format!("State of the {} circuit breaker (0=Closed, 1=HalfOpen, 2=Open)", name),
        ).unwrap();
        
        registry.register(Box::new(state_metric.clone())).unwrap();
        state_metric.set(CircuitState::Closed as i64);
        
        Self {
            name,
            failure_threshold,
            reset_timeout,
            failures: AtomicU32::new(0),
            last_failure: Mutex::new(None),
            is_open: AtomicBool::new(false),
            is_half_open: AtomicBool::new(false),
            state_metric,
        }
    }
    
    pub fn success(&self) {
        self.failures.store(0, Ordering::SeqCst);
        self.is_open.store(false, Ordering::SeqCst);
        self.is_half_open.store(false, Ordering::SeqCst);
        self.state_metric.set(CircuitState::Closed as i64);
    }
    
    pub fn failure(&self) -> bool {
        let failures = self.failures.fetch_add(1, Ordering::SeqCst) + 1;
        let mut last_failure = self.last_failure.lock();
        *last_failure = Some(Instant::now());
        
        if failures >= self.failure_threshold {
            self.is_open.store(true, Ordering::SeqCst);
            self.state_metric.set(CircuitState::Open as i64);
            true
        } else {
            false
        }
    }
    
    pub fn is_blocked(&self) -> bool {
        if self.is_closed() {
            return false;
        }
        
        if self.is_open() {
            let last_failure = self.last_failure.lock();
            if let Some(last) = *last_failure {
                if last.elapsed() >= self.reset_timeout {
                    drop(last_failure);
                    self.is_half_open.store(true, Ordering::SeqCst);
                    self.is_open.store(false, Ordering::SeqCst);
                    self.state_metric.set(CircuitState::HalfOpen as i64);
                    return false;
                }
            }
            return true;
        }
        
        false
    }
    
    pub fn state(&self) -> CircuitState {
        if self.is_open() {
            CircuitState::Open
        } else if self.is_half_open() {
            CircuitState::HalfOpen
        } else {
            CircuitState::Closed
        }
    }
    
    pub fn failure_count(&self) -> u32 {
        self.failures.load(Ordering::SeqCst)
    }
    
    pub fn is_closed(&self) -> bool {
        !self.is_open() && !self.is_half_open()
    }
    
    pub fn is_half_open(&self) -> bool {
        self.is_half_open.load(Ordering::SeqCst)
    }
    
    pub fn is_open(&self) -> bool {
        self.is_open.load(Ordering::SeqCst)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;
    use std::thread;
    
    fn create_test_breaker() -> (Arc<CircuitBreaker>, Registry) {
        let registry = Registry::new();
        let breaker = Arc::new(CircuitBreaker::new(
            3, 
            Duration::from_millis(100), 
            &registry,
            "test"
        ));
        (breaker, registry)
    }
    
    #[test]
    fn test_initial_state() {
        let (cb, _) = create_test_breaker();
        assert_eq!(cb.state(), CircuitState::Closed);
        assert_eq!(cb.failure_count(), 0);
        assert!(!cb.is_blocked());
    }
    
    #[test]
    fn test_opens_after_threshold() {
        let (cb, _) = create_test_breaker();
        
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
    fn test_reset_after_timeout() {
        let (cb, _) = create_test_breaker();
        
        // Open the circuit
        cb.failure();
        cb.failure();
        cb.failure();
        
        // Should be open
        assert_eq!(cb.state(), CircuitState::Open);
        
        // Wait for reset timeout
        std::thread::sleep(Duration::from_millis(150));
        
        // Should transition to half-open
        assert!(!cb.is_blocked());
        assert_eq!(cb.state(), CircuitState::HalfOpen);
    }
    
    #[test]
    fn test_success_resets_state() {
        let (cb, _) = create_test_breaker();
        
        // Add some failures
        cb.failure();
        cb.failure();
        
        // Success should reset the counter
        cb.success();
        assert_eq!(cb.failure_count(), 0);
        assert_eq!(cb.state(), CircuitState::Closed);
    }
    
    #[test]
    fn test_half_open_to_closed() {
        let (cb, _) = create_test_breaker();
        
        // Open the circuit
        cb.failure();
        cb.failure();
        cb.failure();
        
        // Wait for half-open
        std::thread::sleep(Duration::from_millis(150));
        cb.is_blocked(); // Triggers transition to half-open
        
        // Success should close the circuit
        cb.success();
        assert_eq!(cb.state(), CircuitState::Closed);
    }
    
    #[test]
    fn test_half_open_to_open() {
        let (cb, _) = create_test_breaker();
        
        // Open the circuit
        cb.failure();
        cb.failure();
        cb.failure();
        
        // Wait for half-open
        std::thread::sleep(Duration::from_millis(150));
        cb.is_blocked(); // Triggers transition to half-open
        
        // Another failure should re-open the circuit
        assert!(cb.failure());
        assert_eq!(cb.state(), CircuitState::Open);
    }
    
    #[test]
    fn test_concurrent_access() {
        let (cb, _) = create_test_breaker();
        let cb = Arc::new(cb);
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
    fn test_metrics() {
        let (cb, registry) = create_test_breaker();
        
        // Check initial state
        let metric = registry.gather();
        let state_metric = metric.iter()
            .find(|m| m.get_name() == "circuit_breaker_test_state")
            .unwrap();
        assert_eq!(state_metric.get_metric()[0].get_gauge().get_value(), CircuitState::Closed as f64);
        
        // After failure
        cb.failure();
        let metric = registry.gather();
        let state_metric = metric.iter()
            .find(|m| m.get_name() == "circuit_breaker_test_state")
            .unwrap();
        assert_eq!(state_metric.get_metric()[0].get_gauge().get_value(), CircuitState::Closed as f64);
        
        // After opening
        cb.failure();
        cb.failure();
        let metric = registry.gather();
        let state_metric = metric.iter()
            .find(|m| m.get_name() == "circuit_breaker_test_state")
            .unwrap();
        assert_eq!(state_metric.get_metric()[0].get_gauge().get_value(), CircuitState::Open as f64);
    }
}
