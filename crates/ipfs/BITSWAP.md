# Bitswap Protocol Implementation

## Overview

Bitswap is the data trading module for IPFS that handles requesting and sending blocks to and from other peers in the network. This document provides an overview of the implementation, configuration options, and usage examples.

## Features

- Support for multiple Bitswap protocol versions (1.0.0, 1.1.0, 1.2.0)
- Efficient block exchange with peer scoring
- Circuit breaking for fault tolerance
- Bandwidth management and rate limiting
- Comprehensive metrics and monitoring
- Connection management and peer prioritization

## Configuration

The Bitswap protocol can be configured using the `BitswapConfig` struct with the following options:

```rust
pub struct BitswapConfig {
    /// Maximum number of concurrent connections
    pub max_connections: usize,
    /// Bandwidth limit in bytes per second (None for no limit)
    pub bandwidth_limit: Option<usize>,
    /// Protocol version to use (default: 1.2.0)
    pub protocol_version: Vec<u8>,
    /// Window duration for bandwidth measurement
    pub bandwidth_window: Duration,
}
```

### Default Configuration

```rust
impl Default for BitswapConfig {
    fn default() -> Self {
        Self {
            max_connections: 100,
            bandwidth_limit: None, // No limit by default
            protocol_version: BITSWAP_120.to_vec(),
            bandwidth_window: Duration::from_secs(1),
        }
    }
}
```

## Usage

### Creating a Bitswap Service

```rust
use ipfs::{Node, Config};
use libp2p::PeerId;
use tokio::sync::mpsc;
use prometheus::Registry;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Create a channel for node events
    let (event_sender, _event_receiver) = mpsc::channel(32);
    
    // Create a new node with default configuration
    let node = Node::new(Config::default()).await?;
    
    // Start the node
    node.start().await?;
    
    Ok(())
}
```

### Requesting Blocks

```rust
use cid::Cid;
use libp2p_bitswap::Priority;

async fn request_block(node: &mut Node, cid: Cid) -> anyhow::Result<Vec<u8>> {
    // Request a block with high priority
    match node.get_block(&cid, Some(std::time::Duration::from_secs(10))).await? {
        Some(data) => Ok(data),
        None => Err(anyhow::anyhow!("Block not found")),
    }
}
```

### Providing Blocks

```rust
use cid::Cid;

async fn provide_block(node: &mut Node, data: Vec<u8>) -> anyhow::Result<Cid> {
    // Store and announce the block to the network
    node.put_block(data, None, None).await
}
```

## Metrics

The following metrics are exposed via Prometheus:

- `bitswap_blocks_received`: Total blocks received
- `bitswap_blocks_sent`: Total blocks sent
- `bitswap_blocks_not_found`: Total blocks not found
- `bitswap_active_peers`: Number of active peers
- `bitswap_wantlist_size`: Current size of the wantlist
- `bitswap_bandwidth_in`: Incoming bandwidth usage in bytes
- `bitswap_bandwidth_out`: Outgoing bandwidth usage in bytes
- `bitswap_connection_errors`: Connection errors
- `bitswap_bandwidth_limit_exceeded`: Times bandwidth limit was exceeded

## Circuit Breaking

Bitswap implements circuit breaking to handle failing peers and requests:

- **Failure Threshold**: 5 consecutive failures
- **Reset Timeout**: 30 seconds before attempting to close the circuit
- **Half-Open State**: After timeout, allows one request to test connectivity

## Performance Considerations

1. **Connection Management**: The `ConnectionManager` handles connection limits and queuing
2. **Bandwidth Management**: Bandwidth usage is tracked and can be limited
3. **Peer Scoring**: Peers are scored based on performance and reliability
4. **Request Deduplication`: Duplicate block requests are deduplicated

## Troubleshooting

### Common Issues

1. **Connection Failures**:
   - Check peer connectivity
   - Verify network configuration (NAT, firewalls)
   - Check peer addresses and protocols

2. **Slow Transfers**:
   - Monitor bandwidth usage and limits
   - Check peer scores and connection quality
   - Review request priorities

3. **Memory Usage**:
   - Monitor block cache size
   - Adjust connection and request limits if needed

## Example: Basic File Transfer

```rust
use ipfs::{Node, Config};
use cid::Cid;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Create two nodes
    let (mut node1, _) = Node::new(Config::default()).await?;
    let (mut node2, _) = Node::new(Config::default()).await?;
    
    // Start nodes
    node1.start().await?;
    node2.start().await?;
    
    // Connect node1 to node2
    let addrs = node2.listen_addrs()?;
    for addr in addrs {
        node1.connect(addr).await?;
    }
    
    // Put data on node2
    let data = b"Hello, Bitswap!".to_vec();
    let cid = node2.put_block(data.clone(), None, None).await?;
    
    // Get data from node1
    let retrieved = node1.get_block(&cid, Some(std::time::Duration::from_secs(10))).await?;
    
    assert_eq!(retrieved, Some(data));
    println!("Successfully transferred block: {}", cid);
    
    Ok(())
}
```

## Security Considerations

- All peer-to-peer communication is encrypted
- Block data is verified using content addressing (CIDs)
- Bandwidth limits help prevent resource exhaustion
- Circuit breakers protect against misbehaving peers
