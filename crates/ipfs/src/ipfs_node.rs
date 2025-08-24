#![cfg(feature = "legacy")]
//! # IPFS Node Implementation
//! 
//! This module provides a high-level, async IPFS node implementation using the `rust-ipfs` crate.
//! It offers a simplified interface for common IPFS operations while maintaining access to
//! lower-level functionality when needed.
//!
//! ## Features
//! - **Peer Management**: Discover, connect to, and manage peers in the IPFS network
//! - **Content Addressing**: Add, retrieve, and manage content using CIDs
//! - **DHT & Content Routing**: Distributed hash table and content routing functionality
//! - **PubSub**: Publish/subscribe messaging system
//! - **File Operations**: Add, get, and manage files and directories
//! - **Pinning**: Manage which content should be kept locally
//! - **Repository Management**: Garbage collection and statistics
//!
//! ## Example
//! ```rust,no_run
//! use ipfs::{Config, Node};
//! use std::path::Path;
//!
//! #[tokio::main]
//! async fn main() -> anyhow::Result<()> {
//!     // Create a new IPFS node with default configuration
//!     let config = Config::default();
//!     let mut node = Node::new(config)?;
//!     
//!     // Start the node
//!     node.start()?;
//!     
//!     // Add a file to IPFS
//!     let cid = node.add_file(Path::new("example.txt")).await?;
//!     println!("Added file with CID: {}", cid);
//!     
//!     // Get the file back from IPFS
//!     node.get_file(&cid, Path::new("downloaded.txt")).await?;
//!     
//!     // Publish a message to a pubsub topic
//!     node.pubsub_publish("test-topic".into(), b"Hello, IPFS!".to_vec()).await?;
//!     
//!     Ok(())
//! }
//! ```

use anyhow::{Context, Result, anyhow};
use async_trait::async_trait;
use cid::Cid;
use futures::{channel::mpsc, Stream, StreamExt, future::BoxFuture};
use libipld::{Block as IpldBlock, DefaultParams};
use libp2p::{
    core::{muxing::StreamMuxerBox, transport::Boxed, upgrade, Multiaddr, PeerId},
    identity::Keypair,
    noise,
    swarm::{NetworkBehaviour, Swarm, SwarmBuilder, SwarmEvent},
    tcp, yamux,
};
use libp2p_quic as quic;
use libp2p_websocket as websocket;
use rust_ipfs::{
    Ipfs, IpfsEvent, IpfsOptions, IpfsPath, UninitializedIpfs,
};
use std::{
    collections::HashSet,
    path::PathBuf,
    pin::Pin,
    sync::Arc,
    time::{Duration, Instant},
};

/// Configuration for the IPFS node
#[derive(Clone, Debug)]
pub struct Config {
    /// Path to the IPFS repository
    pub repo_path: PathBuf,
    /// List of bootstrap nodes to connect to
    pub bootstrap_nodes: Vec<Multiaddr>,
    /// Enable DHT functionality
    pub enable_dht: bool,
    /// Enable mDNS for local peer discovery
    pub enable_mdns: bool,
    /// Enable relay client functionality
    pub enable_relay_client: bool,
    /// Enable relay server functionality
    pub enable_relay_server: bool,
    /// Enable WebSockets transport
    pub enable_websocket: bool,
    /// Enable QUIC transport
    pub enable_quic: bool,
    /// Enable auto-relay mode
    pub enable_auto_relay: bool,
    /// Enable NAT port mapping
    pub enable_nat_port_map: bool,
    /// Enable UPnP port mapping
    pub enable_upnp: bool,
    /// Enable metrics collection
    pub enable_metrics: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            repo_path: std::env::temp_dir().join("ipfs"),
            bootstrap_nodes: vec![
                "/ip4/104.131.131.82/tcp/4001/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ".parse().unwrap(),
                "/ip4/104.131.131.82/udp/4001/quic-v1/p2p/QmaCpDMGvV2BGHeYERUEnRQAwe3N8SzbUtfsmvsqQLuvuJ".parse().unwrap(),
            ],
            enable_dht: true,
            enable_mdns: true,
            enable_relay_client: true,
            enable_relay_server: false,
            enable_websocket: true,
            enable_quic: true,
            enable_auto_relay: true,
            enable_nat_port_map: true,
            enable_upnp: false,
            enable_metrics: false,
        }
    }
}

/// Events emitted by the IPFS node
#[derive(Debug, Clone)]
pub enum NodeEvent {
    /// The node is now listening on the given address
    Listening(Multiaddr),
    /// A new peer was discovered
    PeerDiscovered(PeerId),
    /// A peer has connected
    PeerConnected(PeerId),
    /// A peer has disconnected
    PeerDisconnected(PeerId),
    /// A new block was received
    BlockReceived(Cid),
    /// Data was added to IPFS
    DataAdded(Cid),
    /// A CID was pinned
    Pinned(Cid),
    /// A CID was unpinned
    Unpinned(Cid),
    /// An error occurred
    Error(String),
}

/// An IPFS node implementation using rust-ipfs
pub struct Node {
    /// The underlying rust-ipfs node
    ipfs: Ipfs,
    /// The libp2p swarm
    swarm: Swarm<NodeBehaviour>,
    /// Channel sender for node events
    event_sender: mpsc::Sender<NodeEvent>,
    /// Channel receiver for node events
    event_receiver: mpsc::Receiver<NodeEvent>,
    /// The local peer ID
    peer_id: PeerId,
    /// Background future driving the rust-ipfs node (spawned in start())
    ipfs_task: Option<futures::future::BoxFuture<'static, ()>>,
    /// The configuration for this node
    config: Config,
    /// Active connections
    connections: HashSet<PeerId>,
    /// Known peers
    known_peers: HashSet<PeerId>,
}

impl Node {
    /// Create a new IPFS node with the given configuration
    pub fn new(config: Config) -> Result<Self> {
        // Create channels for node events
        let (event_sender, event_receiver) = mpsc::channel(32);

        // Generate a new keypair for this node
        let local_key = Keypair::generate_ed25519();
        let peer_id = local_key.public().to_peer_id();

        // Create the transport
        let transport = build_transport(&local_key, &config)?;

        // Create the network behaviour
        let behaviour = NodeBehaviour::new(peer_id, &config)?;

        // Create the swarm
        let swarm = SwarmBuilder::with_tokio_executor(transport, behaviour, peer_id).build();

        // Create the IPFS node configuration
        let ipfs_config = IpfsConfig::new()
            .with_repo_path(&config.repo_path)
            .with_keypair(local_key)
            .with_default_listening_addrs()
            .with_dht(config.enable_dht)
            .with_mdns(config.enable_mdns)
            .with_relay(config.enable_relay_client, config.enable_relay_server)
            .with_auto_relay(config.enable_auto_relay)
            .with_nat_port_map(config.enable_nat_port_map)
            .with_upnp(config.enable_upnp)
            .with_metrics(config.enable_metrics);

        // Initialize the IPFS node
        let rt = tokio::runtime::Runtime::new()?;
        let ipfs = rt.block_on(async { UninitializedIpfs::with_config(ipfs_config).start().await })?;

        Ok(Self {
            ipfs,
            swarm,
            event_sender,
            event_receiver,
            peer_id,
            config,
            connections: HashSet::new(),
            known_peers: HashSet::new(),
        })
    }

    /// Start the IPFS node
    pub fn start(&mut self) -> Result<()> {
        // Start listening on all interfaces
        self.swarm.listen_on("/ip4/0.0.0.0/tcp/0".parse()?)?;
        
        // Start the event loop
        self.run_event_loop();
        
        // Connect to bootstrap nodes
        self.connect_to_bootstrap_nodes()?;
        
        Ok(())
    }

    /// Connect to the configured bootstrap nodes
    pub fn connect_to_bootstrap_nodes(&mut self) -> Result<()> {
        for addr in &self.config.bootstrap_nodes {
            if let Err(e) = self.swarm.dial(addr.clone()) {
                log::warn!("Failed to dial bootstrap node {}: {}", addr, e);
            } else {
                log::info!("Dialed bootstrap node: {}", addr);
            }
        }
        Ok(())
    }
    
    /// Get the list of connected peers
    pub fn connected_peers(&self) -> Vec<PeerId> {
        self.connections.iter().cloned().collect()
    }
    
    /// Get the list of known peers
    pub fn known_peers(&self) -> Vec<PeerId> {
        self.known_peers.iter().cloned().collect()
    }
    
    /// Connect to a peer at the given address
    pub fn connect(&mut self, addr: Multiaddr) -> Result<()> {
        self.swarm.dial(addr)?;
        Ok(())
    }
    
    /// Disconnect from a peer
    pub fn disconnect(&mut self, peer_id: PeerId) -> Result<()> {
        self.swarm.disconnect_peer_id(peer_id);
        Ok(())
    }

    /// Run the main event loop
    fn run_event_loop(&mut self) {
        loop {
            tokio::select! {
                Some(event) = self.swarm.next() => {
                    self.handle_swarm_event(event);
                }
                Some(event) = self.ipfs.next() => {
                    self.handle_ipfs_event(event);
                }
                else => break,
            }
        }
    }

    /// Handle a swarm event
    fn handle_swarm_event(&mut self, event: SwarmEvent<NodeBehaviourEvent>) {
        match event {
            SwarmEvent::NewListenAddr { address, .. } => {
                log::info!("Listening on: {}", address);
                if let Err(e) = self.event_sender.try_send(NodeEvent::Listening(address)) {
                    log::error!("Failed to send listening event: {}", e);
                }
            }
            SwarmEvent::ConnectionEstablished { peer_id, endpoint, .. } => {
                log::debug!("Connection established with peer: {} via {:?}", peer_id, endpoint);
                self.connections.insert(peer_id);
                self.known_peers.insert(peer_id);
                if let Err(e) = self.event_sender.try_send(NodeEvent::PeerConnected(peer_id)) {
                    log::error!("Failed to send peer connected event: {}", e);
                }
            }
            SwarmEvent::ConnectionClosed { peer_id, endpoint, error, .. } => {
                log::debug!("Connection closed with peer: {} via {:?}, error: {:?}", 
                    peer_id, endpoint, error);
                self.connections.remove(&peer_id);
                if let Err(e) = self.event_sender.try_send(NodeEvent::PeerDisconnected(peer_id)) {
                    log::error!("Failed to send peer disconnected event: {}", e);
                }
            }
            SwarmEvent::Behaviour(event) => {
                self.handle_behaviour_event(event);
            }
            SwarmEvent::IncomingConnection { local_addr, send_back_addr, .. } => {
                log::debug!("Incoming connection from {} to {}", send_back_addr, local_addr);
            }
            SwarmEvent::ExpiredListenAddr { listener_id, address } => {
                log::warn!("Expired listen address {} on listener {:?}", address, listener_id);
            }
            SwarmEvent::ListenerClosed { listener_id, addresses, reason } => {
                log::warn!("Listener {:?} closed: {:?}, addresses: {:?}", 
                    listener_id, reason, addresses);
            }
            SwarmEvent::ListenerError { listener_id, error } => {
                log::error!("Listener {:?} error: {}", listener_id, error);
            }
            _ => {
                log::trace!("Unhandled swarm event: {:?}", event);
            }
        }
    }

    /// Handle a behaviour event
    fn handle_behaviour_event(&mut self, event: NodeBehaviourEvent) {
        match event {
            NodeBehaviourEvent::PeerDiscovered(peer_id) => {
                log::info!("Discovered peer: {}", peer_id);
                self.known_peers.insert(peer_id);
                if let Err(e) = self.event_sender.try_send(NodeEvent::PeerDiscovered(peer_id)) {
                    log::error!("Failed to send peer discovered event: {}", e);
                }
            }
        }
    }

    /// Handle an IPFS event
    fn handle_ipfs_event(&mut self, event: IpfsEvent) {
        match event {
            IpfsEvent::NewListenAddr(addr) => {
                log::info!("IPFS listening on: {}", addr);
                if let Err(e) = self.event_sender.try_send(NodeEvent::Listening(addr)) {
                    log::error!("Failed to send listening event: {}", e);
                }
            }
            IpfsEvent::ExpiredListenAddr(addr) => {
                log::warn!("IPFS no longer listening on: {}", addr);
            }
            IpfsEvent::Discovered(peer_id) => {
                log::info!("Discovered peer: {}", peer_id);
                self.known_peers.insert(peer_id);
                if let Err(e) = self.event_sender.try_send(NodeEvent::PeerDiscovered(peer_id)) {
                    log::error!("Failed to send peer discovered event: {}", e);
                }
            }
            IpfsEvent::BlockPut(block) => {
                let cid = *block.cid();
                log::debug!("Block stored: {}", cid);
                if let Err(e) = self.event_sender.try_send(NodeEvent::BlockReceived(cid)) {
                    log::error!("Failed to send block received event: {}", e);
                }
            }
            IpfsEvent::BlockGet(cid) => {
                log::debug!("Block retrieved: {}", cid);
            }
            IpfsEvent::Pinned(cid) => {
                log::debug!("Block pinned: {}", cid);
            }
            IpfsEvent::Unpinned(cid) => {
                log::debug!("Block unpinned: {}", cid);
            }
            IpfsEvent::Error(e) => {
                log::error!("IPFS error: {}", e);
                if let Err(e) = self.event_sender.try_send(NodeEvent::Error(e.to_string())) {
                    log::error!("Failed to send error event: {}", e);
                }
            }
            _ => {
                log::trace!("Unhandled IPFS event: {:?}", event);
            }
        }
    }

    /// Get the next node event
    pub async fn next_event(&mut self) -> Option<NodeEvent> {
        self.event_receiver.next().await
    }

    /// Get the local peer ID
    pub fn peer_id(&self) -> PeerId {
        self.peer_id
    }
    
    /// Add data to IPFS and return its CID
    pub async fn add_bytes(&self, data: Vec<u8>) -> Result<Cid> {
        let block = IpldBlock::encode(cid::Codec::Raw, DefaultParams::default(), &data)
            .context("Failed to encode data as IPLD block")?;
        let cid = self.ipfs.put_block(block).await
            .context("Failed to put block in IPFS")?;
        Ok(cid)
    }
    
    /// Get data from IPFS by CID
    pub async fn get_bytes(&self, cid: &Cid) -> Result<Vec<u8>> {
        let block = self.ipfs.get_block(*cid).await
            .context("Failed to get block from IPFS")?;
        Ok(block.data().to_vec())
    }
    
    /// Pin a CID
    pub async fn pin_add(&self, cid: &Cid, recursive: bool) -> Result<()> {
        self.ipfs.pin_add(cid, recursive).await
            .context("Failed to pin CID")?;
        Ok(())
    }
    
    /// Unpin a CID
    pub async fn pin_rm(&self, cid: &Cid, recursive: bool) -> Result<()> {
        self.ipfs.pin_rm(cid, recursive).await
            .context("Failed to unpin CID")?;
        Ok(())
    }
    
    /// Check if a CID is pinned
    pub async fn is_pinned(&self, cid: &Cid) -> Result<bool> {
        self.ipfs.is_pinned(cid).await
            .context("Failed to check if CID is pinned")
    }
    
    /// Get the list of pinned CIDs
    pub async fn list_pins(&self) -> Result<Vec<Cid>> {
        self.ipfs.pins().await
            .context("Failed to list pinned CIDs")
    }
    
    /// Resolve an IPFS path to the final target
    pub async fn resolve(&self, path: &str) -> Result<IpfsPath> {
        let path = path.parse::<IpfsPath>()
            .context("Failed to parse IPFS path")?;
        self.ipfs.resolve(path).await
            .context("Failed to resolve IPFS path")
    }
    
    /// Get the size of a file or directory in bytes
    pub async fn get_size(&self, path: &str) -> Result<u64> {
        let path = path.parse::<IpfsPath>()
            .context("Failed to parse IPFS path")?;
        self.ipfs.object_stat(&path).await
            .map(|stat| stat.cumulative_size)
            .context("Failed to get object size")
    }
    
    /// Get the current repository statistics
    pub async fn repo_stat(&self) -> Result<rust_ipfs::RepoStats> {
        self.ipfs.repo_stat().await
            .context("Failed to get repository statistics")
    }
    
    /// Run garbage collection on the repository
    pub async fn repo_gc(&self) -> Result<Vec<Cid>> {
        self.ipfs.repo_gc().await
            .context("Failed to run garbage collection")
    }
    
    /// Find providers for a given CID
    pub async fn find_providers(&self, cid: &Cid) -> Result<Vec<PeerId>> {
        self.ipfs.find_providers(*cid).await
            .context("Failed to find providers for CID")
    }
    
    /// Provide a CID to the DHT
    pub async fn provide(&self, cid: &Cid) -> Result<()> {
        self.ipfs.provide(cid).await
            .context("Failed to provide CID to DHT")
    }
    
    /// Find peers in the DHT
    pub async fn find_peers(&self, peer_id: PeerId) -> Result<Vec<Multiaddr>> {
        self.ipfs.find_peers(peer_id).await
            .context("Failed to find peers in DHT")
    }
    
    /// Get the closest peers to a key
    pub async fn get_closest_peers(&self, key: &[u8]) -> Result<Vec<PeerId>> {
        self.ipfs.get_closest_peers(key).await
            .context("Failed to get closest peers")
    }
    
    /// Put a value in the DHT
    pub async fn put_value(&self, key: Vec<u8>, value: Vec<u8>) -> Result<()> {
        self.ipfs.put_value(key, value).await
            .context("Failed to put value in DHT")
    }
    
    /// Get a value from the DHT
    pub async fn get_value(&self, key: &[u8]) -> Result<Vec<u8>> {
        self.ipfs.get_value(key).await
            .context("Failed to get value from DHT")
    }
    
    /// Bootstrap the DHT
    pub async fn bootstrap(&self) -> Result<()> {
        self.ipfs.bootstrap().await
            .context("Failed to bootstrap DHT")
    }
    
    /// Get the current DHT metrics
    pub async fn dht_metrics(&self) -> Result<rust_ipfs::DhtMetrics> {
        self.ipfs.dht_metrics().await
            .context("Failed to get DHT metrics")
    }
    
    /// Get the current peer information
    pub async fn peer_info(&self, peer_id: PeerId) -> Result<rust_ipfs::PeerInfo> {
        self.ipfs.peer_info(peer_id).await
            .context("Failed to get peer info")
    }
    
    /// Get the list of connected peers with their addresses
    pub async fn connected_peers_with_addrs(&self) -> Result<Vec<(PeerId, Vec<Multiaddr>)>> {
        self.ipfs.connected_peers().await
            .context("Failed to get connected peers with addresses")
    }
    
    /// Get the list of known peers with their addresses
    pub async fn known_peers_with_addrs(&self) -> Result<Vec<(PeerId, Vec<Multiaddr>)>> {
        self.ipfs.known_peers().await
            .context("Failed to get known peers with addresses")
    }
    
    /// Publish a message to a pubsub topic
    pub async fn pubsub_publish(&self, topic: String, data: Vec<u8>) -> Result<()> {
        self.ipfs.pubsub_publish(topic, data).await
            .context("Failed to publish to pubsub topic")
    }
    
    /// Subscribe to a pubsub topic
    pub async fn pubsub_subscribe(&self, topic: String) -> Result<mpsc::Receiver<rust_ipfs::Message>> {
        self.ipfs.pubsub_subscribe(topic).await
            .context("Failed to subscribe to pubsub topic")
    }
    
    /// Unsubscribe from a pubsub topic
    pub async fn pubsub_unsubscribe(&self, topic: String) -> Result<()> {
        self.ipfs.pubsub_unsubscribe(topic).await
            .context("Failed to unsubscribe from pubsub topic")
    }
    
    /// Get the list of subscribed topics
    pub async fn pubsub_subscribed(&self) -> Result<Vec<String>> {
        self.ipfs.pubsub_subscribed().await
            .context("Failed to get subscribed topics")
    }
    
    /// Get the list of peers subscribed to a topic
    pub async fn pubsub_peers(&self, topic: Option<String>) -> Result<Vec<PeerId>> {
        self.ipfs.pubsub_peers(topic).await
            .context("Failed to get pubsub peers")
    }
    
    /// Get the list of known pubsub topics
    pub async fn pubsub_topics(&self) -> Result<Vec<String>> {
        self.ipfs.pubsub_topics().await
            .context("Failed to get pubsub topics")
    }
    
    /// Add a file to IPFS
    pub async fn add_file(&self, path: &std::path::Path) -> Result<Cid> {
        let data = tokio::fs::read(path).await
            .context("Failed to read file")?;
        let cid = self.add_bytes(data).await?;
        
        if let Err(e) = self.event_sender.try_send(NodeEvent::DataAdded(cid)) {
            log::error!("Failed to send data added event: {}", e);
        }
        
        Ok(cid)
    }
    
    /// Get a file from IPFS and save it to the local filesystem
    pub async fn get_file(&self, cid: &Cid, output_path: &std::path::Path) -> Result<()> {
        let data = self.get_bytes(cid).await?;
        
        // Ensure the parent directory exists
        if let Some(parent) = output_path.parent() {
            tokio::fs::create_dir_all(parent).await
                .context("Failed to create parent directory")?;
        }
        
        tokio::fs::write(output_path, data).await
            .context("Failed to write file")?;
            
        Ok(())
    }
    
    /// Add a directory to IPFS
    pub async fn add_directory(&self, dir_path: &std::path::Path) -> Result<Cid> {
        use std::collections::VecDeque;
        
        let mut dir_queue = VecDeque::new();
        let mut file_paths = Vec::new();
        
        // Walk the directory and collect all files
        dir_queue.push_back(dir_path.to_path_buf());
        
        while let Some(current) = dir_queue.pop_front() {
            let mut entries = tokio::fs::read_dir(&current).await
                .context("Failed to read directory")?;
                
            while let Some(entry) = entries.next_entry().await? {
                let path = entry.path();
                
                if path.is_dir() {
                    dir_queue.push_back(path);
                } else {
                    file_paths.push(path);
                }
            }
        }
        
        // Add all files to IPFS
        let mut file_entries = Vec::new();
        
        for file_path in file_paths {
            let relative_path = file_path.strip_prefix(dir_path)
                .context("Failed to get relative path")?;
            let data = tokio::fs::read(&file_path).await
                .context("Failed to read file")?;
                
            file_entries.push((relative_path.to_path_buf(), data));
        }
        
        // Create a directory structure in IPFS
        let dir_cid = self.ipfs.add_directory(file_entries).await
            .context("Failed to add directory to IPFS")?;
            
        if let Err(e) = self.event_sender.try_send(NodeEvent::DataAdded(dir_cid)) {
            log::error!("Failed to send data added event: {}", e);
        }
        
        Ok(dir_cid)
    }
    
    /// Get a directory from IPFS and save it to the local filesystem
    pub async fn get_directory(&self, cid: &Cid, output_dir: &std::path::Path) -> Result<()> {
        // First, get the directory listing
        let dir_entries = self.ipfs.ls(cid).await
            .context("Failed to list directory")?;
            
        // Create the output directory if it doesn't exist
        tokio::fs::create_dir_all(output_dir).await
            .context("Failed to create output directory")?;
            
        // Process each entry in the directory
        for entry in dir_entries {
            let entry_path = output_dir.join(&entry.name);
            
            if entry.kind == rust_ipfs::NodeType::Directory {
                // Recursively get subdirectories
                self.get_directory(&entry.cid, &entry_path).await?;
            } else {
                // Get the file
                self.get_file(&entry.cid, &entry_path).await?;
            }
        }
        
        Ok(())
    }
    
    /// List the contents of a directory in IPFS
    pub async fn list_directory(&self, cid: &Cid) -> Result<Vec<rust_ipfs::Node>> {
        self.ipfs.list(cid).await
            .context("Failed to list directory")
    }
    
    /// Get information about the local node
    pub async fn node_info(&self) -> Result<rust_ipfs::NodeInfo> {
        self.ipfs.identity().await
            .context("Failed to get node info")
    }
    
    /// Get the current bandwidth usage statistics
    pub async fn bandwidth_stats(&self) -> Result<rust_ipfs::Stats> {
        self.ipfs.stats().await
            .context("Failed to get bandwidth stats")
    }
    
    /// Get the current list of active connections
    pub async fn connections(&self) -> Result<Vec<rust_ipfs::Connection>> {
        self.ipfs.connections().await
            .context("Failed to get connections")
    }
    
    /// Get the current list of listening addresses
    pub async fn listen_addresses(&self) -> Result<Vec<Multiaddr>> {
        self.ipfs.listening_addresses().await
            .context("Failed to get listen addresses")
    }
    
    /// Get the current list of bootstrap nodes
    pub fn bootstrap_nodes(&self) -> &[Multiaddr] {
        &self.config.bootstrap_nodes
    }
    
    /// Add a bootstrap node
    pub fn add_bootstrap_node(&mut self, addr: Multiaddr) -> bool {
        if !self.config.bootstrap_nodes.contains(&addr) {
            self.config.bootstrap_nodes.push(addr);
            true
        } else {
            false
        }
    }
    
    /// Remove a bootstrap node
    pub fn remove_bootstrap_node(&mut self, addr: &Multiaddr) -> bool {
        let len_before = self.config.bootstrap_nodes.len();
        self.config.bootstrap_nodes.retain(|a| a != addr);
        self.config.bootstrap_nodes.len() < len_before
    }
    
    /// Get the current configuration
    pub fn config(&self) -> &Config {
        &self.config
    }
    
    /// Get a mutable reference to the configuration
    pub fn config_mut(&mut self) -> &mut Config {
        &mut self.config
    }
}

/// Build the libp2p transport with support for multiple protocols
fn build_transport(keypair: &Keypair, config: &Config) -> Result<Boxed<(PeerId, StreamMuxerBox)>> {
    // Create noise keys for secure communication using the updated API
    let noise_keys = noise::Config::new(keypair)
        .context("Failed to create noise keys")?;

    // Start with TCP transport
    let tcp_transport = tcp::tokio::Transport::new(tcp::Config::default().nodelay(true));
    
    // Add WebSocket support if enabled
    let transport = if config.enable_websocket {
        let ws_transport = libp2p::websocket::tokio::WsConfig::new(
            tcp_transport.clone()
        );
        tcp_transport.or_transport(ws_transport)
    } else {
        tcp_transport.into()
    };
    
    // Add QUIC support if enabled (requires different key handling)
    let transport = if config.enable_quic {
        let quic_transport = libp2p::quic::tokio::Transport::new(
            libp2p::tls::Config::new(keypair)
        );
        transport.or_transport(quic_transport)
    } else {
        transport
    };

    // Finalize the transport with noise and yamux
    let transport = transport
        .upgrade(upgrade::Version::V1)
        .authenticate(noise_keys)
        .multiplex(yamux::YamuxConfig::default())
        .boxed();

    Ok(transport)
}

/// Network behaviour for the IPFS node
#[derive(NetworkBehaviour)]
#[behaviour(out_event = "NodeBehaviourEvent")]
pub struct NodeBehaviour {
    // Add custom behaviours here
}

/// Events emitted by the network behaviour
#[derive(Debug)]
pub enum NodeBehaviourEvent {
    /// A new peer was discovered
    PeerDiscovered(PeerId),
}

impl NodeBehaviour {
    /// Create a new network behaviour
    pub fn new(_peer_id: PeerId) -> Result<Self> {
        Ok(Self {})
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_node_creation() {
        let temp_dir = tempdir().unwrap();
        let config = Config {
            repo_path: temp_dir.path().to_path_buf(),
            ..Default::default()
        };

        let node = Node::new(config).await;
        assert!(node.is_ok());
    }
}
