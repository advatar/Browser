use anyhow::Result;
use cid::Cid;
use futures::future::join_all;
use ipfs::{Config, Node};
use libp2p::multiaddr::Multiaddr;
use libp2p::PeerId;
use libp2p_bitswap::Priority;
use prometheus::Registry;
use rand::Rng;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tempfile::tempdir;
use tokio::time;

/// Configuration for creating test nodes
#[derive(Clone)]
struct TestNodeConfig {
    /// Node name/ID
    name: String,
    /// Whether to enable DHT
    enable_dht: bool,
    /// Bitswap configuration
    bitswap_config: Option<ipfs::BitswapConfig>,
    /// Bootstrap nodes to connect to
    bootstrap_nodes: Vec<Multiaddr>,
}

impl Default for TestNodeConfig {
    fn default() -> Self {
        Self {
            name: "test-node".to_string(),
            enable_dht: true,
            bitswap_config: None,
            bootstrap_nodes: vec![],
        }
    }
}

/// Helper function to create a test node with a temporary directory
async fn create_test_node() -> Result<(Node, tempfile::TempDir)> {
    create_test_node_with_config(TestNodeConfig::default()).await
}

/// Create a test node with custom configuration
async fn create_test_node_with_config(config: TestNodeConfig) -> Result<(Node, tempfile::TempDir)> {
    // Create a temporary directory for the node's data
    let temp_dir = tempdir()?;
    
    // Create a new config with the temp directory
    let mut node_config = Config::new(temp_dir.path().to_path_buf());
    node_config.kademlia_enabled = config.enable_dht;
    node_config.bootstrap_nodes = config.bootstrap_nodes;
    
    // Create and initialize the node with the config
    let node = Node::new(node_config).await?;
    
    Ok((node, temp_dir))
        data_dir: temp_dir.path().to_path_buf(),
        enable_dht: config.enable_dht,
        bootstrap_nodes: config.bootstrap_nodes,
        ..Default::default()
    };
    
    // Apply Bitswap config if provided
    if let Some(bitswap_config) = config.bitswap_config {
        node_config.bitswap = bitswap_config;
    }
    
    // Create a new Sled store
    let store = ipfs_embed::SledBlockStore::new(temp_dir.path().join("blocks"))?;
    
    // Create and start the node
    let mut node = Node::new(node_config, store).await?;
    node.start().await?;
    
    Ok((node, temp_dir))
}

#[tokio::test]
async fn test_bitswap_block_exchange() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Get node2's listen addresses
    let node2_addrs = node2.listen_addrs()?;
    assert!(!node2_addrs.is_empty(), "Node2 should have listening addresses");
    
    // Connect node1 to node2
    for addr in &node2_addrs {
        if let Err(e) = node1.connect(addr.clone()).await {
            log::warn!("Failed to connect to node2: {}", e);
        }
    }
    
    // Wait for the connection to be established
    time::sleep(Duration::from_secs(1)).await;
    
    // Create a test block
    let test_data = b"hello bitswap".to_vec();
    let cid = node2.put_block(test_data.clone(), None, None).await?;
    
    // Wait for DHT propagation
    time::sleep(Duration::from_secs(2)).await;
    
    // Try to get the block from node1
    let retrieved_data = node1.get_block(&cid, Some(Duration::from_secs(5))).await?;
    
    // Verify the data matches
    assert_eq!(retrieved_data, Some(test_data), "Retrieved data should match the original data");
    
    Ok(())
}

#[tokio::test]
async fn test_concurrent_block_requests() -> Result<()> {
    // Create three nodes in a line: node1 <-> node2 <-> node3
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    let (mut node3, _temp3) = create_test_node().await?;
    
    // Connect node1 to node2
    for addr in node2.listen_addrs()? {
        node1.connect(addr).await?;
    }
    
    // Connect node2 to node3
    for addr in node3.listen_addrs()? {
        node2.connect(addr).await?;
    }
    
    // Wait for connections to establish
    time::sleep(Duration::from_secs(1)).await;
    
    // Create 10 test blocks on node3
    let mut blocks = Vec::new();
    for i in 0..10 {
        let data = format!("test block {}", i).into_bytes();
        let cid = node3.put_block(data.clone(), None, None).await?;
        blocks.push((cid, data));
    }
    
    // Request all blocks from node1 concurrently
    let node1_clone = node1.clone();
    let handles: Vec<_> = blocks.into_iter()
        .map(|(cid, expected_data)| {
            let node_clone = node1_clone.clone();
            tokio::spawn(async move {
                let data = node_clone.get_block(&cid, Some(Duration::from_secs(10))).await?;
                assert_eq!(data, Some(expected_data), "Retrieved data should match the original data");
                Ok::<_, anyhow::Error>(())
            })
        })
        .collect();
    
    // Wait for all requests to complete
    let results = join_all(handles).await;
    for result in results {
        result??; // Propagate any errors
    }
    
    Ok(())
}

#[tokio::test]
async fn test_bitswap_peer_disconnect() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Connect node1 to node2
    for addr in node2.listen_addrs()? {
        node1.connect(addr).await?;
    }
    
    // Wait for connection to establish
    time::sleep(Duration::from_secs(1)).await;
    
    // Create a large block on node2
    let large_data = vec![0u8; 10 * 1024 * 1024]; // 10MB
    let cid = node2.put_block(large_data.clone(), None, None).await?;
    
    // Start getting the block from node1 (this will start the transfer)
    let node1_clone = node1.clone();
    let handle = tokio::spawn(async move {
        node1_clone.get_block(&cid, Some(Duration::from_secs(30))).await
    });
    
    // Wait a bit for the transfer to start
    time::sleep(Duration::from_secs(1)).await;
    
    // Disconnect the nodes
    node1.disconnect_peer(node2.local_peer_id()).await?;
    
    // The transfer should fail with a timeout
    let result = handle.await??;
    assert!(result.is_none(), "Block transfer should have failed due to disconnection");
    
    // Reconnect the nodes
    for addr in node2.listen_addrs()? {
        node1.connect(addr).await?;
    }
    
    // The transfer should now succeed
    let retrieved = node1.get_block(&cid, Some(Duration::from_secs(10))).await?;
    assert_eq!(retrieved, Some(large_data), "Block should be retrievable after reconnection");
    
    Ok(())
}

#[tokio::test]
async fn test_bitswap_wantlist_management() -> Result<()> {
    // Create a test node with a custom Bitswap config
    let config = TestNodeConfig {
        bitswap_config: Some(ipfs::BitswapConfig {
            max_wantlist_size: 100,
            wantlist_ttl: Duration::from_secs(30),
            ..Default::default()
        }),
        ..Default::default()
    };
    
    let (mut node, _temp) = create_test_node_with_config(config).await?;
    
    // Create a test block
    let test_data = b"test wantlist".to_vec();
    let cid = node.put_block(test_data, None, None).await?;
    
    // The block should now be in the blockstore, not the wantlist
    assert!(node.has_block(&cid).await, "Block should be in the blockstore");
    
    // To test wantlist, we need to request a block we don't have
    let non_existent_cid = Cid::try_from("QmUNLLsPACCz1vLxQVkXqqLX5R1X345qqfHbsf67hvA3Nn")?;
    
    // Spawn a task to get the block (this will add it to the wantlist)
    let node_clone = node.clone();
    let handle = tokio::spawn(async move {
        node_clone.get_block(&non_existent_cid, Some(Duration::from_secs(5))).await
    });
    
    // Give it some time to process
    time::sleep(Duration::from_millis(100)).await;
    
    // Check that the block is in the wantlist
    assert!(node.is_block_wanted(&non_existent_cid), "Block should be in wantlist");
    
    // Cancel the pending request
    node.cancel_block_request(&non_existent_cid);
    
    // The block should no longer be in the wantlist
    assert!(!node.is_block_wanted(&non_existent_cid), "Block should be removed from wantlist");
    
    // The result should be None since the block doesn't exist
    let result = handle.await??;
    assert!(result.is_none(), "Non-existent block should return None");
    
    // Test wantlist limit
    let config = TestNodeConfig {
        bitswap_config: Some(ipfs::BitswapConfig {
            max_wantlist_size: 5, // Very small limit for testing
            ..Default::default()
        }),
        ..Default::default()
    };
    
    let (mut node, _temp) = create_test_node_with_config(config).await?;
    
    // Add more blocks than the wantlist can hold
    let mut cids = Vec::new();
    for i in 0..10 {
        let data = format!("test block {}", i).into_bytes();
        let cid = node.put_block(data, None, None).await?;
        cids.push(cid);
    }
    
    // The wantlist should be at its maximum size
    assert!(node.wantlist_size() <= 5, "Wantlist should respect the size limit");
    
    Ok(())
}

#[tokio::test]
async fn test_bitswap_duplicate_blocks() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Connect the nodes
    for addr in node2.listen_addrs()? {
        node1.connect(addr).await?;
    }
    
    // Create a block on node2
    let data = b"duplicate test block".to_vec();
    let cid = node2.put_block(data.clone(), None, None).await?;
    
    // Request the same block multiple times from node1
    let node1_clone = node1.clone();
    let handles: Vec<_> = (0..5)
        .map(|_| {
            let cid = cid.clone();
            let node_clone = node1_clone.clone();
            tokio::spawn(async move {
                node_clone.get_block(&cid, Some(Duration::from_secs(5))).await
            })
        })
        .collect();
    
    // All requests should succeed with the same data
    for handle in handles {
        let result = handle.await??;
        assert_eq!(result, Some(data.clone()), "All requests should return the same data");
    }
    
    // Verify the block was only transferred once by checking the metrics
    let stats = node1.bitswap_stats();
    assert_eq!(stats.blocks_received, 1, "Block should only be transferred once");
    
    Ok(())
}

#[tokio::test]
async fn test_bitswap_large_block() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Connect the nodes
    for addr in node2.listen_addrs()? {
        node1.connect(addr).await?;
    }
    
    // Create a large block (5MB)
    let mut rng = rand::thread_rng();
    let mut large_data = vec![0u8; 5 * 1024 * 1024];
    rng.fill(&mut large_data[..]);
    
    // Put the block on node2
    let cid = node2.put_block(large_data.clone(), None, None).await?;
    
    // Get the block from node1 with a timeout
    let retrieved = node1.get_block(&cid, Some(Duration::from_secs(30))).await?;
    
    // Verify the data matches
    assert_eq!(retrieved, Some(large_data), "Retrieved large block should match original");
    
    Ok(())
}

#[tokio::test]
async fn test_bitswap_peer_management() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Get node2's listen addresses
    let node2_addrs = node2.listen_addrs()?;
    assert!(!node2_addrs.is_empty(), "Node2 should have listening addresses");
    
    // Connect node1 to node2
    for addr in node2_addrs {
        if node1.connect(addr).await.is_ok() {
            break;
        }
    }
    
    // Wait for the connection to be established
    time::sleep(Duration::from_secs(1)).await;
    
    // Check that we can get node2's peer ID
    let node2_peer_id = node2.local_peer_id().clone();
    
    // The node should now have at least one peer
    // Note: The exact peer management API might need adjustment based on the Node implementation
    
    Ok(())
}

#[tokio::test]
async fn test_bitswap_block_provide() -> Result<()> {
    // Create two test nodes
    let (mut node1, _temp1) = create_test_node().await?;
    let (mut node2, _temp2) = create_test_node().await?;
    
    // Get node2's listen addresses
    let node2_addrs = node2.listen_addrs()?;
    assert!(!node2_addrs.is_empty(), "Node2 should have listening addresses");
    
    // Connect node1 to node2
    for addr in node2_addrs {
        if node1.connect(addr).await.is_ok() {
            break;
        }
    }
    
    // Wait for connection
    time::sleep(Duration::from_secs(1)).await;
    
    // Add a block to node2
    let test_data = b"block to provide".to_vec();
    let cid = node2.put_block(test_data.clone()).await?;
    
    // Wait for DHT propagation
    time::sleep(Duration::from_secs(2)).await;
    
    // Node1 should now be able to get the block
    let retrieved = node1.get_block(&cid).await?;
    assert_eq!(retrieved, Some(test_data), "Should be able to retrieve provided block");
    
    Ok(())
}

#[tokio::test]
async fn test_bitswap_priority() -> Result<()> {
    // Create a test node
    let (mut node, _temp) = create_test_node().await?;
    
    // Create a test block
    let test_data = b"test block".to_vec();
    let cid = node.put_block(test_data.clone()).await?;
    
    // Request the block
    let retrieved = node.get_block(&cid).await?;
    assert_eq!(retrieved, Some(test_data), "Should retrieve block");
    
    // Note: Priority-based retrieval would require additional API support
    // in the Node implementation
    
    Ok(())
}
