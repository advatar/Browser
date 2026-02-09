use anyhow::Result;
use cid::Cid;
use libp2p_bitswap::{
    Bitswap, BitswapConfig as Libp2pBitswapConfig, BitswapEvent, BitswapMessage, Block, Priority, Stats,
    protocol::{Message as BitswapMessageProto, wantlist::WantType}
};
use libp2p_core::{Multiaddr, PeerId};
use libp2p_swarm::{Swarm, SwarmEvent};
use prometheus::{self, IntCounter, IntGauge, IntCounterVec, IntGaugeVec, Opts};
use std::collections::{BTreeMap, HashMap, HashSet, VecDeque};
use std::sync::atomic::{AtomicU64, AtomicUsize, AtomicI32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use crate::bitswap::circuit_breaker::{CircuitBreaker, CircuitState};
use std::cmp::Reverse;
use std::ops::AddAssign;
use std::hash::Hash;
use tokio::sync::mpsc;
use tokio::time::{timeout, sleep};
use futures::future::{FutureExt, BoxFuture};
use prost::Message as _;
use std::future::Future;
use std::pin::Pin;
use std::task::Poll;
use std::time::SystemTime;

use crate::NodeEvent;

/// Bitswap protocol implementation for IPFS block exchange.
/// 
/// This module provides the Bitswap protocol implementation that handles:
/// - Block exchange between peers
/// - Wantlist management
/// - Block accounting and debt management
/// - Peer prioritization
/// Bitswap protocol service for the IPFS node.
/// 
/// Handles block exchange between peers using the Bitswap protocol.
/// Protocol version constants
const BITSWAP_120: &[u8] = b"/ipfs/bitswap/1.2.0";
const BITSWAP_110: &[u8] = b"/ipfs/bitswap/1.1.0";
const BITSWAP_100: &[u8] = b"/ipfs/bitswap/1.0.0";

/// Default timeout for block requests
const DEFAULT_BLOCK_TIMEOUT: Duration = Duration::from_secs(30);

/// Configuration for Bitswap service
#[derive(Clone, Debug)]
pub struct BitswapConfig {
    /// Maximum number of concurrent connections
    pub max_connections: usize,
    /// Bandwidth limit in bytes per second (None for no limit)
    pub bandwidth_limit: Option<usize>,
    /// Protocol version to use
    pub protocol_version: Vec<u8>,
    /// Window duration for bandwidth measurement
    pub bandwidth_window: Duration,
}

impl Default for BitswapConfig {
    fn default() -> Self {
        Self {
            max_connections: 100,
            bandwidth_limit: None,
            protocol_version: BITSWAP_120.to_vec(),
            bandwidth_window: Duration::from_secs(1),
        }
    }
}

/// Circuit breaker configuration
const CIRCUIT_BREAKER_THRESHOLD: u32 = 5; // Number of failures before opening the circuit
const CIRCUIT_BREAKER_TIMEOUT: Duration = Duration::from_secs(30); // Time to wait before half-open

/// Bitswap service implementation with protocol version 1.2.0 support
pub struct BitswapService {
    /// The underlying libp2p swarm
    swarm: Swarm<Bitswap>,
    /// Tracks block wants and peer capabilities
    wantlist: Arc<Wantlist>,
    /// Channel for sending node events
    event_sender: mpsc::Sender<NodeEvent>,
    /// Tracks pending block requests for deduplication
    pending_requests: HashMap<Cid, Vec<PeerId>>,
    /// Metrics for monitoring
    metrics: BitswapMetrics,
    /// Protocol version to use
    protocol_version: Vec<u8>,
    /// Connection and bandwidth management
    connection_manager: Arc<ConnectionManager>,
    /// Configuration
    config: BitswapConfig,
    /// Circuit breaker for peer failures
    peer_circuit_breaker: Arc<Mutex<HashMap<PeerId, CircuitBreaker>>>,
    /// Circuit breaker for request failures
    request_circuit_breaker: Arc<Mutex<HashMap<Cid, CircuitBreaker>>>,
}

/// Information about a pending block request
#[derive(Debug, Clone)]
struct PendingRequest {
    /// When the request was made
    timestamp: Instant,
    /// Peers we've already tried
    tried_peers: Vec<PeerId>,
    /// Current retry count
    retry_count: u32,
    /// Request priority
    priority: Priority,
}

/// Tracks peer performance metrics for scoring
#[derive(Debug, Clone)]
struct PeerScore {
    /// Successfully received blocks from this peer
    blocks_received: u64,
    /// Total bytes received from this peer
    bytes_received: u64,
    /// Failed attempts with this peer
    failures: u32,
    /// Response time in microseconds (exponentially weighted moving average)
    avg_response_time: f64,
    /// Last time we received a block from this peer
    last_seen: Instant,
    /// Score value (higher is better)
    score: AtomicI32,
}

impl Default for PeerScore {
    fn default() -> Self {
        Self {
            blocks_received: 0,
            bytes_received: 0,
            failures: 0,
            avg_response_time: 0.0,
            last_seen: Instant::now(),
            score: AtomicI32::new(100), // Start with a neutral score
        }
    }
}

impl PeerScore {
    /// Update score based on a successful block transfer
    fn record_success(&mut self, block_size: usize, response_time: Duration) {
        self.blocks_received += 1;
        self.bytes_received += block_size as u64;
        
        // Update EWMA of response time (alpha = 0.1)
        let response_time_us = response_time.as_micros() as f64;
        if self.avg_response_time == 0.0 {
            self.avg_response_time = response_time_us;
        } else {
            self.avg_response_time = 0.9 * self.avg_response_time + 0.1 * response_time_us;
        }
        
        self.last_seen = Instant::now();
        
        // Increase score for success (capped at 1000)
        self.score.fetch_add(10, Ordering::Relaxed).min(1000);
    }
    
    /// Update score based on a failed attempt
    fn record_failure(&mut self) {
        self.failures += 1;
        
        // Decrease score for failure (capped at -1000)
        self.score.fetch_sub(20, Ordering::Relaxed).max(-1000);
    }
    
    /// Get the current score
    fn get_score(&self) -> i32 {
        self.score.load(Ordering::Relaxed)
    }
    
    /// Calculate a performance metric (higher is better)
    fn performance_metric(&self) -> f64 {
        let score = self.get_score() as f64;
        let time_since_seen = self.last_seen.elapsed().as_secs_f64();
        
        // Decay score based on time since last seen (half-life of 1 hour)
        let decay = 2.0f64.powf(-time_since_seen / 3600.0);
        score * decay
    }
}

/// Tracks block wants and peer capabilities with scoring
#[derive(Default)]
struct Wantlist {
    /// Blocks that are wanted, mapped to their priority and the peers that have them
    wanted_blocks: HashMap<Cid, (Priority, BTreeMap<PeerId, i32>)>,
    /// Peers that we're connected to and their scores
    peers: HashMap<PeerId, (HashSet<Cid>, Arc<Mutex<PeerScore>>)>,
    /// Blocks that we have and can provide to others
    provided_blocks: HashSet<Cid>,
    /// Pending requests with their metadata
    pending_requests: HashMap<Cid, PendingRequest>,
}

/// Bandwidth usage statistics
#[derive(Debug, Default, Clone)]
struct BandwidthStats {
    /// Bytes received in the current window
    bytes_received: AtomicUsize,
    /// Bytes sent in the current window
    bytes_sent: AtomicUsize,
    /// When the current window started
    window_start: Instant,
    /// Duration of the measurement window
    window_duration: Duration,
}

/// Connection limits and statistics
#[derive(Debug)]
struct ConnectionManager {
    /// Maximum number of concurrent connections
    max_connections: usize,
    /// Current number of active connections
    active_connections: AtomicUsize,
    /// Bandwidth usage statistics
    bandwidth: BandwidthStats,
    /// Queue of pending requests when at connection limit
    pending_requests: Mutex<VecDeque<Box<dyn FnOnce() + Send + 'static>>>,
}

/// Metrics for the Bitswap service
#[derive(Clone)]
pub(crate) struct BitswapMetrics {
    blocks_received: IntCounter,
    blocks_sent: IntCounter,
    blocks_not_found: IntCounter,
    active_peers: IntGauge,
    wantlist_size: IntGauge,
    bandwidth_in: IntCounter,
    bandwidth_out: IntCounter,
    connection_errors: IntCounter,
    bandwidth_limit_exceeded: IntCounter,
    
    // Circuit breaker metrics
    circuit_opened: IntCounterVec,
    circuit_closed: IntCounterVec,
    circuit_requests_rejected: IntCounterVec,
    circuit_state: IntGaugeVec,
    circuit_failures: IntCounterVec,
}

impl BandwidthStats {
    /// Records received bytes and checks against the limit
    fn record_received(&self, bytes: usize, limit: Option<usize>) -> bool {
        let now = Instant::now();
        let window_elapsed = now.duration_since(self.window_start);
        
        // Reset counters if window has elapsed
        if window_elapsed > self.window_duration {
            self.bytes_received.store(0, Ordering::Relaxed);
            self.bytes_sent.store(0, Ordering::Relaxed);
            return true;
        }
        
        // Check if we're over the limit
        if let Some(limit) = limit {
            let current = self.bytes_received.fetch_add(bytes, Ordering::Relaxed) + bytes;
            if current > limit {
                return false;
            }
        }
        
        true
    }
    
    /// Records sent bytes and checks against the limit
    fn record_sent(&self, bytes: usize, limit: Option<usize>) -> bool {
        // Similar to record_received but for sent bytes
        let now = Instant::now();
        let window_elapsed = now.duration_since(self.window_start);
        
        if window_elapsed > self.window_duration {
            self.bytes_received.store(0, Ordering::Relaxed);
            self.bytes_sent.store(0, Ordering::Relaxed);
            return true;
        }
        
        if let Some(limit) = limit {
            let current = self.bytes_sent.fetch_add(bytes, Ordering::Relaxed) + bytes;
            if current > limit {
                return false;
            }
        }
        
        true
    }
}

impl ConnectionManager {
    /// Creates a new connection manager with the specified limits
    fn new(max_connections: usize, window_duration: Duration) -> Self {
        Self {
            max_connections,
            active_connections: AtomicUsize::new(0),
            bandwidth: BandwidthStats {
                bytes_received: AtomicUsize::new(0),
                bytes_sent: AtomicUsize::new(0),
                window_start: Instant::now(),
                window_duration,
            },
            pending_requests: Mutex::new(VecDeque::new()),
        }
    }
    
    /// Tries to acquire a connection slot, returns true if successful
    fn try_acquire_connection(&self) -> bool {
        let current = self.active_connections.load(Ordering::Relaxed);
        if current >= self.max_connections {
            return false;
        }
        self.active_connections.fetch_add(1, Ordering::Relaxed) < self.max_connections
    }
    
    /// Releases a connection slot
    fn release_connection(&self) {
        self.active_connections.fetch_sub(1, Ordering::Relaxed);
    }
    
    /// Queues a request to be executed when a connection becomes available
    async fn queue_request<F, Fut, T>(&self, f: F) -> T
    where
        F: FnOnce() -> Fut + Send + 'static,
        Fut: Future<Output = T> + Send + 'static,
        T: Send + 'static,
    {
        let (sender, receiver) = futures::channel::oneshot::channel();
        
        // Create a future that will execute the user's future and send the result
        let wrapped = move || {
            let future = f();
            async move {
                let result = future.await;
                let _ = sender.send(result);
            }
        };
        
        // Try to execute immediately if we're under the limit
        if self.try_acquire_connection() {
            wrapped().await;
            return receiver.await.unwrap_or_else(|_| {
                panic!("Failed to receive result from immediately executed request");
            });
        }
        
        // Otherwise queue the request
        {
            let mut pending = self.pending_requests.lock().unwrap();
            pending.push_back(Box::new(move || {
                Box::pin(wrapped()) as Pin<Box<dyn Future<Output = ()> + Send>>
            }));
        }
        
        // Wait for the request to complete
        receiver.await.unwrap_or_else(|_| {
            panic!("Failed to receive result from queued request");
        })
    }
    
    /// Processes pending requests when connections become available
    fn process_pending_requests(&self) {
        let mut pending = match self.pending_requests.try_lock() {
            Ok(guard) => guard,
            Err(_) => return, // Another task is processing
        };
        
        while let Some(request) = pending.pop_front() {
            if !self.try_acquire_connection() {
                // No more connections available, put it back
                pending.push_front(request);
                break;
            }
            
            // Execute the request in the background
            tokio::spawn(async move {
                request().await;
            });
        }
    }
}

impl BitswapMetrics {
    fn new(registry: &prometheus::Registry) -> Result<Self> {
        let blocks_received = IntCounter::new(
            "bitswap_blocks_received_total",
            "Total number of blocks received via Bitswap"
        )?;
        
        let blocks_sent = IntCounter::new(
            "bitswap_blocks_sent_total",
            "Total number of blocks sent via Bitswap"
        )?;
        
        let blocks_not_found = IntCounter::new(
            "bitswap_blocks_not_found_total",
            "Total number of block not found errors"
        )?;
        
        let active_peers = IntGauge::new(
            "bitswap_active_peers",
            "Current number of active peers"
        )?;
        
        let wantlist_size = IntGauge::new(
            "bitswap_wantlist_size",
            "Current number of blocks in the wantlist"
        )?;
        
        let bandwidth_in = IntCounter::new(
            "bitswap_bandwidth_in_bytes_total",
            "Total bytes received via Bitswap"
        )?;
        
        let bandwidth_out = IntCounter::new(
            "bitswap_bandwidth_out_bytes_total",
            "Total bytes sent via Bitswap"
        )?;
        
        let connection_errors = IntCounter::new(
            "bitswap_connection_errors_total",
            "Total number of connection errors"
        )?;
        
        let bandwidth_limit_exceeded = IntCounter::new(
            "bitswap_bandwidth_limit_exceeded_total",
            "Number of times bandwidth limit was exceeded"
        )?;
        
        // Circuit breaker metrics
        let circuit_opened = IntCounterVec::new(
            Opts::new(
                "bitswap_circuit_opened_total",
                "Number of times a circuit breaker has been opened"
            ),
            &["circuit"]
        )?;
        
        let circuit_closed = IntCounterVec::new(
            Opts::new(
                "bitswap_circuit_closed_total",
                "Number of times a circuit breaker has been closed after reset timeout"
            ),
            &["circuit"]
        )?;
        
        let circuit_requests_rejected = IntCounterVec::new(
            Opts::new(
                "bitswap_circuit_requests_rejected_total",
                "Number of requests rejected due to open circuit"
            ),
            &["circuit"]
        )?;
        
        let circuit_state = IntGaugeVec::new(
            Opts::new(
                "bitswap_circuit_state",
                "Current state of the circuit breaker (0=closed, 1=half-open, 2=open)"
            ),
            &["circuit"]
        )?;
        
        let circuit_failures = IntCounterVec::new(
            Opts::new(
                "bitswap_circuit_failures_total",
                "Number of failures recorded by the circuit breaker"
            ),
            &["circuit"]
        )?;
        
        // Register all metrics
        registry.register(Box::new(blocks_received.clone()))?;
        registry.register(Box::new(blocks_sent.clone()))?;
        registry.register(Box::new(blocks_not_found.clone()))?;
        registry.register(Box::new(active_peers.clone()))?;
        registry.register(Box::new(wantlist_size.clone()))?;
        registry.register(Box::new(bandwidth_in.clone()))?;
        registry.register(Box::new(bandwidth_out.clone()))?;
        registry.register(Box::new(connection_errors.clone()))?;
        registry.register(Box::new(bandwidth_limit_exceeded.clone()));
        registry.register(Box::new(circuit_opened.clone()))?;
        registry.register(Box::new(circuit_closed.clone()))?;
        registry.register(Box::new(circuit_requests_rejected.clone()))?;
        registry.register(Box::new(circuit_state.clone()))?;
        registry.register(Box::new(circuit_failures.clone()))?;
        
        Ok(Self {
            blocks_received,
            blocks_sent,
            blocks_not_found,
            active_peers,
            wantlist_size,
            bandwidth_in,
            bandwidth_out,
            connection_errors,
            bandwidth_limit_exceeded,
            circuit_opened,
            circuit_closed,
            circuit_requests_rejected,
            circuit_state,
            circuit_failures,
        })
    }
}

impl BitswapService {
    /// Creates a new Bitswap service instance with the specified configuration.
    /// 
    /// # Arguments
    /// * `peer_id` - The local peer ID
    /// * `event_sender` - Channel for sending node events
    /// * `registry` - Prometheus metrics registry
    /// * `config` - Configuration for the Bitswap service
    pub fn with_config(
        peer_id: PeerId,
        event_sender: mpsc::Sender<NodeEvent>,
        registry: &prometheus::Registry,
        config: BitswapConfig,
    ) -> Result<Self> {
        let metrics = BitswapMetrics::new(registry)?;
        let connection_manager = Arc::new(ConnectionManager::new(
            config.max_connections,
            config.bandwidth_window,
        ));
        
        // Create libp2p Bitswap config with our protocol version
        let mut bitswap_config = Libp2pBitswapConfig::default();
        bitswap_config.set_protocol_prefix(config.protocol_version.clone());
        
        let bitswap = Bitswap::new(peer_id, bitswap_config);
        let swarm = Swarm::new(bitswap);
        
        Ok(Self {
            swarm,
            wantlist: Arc::new(Wantlist::default()),
            event_sender,
            pending_requests: HashMap::new(),
            metrics,
            protocol_version: config.protocol_version.clone(),
            connection_manager,
            config,
            peer_circuit_breaker: Arc::new(Mutex::new(HashMap::new())),
            request_circuit_breaker: Arc::new(Mutex::new(HashMap::new())),)
    }
    
    /// Creates a new Bitswap service instance with default configuration.
    /// 
    /// # Arguments
    /// * `peer_id` - The local peer ID
    /// * `event_sender` - Channel for sending node events
    /// * `registry` - Prometheus metrics registry
    pub fn new(
        peer_id: PeerId,
        event_sender: mpsc::Sender<NodeEvent>,
        registry: &prometheus::Registry,
    ) -> Result<Self> {
        Self::with_config(peer_id, event_sender, registry, BitswapConfig::default())
    }
    
    /// Creates a new Bitswap service instance with custom configuration.
    /// 
    /// # Arguments
    /// * `peer_id` - The local peer ID
    /// * `event_sender` - Channel for sending node events
    /// * `registry` - Prometheus metrics registry
    /// * `config` - Configuration for the Bitswap service
    pub fn with_config(
        peer_id: PeerId,
        event_sender: mpsc::Sender<NodeEvent>,
        registry: &prometheus::Registry,
        config: BitswapConfig,
    ) -> Result<Self> {
        // Initialize metrics
        let metrics = BitswapMetrics::new(registry)?;
        
        // Create connection manager with bandwidth tracking
        let connection_manager = Arc::new(ConnectionManager::new(
            config.max_connections,
            config.bandwidth_window,
        ));
        
        // Create libp2p Bitswap config with our protocol version
        let mut bitswap_config = Libp2pBitswapConfig::default();
        bitswap_config.set_protocol_prefix(config.protocol_version.clone());
        
        let bitswap = Bitswap::new(peer_id, bitswap_config);
        let swarm = Swarm::new(bitswap);
        
        Ok(Self {
            swarm,
            wantlist: Arc::new(Wantlist::default()),
            event_sender,
            pending_requests: HashMap::new(),
            connection_manager,
            metrics,
            config,
        })
    }
        
    /// Returns a reference to the underlying Swarm.
    pub fn swarm_mut(&mut self) -> &mut Swarm<Bitswap> {
        &mut self.swarm
    }
    
    /// Returns a reference to the metrics.
    pub fn metrics(&self) -> &BitswapMetrics {
        &self.metrics
    }
    
    /// Returns a reference to the connection manager.
    pub fn connection_manager(&self) -> &Arc<ConnectionManager> {
        &self.connection_manager
    }
    
    /// Returns a reference to the configuration.
    pub fn config(&self) -> &BitswapConfig {
        &self.config
    }
    
    /// Returns a reference to the wantlist.
    pub fn wantlist(&self) -> &Arc<Wantlist> {
        &self.wantlist
    }

    /// Adds a block to the wantlist.
    pub fn want_block(&mut self, block: Block) {
        self.wantlist.blocks.push(block);
    }

    /// Removes a block from the wantlist.
    pub fn cancel_want(&mut self, cid: &cid::Cid) {
        self.wantlist.blocks.retain(|b| b.cid() != cid);
    }

    /// Processes incoming Bitswap events with protocol version handling and deduplication.
    pub async fn process_events(&mut self) -> Result<()> {
        // First check for any timed out requests
        self.check_timeouts().await?;
        
        // Then process the next event with a timeout
        let event = match timeout(Duration::from_secs(1), self.swarm.next_event()).await {
            Ok(Some(event)) => event,
            Ok(None) => return Ok(()), // No more events
            Err(_) => {
                // Timeout occurred, check timeouts and continue
                self.check_timeouts().await?;
                return Ok(());
            }
        };
        
        match event {
                
                SwarmEvent::Behaviour(BitswapEvent::BlockReceived { block, from }) => {
                    let cid = *block.cid();
                    log::debug!("Received block {} from peer {}", cid, from);
                    
                    // Remove from pending requests
                    self.pending_requests.remove(&cid);
                    
                    // Remove from wantlist
                    {
                        let wantlist = Arc::get_mut(&mut self.wantlist).expect("Failed to get mutable wantlist");
                        wantlist.wanted_blocks.remove(&cid);
                    }
                    
                    // Mark as provided
                    self.provide_block(cid);
                    
                    // Update metrics
                    self.metrics.blocks_received.inc();
                    self.metrics.wantlist_size.dec();
                    
                    // Notify about the received block
                    if let Err(e) = self.event_sender.send(NodeEvent::BlockReceived(cid)).await {
                        log::error!("Failed to send BlockReceived event: {}", e);
                    }
                }
                
                SwarmEvent::Behaviour(BitswapEvent::BlockSent { block, to }) => {
                    log::debug!("Sent block {} to peer {}", block.cid(), to);
                    self.metrics.blocks_sent.inc();
                }
                
                SwarmEvent::Behaviour(BitswapEvent::BlockNotFound { cid, from }) => {
                    log::debug!("Block {} not found from peer {}", cid, from);
                    self.metrics.blocks_not_found.inc();
                    
                    // Try other peers that might have this block
                    if let Some((_, peers)) = self.wantlist.wanted_blocks.get(&cid) {
                        let other_peers: Vec<_> = peers.iter()
                            .filter(|&&peer_id| peer_id != from)
                            .cloned()
                            .collect();
                            
                        for peer_id in other_peers {
                            log::debug!("Trying alternative peer {} for block {}", peer_id, cid);
                            let block = Block { cid, data: Vec::new() };
                            self.swarm.behaviour_mut().want_block(peer_id, block, Priority::default());
                        }
                    }
                }
                
                SwarmEvent::Behaviour(BitswapEvent::Error { error }) => {
                    log::error!("Bitswap error: {}", error);
                    self.metrics.connection_errors.inc();
                    if let Err(e) = self
                        .event_sender
                        .send(NodeEvent::Error(format!("Bitswap error: {}", error)))
                        .await
                    {
                        log::error!("Failed to forward Bitswap error: {}", e);
                    }
                }
                
                SwarmEvent::NewListenAddr { address, .. } => {
                    log::info!("Bitswap listening on {}", address);
                }
                
                SwarmEvent::IncomingConnection { .. } => {
                    // Handled by ConnectionEstablished
                }
                
                SwarmEvent::ConnectionEstablished { peer_id, .. } => {
                    self.handle_new_peer(peer_id);
                }
                
                SwarmEvent::ConnectionClosed { peer_id, .. } => {
                    log::debug!("Disconnected from peer {}", peer_id);
                    
                    // Remove peer from our tracking
                    let mut wantlist = Arc::get_mut(&mut self.wantlist).expect("Failed to get mutable wantlist");
                    wantlist.peers.remove(&peer_id);
                    
                    // Update metrics
                    self.metrics.active_peers.dec();
                }
                
                _ => {}
            }
        }
        Ok(())
    }

    /// Handles incoming Bitswap messages with protocol version awareness
    async fn handle_bitswap_message(&mut self, peer_id: PeerId, message: BitswapMessage) -> Result<()> {
        log::debug!("Received message from {}: {:?}", peer_id, message);
        
        // Handle message based on protocol version
        if self.protocol_version == BITSWAP_120 {
            self.handle_bitswap_120_message(peer_id, message).await
        } else {
            // Fallback to basic message handling for older versions
            self.handle_legacy_bitswap_message(peer_id, message).await
        }
    }
    
    /// Handles Bitswap 1.2.0 protocol messages
    async fn handle_bitswap_120_message(&mut self, peer_id: PeerId, message: BitswapMessage) -> Result<()> {
        // Process want-have and want-block entries
        for (cid, entry) in message.want() {
            match entry.want_type() {
                WantType::Have => {
                    // Handle want-have
                    if let Some(block) = self.get_block(cid).await? {
                        self.send_have(peer_id, *cid).await?;
                    } else {
                        self.send_dont_have(peer_id, *cid).await?;
                    }
                },
                WantType::Block => {
                    // Handle want-block
                    if let Some(block) = self.get_block(cid).await? {
                        self.send_block(peer_id, block).await?;
                    } else {
                        self.send_dont_have(peer_id, *cid).await?;
                    }
                },
                _ => {
                    log::warn!("Unsupported want type from peer {}: {:?}", peer_id, entry);
                }
            }
        }
        
        // Process block presence (HAVE/DONT_HAVE)
        for (cid, presence) in message.block_presences() {
            // Update our peer's block presence information
            self.update_peer_block_presence(peer_id, *cid, presence.is_have());
        }
        
        // Process incoming blocks
        for block in message.blocks() {
            let cid = *block.cid();
            log::debug!("Received block {} from peer {}", cid, peer_id);
            
            // Remove from pending requests
            self.pending_requests.remove(&cid);
            
            // Process the received block
            self.process_received_block(block, peer_id).await?;
        }
        
        Ok(())
    }
    
    /// Handles legacy Bitswap protocol messages (pre-1.2.0)
    async fn handle_legacy_bitswap_message(&mut self, peer_id: PeerId, message: BitswapMessage) -> Result<()> {
        // Process all entries as want-block for legacy compatibility
        for (cid, _) in message.want() {
            if let Some(block) = self.get_block(cid).await? {
                self.send_block(peer_id, block).await?;
            }
        }
        
        // Process incoming blocks
        for block in message.blocks() {
            self.process_received_block(block, peer_id).await?;
        }
        
        Ok(())
    }
    
    /// Processes a received block and updates internal state
    async fn process_received_block(&mut self, block: &Block, from: PeerId) -> Result<()> {
        let cid = *block.cid();
        let block_size = block.data.len();
        let start_time = Instant::now();
        
        // Record success for this peer and request
        self.record_success(&from, &cid);
        
        // Check bandwidth limits
        if !self.connection_manager.bandwidth.record_received(block_size, self.config.bandwidth_limit) {
            self.metrics.bandwidth_limit_exceeded.inc();
            return Err(anyhow::anyhow!("Bandwidth limit exceeded"));
        }
        
        // Update metrics
        self.metrics.bandwidth_in.inc_by(block_size as i64);
        self.metrics.blocks_received.inc();
        
        // Update peer score for successful transfer
        if let Some(wantlist) = Arc::get_mut(&mut self.wantlist) {
            // Calculate response time (time since request)
            let response_time = if let Some(request) = wantlist.pending_requests.get(&cid) {
                start_time.duration_since(request.timestamp)
            } else {
                Duration::from_millis(0) // Shouldn't happen, but handle gracefully
            };
            
            // Update peer score
            if let Some((_, score)) = wantlist.peers.get_mut(&from) {
                if let Ok(mut score) = score.lock() {
                    score.record_success(block_size, response_time);
                }
            }
            
            // Clean up
            wantlist.wanted_blocks.remove(&cid);
            wantlist.pending_requests.remove(&cid);
        } else {
            log::error!("Failed to get mutable access to wantlist");
            return Err(anyhow::anyhow!("Failed to access wantlist"));
        }
        
        // Mark as provided
        self.provide_block(cid);
        
        // Update metrics
        self.metrics.blocks_received.inc();
        self.metrics.wantlist_size.dec();
        
        // Notify about the received block
        if let Err(e) = self.event_sender.send(NodeEvent::BlockReceived(cid)).await {
            log::error!("Failed to send BlockReceived event: {}", e);
        }
        
        Ok(())
    }
    
    /// Updates the block presence information for a peer
    fn update_peer_block_presence(&mut self, peer_id: PeerId, cid: Cid, has_block: bool) {
        if let Some(wantlist) = Arc::get_mut(&mut self.wantlist) {
            if has_block {
                // Get or create peer entry with score
                let (peer_blocks, _) = wantlist.peers
                    .entry(peer_id)
                    .or_insert_with(|| (HashSet::new(), Arc::new(Mutex::new(PeerScore::default()))));
                
                // Add to peer's blocks
                peer_blocks.insert(cid);
                
                // Add to wanted_blocks with peer's current score
                let peer_score = wantlist.peers.get(&peer_id)
                    .and_then(|(_, score)| Some(score.lock().unwrap().get_score()))
                    .unwrap_or(0);
                
                wantlist.wanted_blocks
                    .entry(cid)
                    .or_insert((Priority::default(), BTreeMap::new()))
                    .1
                    .insert(peer_id, peer_score);
            } else {
                // Remove from peer's blocks
                if let Some((blocks, _)) = wantlist.peers.get_mut(&peer_id) {
                    blocks.remove(&cid);
                }
                
                // Remove from wanted_blocks if this peer had it
                if let Some((_, peers)) = wantlist.wanted_blocks.get_mut(&cid) {
                    peers.remove(&peer_id);
                    if peers.is_empty() {
                        wantlist.wanted_blocks.remove(&cid);
                    }
                }
            }
        }
    }
    
    /// Sends a HAVE message to the specified peer
    async fn send_have(&mut self, peer_id: PeerId, cid: Cid) -> Result<()> {
        let mut message = BitswapMessage::new();
        message.add_have(cid);
        self.swarm.behaviour_mut().send_message(&peer_id, message);
        Ok(())
    }
    
    /// Sends a DONT_HAVE message to the specified peer
    async fn send_dont_have(&mut self, peer_id: PeerId, cid: Cid) -> Result<()> {
        let mut message = BitswapMessage::new();
        message.add_dont_have(cid);
        self.swarm.behaviour_mut().send_message(&peer_id, message);
        Ok(())
    }
    
    /// Sends a block to the specified peer with bandwidth management
    async fn send_block(&mut self, peer_id: PeerId, block: Block) -> Result<()> {
        let block_size = block.data.len();
        
        // Check bandwidth limits
        if !self.connection_manager.bandwidth.record_sent(block_size, self.config.bandwidth_limit) {
            self.metrics.bandwidth_limit_exceeded.inc();
            return Err(anyhow::anyhow!("Bandwidth limit exceeded"));
        }
        
        // Update metrics
        self.metrics.blocks_sent.inc();
        self.metrics.bandwidth_out.inc_by(block_size as i64);
        
        // Clone necessary data for the closure
        let peer_id_clone = peer_id.clone();
        let block_clone = block.clone();
        
        // Send the message with connection management
        self.connection_manager.queue_request(move || {
            let peer_id = peer_id_clone;
            let block = block_clone;
            
            async move {
                let mut message = BitswapMessage::new();
                message.add_block(block);
                
                // Acquire a lock on the swarm to send the message
                if let Some(swarm) = self.swarm.upgrade() {
                    // Create a command to send to the swarm's event loop
                    let command = BitswapCommand::SendMessage {
                        peer_id: peer_id.clone(),
                        message: message.clone(),
                    };
                    
                    // Send the command through the command channel
                    match self.command_sender.send(command).await {
                        Ok(_) => {
                            log::debug!("Successfully queued block send to peer: {}", peer_id);
                            
                            // Update metrics
                            if let Ok(mut metrics) = self.metrics.lock() {
                                metrics.blocks_sent += 1;
                                metrics.bytes_sent += message.serialized_size() as u64;
                                metrics.last_send_time = std::time::Instant::now();
                            }
                        },
                        Err(e) => {
                            log::error!("Failed to send block to peer {}: {}", peer_id, e);
                            return Err(anyhow!("Failed to send command: {}", e));
                        }
                    }
                } else {
                    log::warn!("Cannot send block to peer {}: swarm reference is no longer valid", peer_id);
                    return Err(anyhow!("Swarm reference is no longer valid"));
                }
            }
        }).await;
        
        Ok(())
    }
    
    /// Starts the Bitswap service.
    pub async fn start(&mut self, listen_addr: Multiaddr) -> Result<()> {
        // Start listening on the provided address
        self.swarm.listen_on(listen_addr)
            .context("Failed to start listening on address")?;
            
        log::info!("Bitswap service started with protocol {}", 
            String::from_utf8_lossy(&self.protocol_version));
        Ok(())
    }
    
    /// Checks for and handles any timed out requests
    async fn check_timeouts(&mut self) -> Result<()> {
        let now = Instant::now();
        let timeout = Duration::from_secs(30); // 30 second timeout
        let max_retries = 3;
        
        // Get a list of requests that have timed out
        let mut timed_out = Vec::new();
        {
            let wantlist = Arc::get_mut(&mut self.wantlist).ok_or_else(|| {
                anyhow::anyhow!("Failed to get mutable access to wantlist")
            })?;
            
            for (cid, request) in &wantlist.pending_requests {
                if now.duration_since(request.timestamp) > timeout {
                    timed_out.push((*cid, request.clone()));
                }
            }
        }
        
        // Process timed out requests
        for (cid, request) in timed_out {
            if request.retry_count >= max_retries {
                log::warn!("Max retries ({}) reached for block {}", max_retries, cid);
                self.cancel_request(&cid);
                continue;
            }
            
            log::debug!("Request for block {} timed out, retrying (attempt {}/{})", 
                cid, request.retry_count + 1, max_retries);
            
            // Retry the request with the next available peer
            self.retry_request(cid, request).await?;
        }
        
        Ok(())
    }
    
    /// Retries a request with the next available peer
    async fn retry_request(&mut self, cid: Cid, mut request: PendingRequest) -> Result<()> {
        // Find peers that haven't been tried yet and are not blocked by circuit breaker
        let untried_peers: Vec<PeerId> = self.wantlist
            .peers
            .iter()
            .filter_map(|(peer_id, (blocks, _))| {
                if blocks.contains(&cid) && 
                   !request.tried_peers.contains(peer_id) && 
                   self.is_request_allowed(peer_id, &cid) {
                    Some(*peer_id)
                } else {
                    None
                }
            })
            .collect();
        
        if untried_peers.is_empty() {
            log::warn!("No more peers to try for block {}", cid);
            self.cancel_request(&cid);
            return Ok(());
        }
        
        // Try the next peer
        let next_peer = untried_peers[0];
        request.tried_peers.push(next_peer);
        request.retry_count += 1;
        request.timestamp = Instant::now();
        
        // Update the pending request
        {
            let wantlist = Arc::get_mut(&mut self.wantlist).ok_or_else(|| {
                anyhow::anyhow!("Failed to get mutable access to wantlist")
            })?;
            wantlist.pending_requests.insert(cid, request);
        }
        
        // Send the request
        log::debug!("Retrying block {} with peer {} (attempt {})", 
            cid, next_peer, request.retry_count);
            
        let block = Block {
            cid,
            data: Vec::new(),
        };
        
        self.swarm.behaviour_mut().want_block(next_peer, block, request.priority);
        
        Ok(())
    }
    
    /// Cancels a pending request
    fn cancel_request(&mut self, cid: &Cid) {
        if let Some(mut wantlist) = Arc::get_mut(&mut self.wantlist) {
            wantlist.pending_requests.remove(cid);
            wantlist.wanted_blocks.remove(cid);
            self.metrics.wantlist_size.dec();
        }
    }
    
    /// Checks if a request to a specific peer is allowed by the circuit breaker
    fn is_request_allowed(&self, peer_id: &PeerId, cid: &Cid) -> bool {
        // Check peer circuit breaker
        if let Ok(peer_breaker) = self.peer_circuit_breaker.lock() {
            if let Some(breaker) = peer_breaker.get(peer_id) {
                if breaker.is_blocked() {
                    log::debug!("Request to peer {} blocked by circuit breaker", peer_id);
                    return false;
                }
            }
        }
        
        // Check request circuit breaker
        if let Ok(request_breaker) = self.request_circuit_breaker.lock() {
            if let Some(breaker) = request_breaker.get(cid) {
                if breaker.is_blocked() {
                    log::debug!("Request for block {} blocked by circuit breaker", cid);
                    return false;
                }
            }
        }
        
        true
    }
    
    /// Records a successful request to a peer
    fn record_success(&self, peer_id: &PeerId, cid: &Cid) {
        // Update peer circuit breaker
        if let Ok(mut peer_breaker) = self.peer_circuit_breaker.lock() {
            if let Some(breaker) = peer_breaker.get_mut(peer_id) {
                breaker.success();
            }
        }
        
        // Update request circuit breaker
        if let Ok(mut request_breaker) = self.request_circuit_breaker.lock() {
            if let Some(breaker) = request_breaker.get_mut(cid) {
                breaker.success();
            }
        }
    }
    
    /// Records a failed request to a peer
    fn record_failure(&self, peer_id: &PeerId, cid: &Cid) {
        // Update peer circuit breaker
        {
            let mut peer_breaker = match self.peer_circuit_breaker.lock() {
                Ok(guard) => guard,
                Err(_) => return,
            };
            
            if !peer_breaker.contains_key(peer_id) {
                peer_breaker.insert(
                    *peer_id,
                    CircuitBreaker::new(
                        CIRCUIT_BREAKER_THRESHOLD,
                        CIRCUIT_BREAKER_TIMEOUT,
                        self.metrics.clone(),
                        &format!("peer_{}", peer_id),
                    ),
                );
            }
            
            if let Some(breaker) = peer_breaker.get_mut(peer_id) {
                if breaker.failure() {
                    log::warn!("Circuit opened for peer {}: too many failures", peer_id);
                }
            }
        }
        
        // Update request circuit breaker
        {
            let mut request_breaker = match self.request_circuit_breaker.lock() {
                Ok(guard) => guard,
                Err(_) => return,
            };
            
            if !request_breaker.contains_key(cid) {
                request_breaker.insert(
                    *cid,
                    CircuitBreaker::new(
                        CIRCUIT_BREAKER_THRESHOLD,
                        CIRCUIT_BREAKER_TIMEOUT,
                        self.metrics.clone(),
                        &format!("block_{}", cid),
                    ),
                );
            }
            
            if let Some(breaker) = request_breaker.get_mut(cid) {
                if breaker.failure() {
                    log::warn!("Circuit opened for block {}: too many failures", cid);
                }
            }
        }
    }
    
    /// Requests a block from the network with timeout and retry support.
    pub async fn request_block(&mut self, cid: &Cid, priority: Priority) -> Result<()> {
        log::debug!("Requesting block: {} with priority {:?}", cid, priority);
        
        // Check if we already have this block
        if self.wantlist.provided_blocks.contains(cid) {
            log::debug!("Block {} already available locally", cid);
            return Ok(());
        }
        
        // Check if this is a duplicate request
        if self.wantlist.pending_requests.contains_key(cid) {
            log::debug!("Block {} is already being requested", cid);
            return Ok(());
        }
        
        // Create a new pending request
        let pending_request = PendingRequest {
            timestamp: Instant::now(),
            tried_peers: Vec::new(),
            retry_count: 0,
            priority,
        };
        
        // Add to pending requests
        {
            let wantlist = Arc::get_mut(&mut self.wantlist).ok_or_else(|| {
                anyhow::anyhow!("Failed to get mutable access to wantlist")
            })?;
            
            async move {
                log::debug!("Would send {} provided blocks to peer: {}", 
                    provided_blocks.len(), peer_id);
                // Implementation would go here
                ()
        
        if !peers_with_block.is_empty() {
            // Request from the first available peer
            let peer_id = peers_with_block[0];
            log::debug!("Requesting block {} from peer {}", cid, peer_id);
            
            // Update the pending request
            if let Some(mut wantlist) = Arc::get_mut(&mut self.wantlist) {
                if let Some(request) = wantlist.pending_requests.get_mut(cid) {
                    request.tried_peers.push(peer_id);
                }
            }
            
            // Send the want request to the peer
            let block = Block {
                cid: *cid,
                data: Vec::new(),
            };
            
            self.swarm.behaviour_mut().want_block(peer_id, block, priority);
        } else {
            log::debug!("No known peers have block {}, will wait for DHT discovery", cid);
            // The DHT will notify us when new peers are discovered that have this block
        }
        
        Ok(())
    }
    
    /// Notifies that we have a block available to provide to other peers
    pub fn provide_block(&mut self, cid: Cid) {
        let mut wantlist = Arc::get_mut(&mut self.wantlist).expect("Failed to get mutable wantlist");
        wantlist.provided_blocks.insert(cid);
        
        // Notify connected peers that we have this block
        for peer_id in wantlist.peers.keys() {
            self.swarm.behaviour_mut().provide_block(*peer_id, cid);
        }
    }
    
    /// Handles a new peer connection and exchanges wantlists
    pub async fn handle_new_peer(&mut self, peer_id: PeerId) {
        log::debug!("New peer connected: {}", peer_id);
        
        // Add peer to our tracking with a new score
        if let Some(wantlist) = Arc::get_mut(&mut self.wantlist) {
            wantlist.peers.entry(peer_id)
                .or_insert_with(|| (HashSet::new(), Arc::new(Mutex::new(PeerScore::default()))));
            
            // Send our provided blocks to the new peer with connection management
            let provided_blocks = wantlist.provided_blocks.clone();
            
            // Clone necessary data for the closure
            let peer_id_clone = peer_id;
            
            // Queue the request to send provided blocks to the new peer
            let _ = self.connection_manager.queue_request(move || {
                let peer_id = peer_id_clone;
                let provided_blocks = provided_blocks;
                
                async move {
                    log::debug!("Would send {} provided blocks to peer: {}", 
                        provided_blocks.len(), peer_id);
                    // Implementation would go here
                    ()
                }
            }).await;
            
            self.metrics.active_peers.inc();
        } else {
            log::error!("Failed to get mutable access to wantlist");
        }
    }
}

/// Extension trait to add Bitswap functionality to the Node.
pub trait BitswapExt {
    /// Adds a block to the wantlist.
    fn want_block(&mut self, block: Block);
    
    /// Cancels a block from the wantlist.
    fn cancel_want(&mut self, cid: &cid::Cid);
    
    /// Processes incoming Bitswap events.
    fn process_bitswap_events(&mut self);
}

impl BitswapExt for Node {
    fn want_block(&mut self, block: Block) {
        self.bitswap.want_block(block);
    }
    
    fn cancel_want(&mut self, cid: &Cid) {
        self.bitswap.cancel_want(cid);
    }
    
    fn process_bitswap_events(&mut self) {
        // Process Bitswap events in a blocking way
        let _ = tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current().block_on(async {
                self.bitswap.process_events().await
            })
        });
    }
}
