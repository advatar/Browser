#![cfg(feature = "legacy")] // Retired by default: depends on legacy Node API (start, listen_addrs, DHT ops)
use anyhow::Result;
use cid::Cid;
use ipfs::{Block, Config, Node};
use libp2p::PeerId;
use std::time::Duration;
use tempfile::tempdir;

/// Helper function to create a test node with DHT enabled
async fn create_test_node() -> Result<(Node, tempfile::TempDir)> {
    let temp_dir = tempdir()?;
    let config = Config {
        repo_path: temp_dir.path().to_path_buf(),
        dht_enabled: true,
        bitswap_enabled: true,
        ..Default::default()
    };
    
    let node = Node::new(config).await?;
    Ok((node, temp_dir))
}

#[tokio::test]
async fn test_dht_bootstrap() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Start the first node
    node1.start().await?;
    
    // Get the first node's listen addresses
    let node1_addrs = node1.listen_addrs()?;
    assert!(!node1_addrs.is_empty(), "Node1 should have listening addresses");
    
    // Start the second node and connect to the first
    node2.start().await?;
    
    // Connect node2 to node1
    for addr in &node1_addrs {
        if let Err(e) = node2.connect(addr.clone()).await {
            log::warn!("Failed to connect to node1: {}", e);
        }
    }
    
    // Wait for connection to be established
    tokio::time::sleep(Duration::from_secs(1)).await;
    
    // Check that both nodes know about each other in the DHT
    let node1_peers = node1.list_peers().await?;
    let node2_peers = node2.list_peers().await?;
    
    assert!(
        node1_peers.contains(&node2.peer_id()),
        "Node1 should know about Node2"
    );
    assert!(
        node2_peers.contains(&node1.peer_id()),
        "Node2 should know about Node1"
    );
    
    Ok(())
}

#[tokio::test]
async fn test_dht_put_get() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Start both nodes
    node1.start().await?;
    node2.start().await?;
    
    // Connect node2 to node1
    let node1_addrs = node1.listen_addrs()?;
    for addr in &node1_addrs {
        if let Err(e) = node2.connect(addr.clone()).await {
            log::warn!("Failed to connect to node1: {}", e);
        }
    }
    
    // Wait for connection to be established
    tokio::time::sleep(Duration::from_secs(1)).await;
    
    // Create a test key-value pair
    let key = b"test_key".to_vec();
    let value = b"test_value".to_vec();
    
    // Put the value in the DHT via node1
    node1.put_value(key.clone(), value.clone()).await?;
    
    // Get the value from the DHT via node2
    let result = node2.get_value(key).await?;
    
    // Verify we got the correct value back
    assert_eq!(result, Some(value));
    
    Ok(())
}

#[tokio::test]
async fn test_dht_provide_find() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Start both nodes
    node1.start().await?;
    node2.start().await?;
    
    // Connect node2 to node1
    let node1_addrs = node1.listen_addrs()?;
    for addr in &node1_addrs {
        if let Err(e) = node2.connect(addr.clone()).await {
            log::warn!("Failed to connect to node1: {}", e);
        }
    }
    
    // Wait for connection to be established
    tokio::time::sleep(Duration::from_secs(1)).await;
    
    // Create a test block
    let data = b"test block data".to_vec();
    let block = Block::new(data)?;
    let cid = *block.cid();
    
    // Store the block in node1's local store
    node1.put_block(block).await?;
    
    // Announce that node1 provides this block
    node1.provide_block(cid).await?;
    
    // Try to find providers for the block from node2
    let providers = node2.find_providers(cid).await?;
    
    // Verify that node1 is in the list of providers
    assert!(
        providers.contains(&node1.peer_id()),
        "Node1 should be in the list of providers for the block"
    );
    
    Ok(())
}

#[tokio::test]
async fn test_dht_find_peer() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Start both nodes
    node1.start().await?;
    node2.start().await?;
    
    // Connect node2 to node1
    let node1_addrs = node1.listen_addrs()?;
    for addr in &node1_addrs {
        if let Err(e) = node2.connect(addr.clone()).await {
            log::warn!("Failed to connect to node1: {}", e);
        }
    }
    
    // Wait for connection to be established
    tokio::time::sleep(Duration::from_secs(1)).await;
    
    // Find node1 from node2 using the DHT
    let peer_id = node1.peer_id();
    let peers = node2.find_peer(peer_id).await?;
    
    // Verify we found node1's address
    assert!(!peers.is_empty(), "Should find at least one peer address");
    
    Ok(())
}

#[tokio::test]
async fn test_dht_large_value() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Start both nodes
    node1.start().await?;
    node2.start().await?;
    
    // Connect node2 to node1
    let node1_addrs = node1.listen_addrs()?;
    for addr in &node1_addrs {
        if let Err(e) = node2.connect(addr.clone()).await {
            log::warn!("Failed to connect to node1: {}", e);
        }
    }
    
    // Wait for connection to be established
    tokio::time::sleep(Duration::from_secs(1)).await;
    
    // Create a large value (larger than a single DHT record)
    let key = b"large_value".to_vec();
    let mut value = vec![0u8; 1024 * 1024]; // 1MB value
    for (i, byte) in value.iter_mut().enumerate() {
        *byte = (i % 256) as u8;
    }
    
    // Put the large value in the DHT via node1
    node1.put_value(key.clone(), value.clone()).await?;
    
    // Get the value from the DHT via node2
    let result = node2.get_value(key).await?;
    
    // Verify we got the correct value back
    assert_eq!(result, Some(value));
    
    Ok(())
}
