//! IPFS implementation for the decentralized browser.
//!
//! This crate provides IPFS functionality including block storage,
//! content addressing, and peer-to-peer networking with enhanced
//! features like Kademlia DHT and mDNS for peer discovery.
//!
//! # Features
//! - `legacy`: Enable the legacy ipfs-embed based implementation
//! - `rust-ipfs`: Enable the new rust-ipfs based implementation (default)

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
#[cfg(feature = "rust-ipfs")]
pub use ipfs_node::{Config, Node, NodeEvent};

/// Configuration for the IPFS node
#[derive(Debug, Clone)]
pub struct Config {
    /// Path to the repository
    pub repo_path: PathBuf,
    /// Listen addresses for the node
    pub listen_addrs: Vec<libp2p::Multiaddr>,
    /// Bootstrap nodes to connect to
    pub bootstrap_nodes: Vec<libp2p::Multiaddr>,
    /// Maximum block size in bytes
    pub storage_max_block_size: usize,
    /// Maximum number of blocks to store
    pub storage_max_block_count: usize,
    /// Whether to enable mDNS for local peer discovery
    pub mdns_enabled: bool,
    /// Whether to enable Kademlia DHT for peer and content routing
    pub kademlia_enabled: bool,
}

impl Config {
    /// Create a new configuration with default values
    pub fn new(repo_path: PathBuf) -> Self {
        Self {
            repo_path,
            listen_addrs: vec!["/ip4/0.0.0.0/tcp/0".parse().expect("valid multiaddr")],
            bootstrap_nodes: default_bootstrap_nodes(),
            storage_max_block_size: 1024 * 1024, // 1MB
            storage_max_block_count: 1000,
            mdns_enabled: true,
            kademlia_enabled: true,
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
pub async fn new_node(data_dir: PathBuf) -> anyhow::Result<Node> {
    let config = Config::new(data_dir);
    Node::new(config).await
}

/// Create a new IPFS node with the given configuration
pub async fn new_node_with_config(config: Config) -> anyhow::Result<Node> {
    Node::new(config).await
}
