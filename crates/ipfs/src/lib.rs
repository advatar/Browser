//! IPFS implementation for the decentralized browser.
//!
//! This crate provides IPFS functionality including block storage,
//! content addressing, and peer-to-peer networking.
//!     }
//!     
//!     Ok(())
//! }
//! ```

#![deny(missing_docs)]
#![forbid(unsafe_code)]
#![feature(type_alias_impl_trait)]

pub mod blockstore;
pub mod ipfs_node;

#[cfg(feature = "legacy")]
pub mod node;
#[cfg(feature = "legacy")]
pub mod node_new;

/// Re-export commonly used types.
pub use blockstore::SledStore;
pub use cid::Cid;
pub use libp2p::PeerId;
use libp2p_identity as identity;
use std::path::PathBuf;

// Re-export the appropriate node implementation based on feature flags
#[cfg(all(feature = "rust-ipfs", not(feature = "legacy")))]
pub use ipfs::node_modern::Node;

// Legacy implementation (deprecated)
#[cfg(feature = "legacy")]
pub use ipfs::node::Node;

// Common types and traits
pub use ipfs::{
    Block, BlockStore, Config, Error, EventStream, NodeEvent, Result,
    ipfs::{self, Node as IpfsNode},
};

// Re-export common types and traits
pub use cid::Cid;
pub use libp2p::{Multiaddr, PeerId};
pub use multihash;
pub use libipld;

use std::{
    fmt,
    path::PathBuf,
    pin::Pin,
    task::{Context, Poll},
};
use futures::Stream;
use thiserror::Error;

/// A block of data with an associated CID
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Block {
    cid: Cid,
    data: Vec<u8>,
}

impl Block {
    /// Create a new block with the given data and codec
    pub fn new(data: Vec<u8>) -> Self {
        use cid::multihash::{Code, MultihashDigest};
        
        let hash = Code::Sha2_256.digest(&data);
        let cid = Cid::new_v1(cid::Codec::Raw, hash);
        
        Self { cid, data }
    }
    
    /// Create a block with a specific CID and data
    pub fn with_cid(cid: Cid, data: Vec<u8>) -> Self {
        Self { cid, data }
    }
    
    /// Get a reference to the block's CID
    pub fn cid(&self) -> &Cid {
        &self.cid
    }
    
    /// Get a reference to the block's data
    pub fn data(&self) -> &[u8] {
        &self.data
    }
    
    /// Consume the block and return its data
    pub fn into_data(self) -> Vec<u8> {
        self.data
    }
}

/// Trait for types that can store and retrieve blocks
#[async_trait::async_trait]
pub trait BlockStore: Send + Sync + 'static {
    /// Get a block by its CID
    async fn get_block(&self, cid: &Cid) -> Result<Option<Block>>;
    
    /// Store a block
    async fn put_block(&mut self, block: Block) -> Result<Cid>;
    
    /// Check if a block exists
    async fn has_block(&self, cid: &Cid) -> Result<bool>;
}

/// Error type for IPFS operations
#[derive(Debug, Error)]
pub enum Error {
    /// I/O error
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    
    /// CID error
    #[error("CID error: {0}")]
    Cid(#[from] cid::Error),
    
    /// Multiaddress error
    #[error("Multiaddress error: {0}")]
    Multiaddr(#[from] libp2p::multiaddr::Error),
    
    /// Peer ID error
    #[error("Peer ID error: {0}")]
    PeerId(#[from] libp2p::identity::DecodingError),
    
    /// Libp2p error
    #[error("Libp2p error: {0}")]
    Libp2p(#[from] libp2p::core::transport::TransportError<std::io::Error>),
    
    /// Channel error
    #[error("Channel error")]
    ChannelClosed,
    
    /// Other error
    #[error("{0}")]
    Other(String),
}

/// Alias for `Result<T, Error>`
pub type Result<T> = std::result::Result<T, Error>;

/// A stream of node events
pub struct EventStream {
    receiver: mpsc::Receiver<NodeEvent>,
}

impl Stream for EventStream {
    type Item = NodeEvent;
    
    fn poll_next(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<Option<Self::Item>> {
        self.receiver.poll_next_unpin(cx)
    }
}

/// Events emitted by the IPFS node
#[derive(Debug, Clone)]
pub enum NodeEvent {
    /// A new peer was discovered
    PeerDiscovered(PeerId),
    /// A peer has connected
    PeerConnected(PeerId),
    /// A peer has disconnected
    PeerDisconnected(PeerId),
    /// A new block was received
    BlockReceived(Cid),
    /// An error occurred
    Error(String),
}

/// Configuration for the IPFS node
#[derive(Debug, Clone)]
pub struct Config {
    /// Path to the repository
    pub repo_path: PathBuf,
    /// Listen addresses for the node
    pub listen_addrs: Vec<Multiaddr>,
    /// Bootstrap nodes to connect to
    pub bootstrap_nodes: Vec<Multiaddr>,
    /// Whether to enable mDNS for local peer discovery
    pub mdns_enabled: bool,
    /// Whether to enable Kademlia DHT for peer and content routing
    pub kademlia_enabled: bool,
    /// Whether to enable the DHT server (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub dht_server: bool,
    /// Whether to enable the relay client (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub relay_client: bool,
    /// Whether to enable the relay server (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub relay_server: bool,
    /// Whether to enable WebSocket transport (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub websocket: bool,
    /// Whether to enable QUIC transport (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub quic: bool,
    /// Whether to enable auto-relay (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub auto_relay: bool,
    /// Whether to enable NAT port mapping (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub port_mapping: bool,
    /// Whether to enable UPnP (only used with rust-ipfs)
    #[cfg(feature = "rust-ipfs")]
    pub upnp: bool,
}

impl Config {
    /// Create a new configuration with default values
    pub fn new(repo_path: PathBuf) -> Self {
        Self {
            repo_path,
            listen_addrs: vec![
                "/ip4/0.0.0.0/tcp/0".parse().unwrap(),
                "/ip6/::/tcp/0".parse().unwrap(),
            ],
            bootstrap_nodes: default_bootstrap_nodes(),
            mdns_enabled: true,
            kademlia_enabled: true,
            #[cfg(feature = "rust-ipfs")]
            dht_server: true,
            #[cfg(feature = "rust-ipfs")]
            relay_client: true,
            #[cfg(feature = "rust-ipfs")]
            relay_server: false,
            #[cfg(feature = "rust-ipfs")]
            websocket: true,
            #[cfg(feature = "rust-ipfs")]
            quic: true,
            #[cfg(feature = "rust-ipfs")]
            auto_relay: true,
            #[cfg(feature = "rust-ipfs")]
            port_mapping: true,
            #[cfg(feature = "rust-ipfs")]
            upnp: true,
        }
    }
}

/// The default path for the IPFS data directory.
pub fn default_ipfs_path() -> PathBuf {
    dirs::data_local_dir()
        .expect("failed to determine local data directory")
        .join("browser")
        .join("ipfs")
}

/// Get the default bootstrap nodes for the IPFS network
fn default_bootstrap_nodes() -> Vec<libp2p::Multiaddr> {
    vec![
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb",
        "/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt",
    ]
    .into_iter()
    .map(|s| s.parse().expect("valid multiaddr"))
    .collect()
}

/// Create a new IPFS node with the given data directory and default configuration
#[cfg(feature = "rust-ipfs")]
pub async fn new_node(data_dir: PathBuf) -> anyhow::Result<Node> {
    let config = Config::new(data_dir);
    Node::new(config)
}

/// Create a new IPFS node with the given configuration
#[cfg(feature = "rust-ipfs")]
pub async fn new_node_with_config(config: Config) -> anyhow::Result<Node> {
    Node::new(config)
}

/// Create a new IPFS node with the given data directory and default configuration (legacy)
#[cfg(feature = "legacy")]
pub async fn new_node(data_dir: PathBuf) -> anyhow::Result<Node> {
    let config = Config::new(data_dir);
    Node::new(config)
}

/// Create a new IPFS node with the given configuration (legacy)
#[cfg(feature = "legacy")]
pub async fn new_node_with_config(config: Config) -> anyhow::Result<Node> {
    Node::new(config)
}
