//! IPFS implementation for the decentralized browser.
//!
//! This crate provides IPFS functionality including block storage,
//! content addressing, and peer-to-peer networking.
//!
//! ```ignore
//! use std::path::PathBuf;
//!
//! # async fn example() -> anyhow::Result<()> {
//! let node = ipfs::new_node(PathBuf::from("/tmp/ipfs-doc")).await?;
//! println!("Local peer id: {:?}", node.local_peer_id());
//! # Ok(())
//! # }
//! ```

#![deny(missing_docs)]
#![forbid(unsafe_code)]

pub mod blockstore;
pub mod ipfs;

pub use crate::ipfs::{Block, BlockStore, Config, Error, EventStream, Node, NodeEvent, Result};
/// Re-export commonly used types from the `ipfs` module.
pub use blockstore::SledStore;
pub use cid::Cid;
pub use libipld;
pub use libp2p::{Multiaddr, PeerId};
pub use multihash;

use std::path::PathBuf;

// Types are defined in `crate::ipfs` and re-exported above.

// Traits are defined in `crate::ipfs` and re-exported above.

// Errors are defined in `crate::ipfs` and re-exported above.

// Result alias is defined in `crate::ipfs` and re-exported above.

// EventStream is defined in `crate::ipfs` and re-exported above.

// NodeEvent is defined in `crate::ipfs` and re-exported above.

// Config is defined in `crate::ipfs` and re-exported above.

// Helpers are defined in `crate::ipfs`.

// Helpers are defined in `crate::ipfs`.

/// Create a new IPFS node with the given data directory and default configuration.
pub async fn new_node(data_dir: PathBuf) -> anyhow::Result<Node> {
    let config = Config::new(data_dir);
    new_node_with_config(config).await
}

/// Create a new IPFS node with the given configuration.
pub async fn new_node_with_config(config: Config) -> anyhow::Result<Node> {
    crate::ipfs::Node::new(config).await.map_err(Into::into)
}
