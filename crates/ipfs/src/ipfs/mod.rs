//! IPFS implementation for the decentralized browser.
//!
//! This module provides the core IPFS functionality including block storage,
//! content addressing, and peer-to-peer networking.

#![deny(missing_docs)]
#![warn(rust_2018_idioms)]

mod block;
mod config;
mod error;
mod node;
mod node_modern;
mod repo;

// Public exports
pub use self::{
    block::Block,
    config::Config,
    error::{Error, Result},
    node_modern::Node as ModernNode,
    node::Node as LegacyNode,
    repo::Repo,
};

// Re-export common types
pub use cid::Cid;
pub use libp2p::{Multiaddr, PeerId};
pub use multihash;
pub use libipld;

/// The main IPFS node type that switches between implementations based on features.
#[cfg(all(feature = "rust-ipfs", not(feature = "legacy")))]
pub type Node = ModernNode;

/// The main IPFS node type that switches between implementations based on features.
#[cfg(feature = "legacy")]
pub type Node = LegacyNode;

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

/// A stream of node events
pub type EventStream = futures::channel::mpsc::Receiver<NodeEvent>;

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
