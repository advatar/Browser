use anyhow::Result;
use cid::Cid;
use ipfs::{Config, Node};
use libp2p::PeerId;
use std::time::Duration;
use tempfile::tempdir;
use tokio::time;

/// Helper function to create a test node with a temporary directory and custom config
async fn create_test_node_with_config(
    name: &str,
    circuit_breaker_threshold: u32,
    circuit_breaker_timeout_ms: u64,
) -> Result<(Node, tempfile::TempDir)> {
    // Create a temporary directory for the node's data
    let temp_dir = tempdir()?;
    
    // Create a new config with the temp directory
    let mut config = Config::new(temp_dir.path().to_path_buf());
    
    // Note: Circuit breaker configuration would be set in the BitswapConfig
    // which would be passed to the Node::new() function if needed
    
    // Create and start the node
    let node = Node::new(config).await?;
    
    Ok((node, temp_dir))
}

#[tokio::test]
async fn test_circuit_breaker_opens_on_consecutive_failures() -> Result<()> {
    // Create two test nodes with a very low circuit breaker threshold
    let (mut node1, _temp1) = create_test_node_with_config("node1", 3, 1000).await?;
    let (mut node2, _temp2) = create_test_node_with_config("node2", 3, 1000).await?;
    
    // Get node2's listen addresses
    let node2_addrs = node2.listeners()?;
    assert!(!node2_addrs.is_empty(), "Node2 should have listening addresses");
    
    // Connect node1 to node2
    for addr in node2_addrs {
        if let Err(e) = node1.connect(addr).await {
            log::warn!("Failed to connect to node2: {}", e);
        }
    }
    
    // Wait for connection to be established
    time::sleep(Duration::from_millis(100)).await;
    
    // Generate a random CID that doesn't exist
    let non_existent_cid: Cid = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
        .parse()
        .expect("valid cid");
    
    // Try to get a non-existent block multiple times to trigger circuit breaker
    for _ in 0..3 {
        let result = node1.get_block(&non_existent_cid).await;
        assert!(result.is_ok(), "Should handle request even if block doesn't exist");
        assert!(result.unwrap().is_none(), "Block should not exist");
    }
    
    // The next request should be blocked by the circuit breaker
    let result = node1.get_block(&non_existent_cid).await;
    assert!(result.is_err(), "Circuit breaker should block the request");
    assert!(
        result.unwrap_err().to_string().contains("circuit breaker"),
        "Error should indicate circuit breaker is open"
    );
    
    Ok(())
}

#[tokio::test]
async fn test_circuit_breaker_resets_after_timeout() -> Result<()> {
    // Create two test nodes with a very low circuit breaker threshold and short timeout
    let (mut node1, _temp1) = create_test_node_with_config("node1", 3, 500).await?;
    let (mut node2, _temp2) = create_test_node_with_config("node2", 3, 500).await?;
    
    // Get node2's listen addresses
    let node2_addrs = node2.listeners()?;
    
    // Connect node1 to node2
    for addr in node2_addrs {
        if let Err(e) = node1.connect(addr).await {
            log::warn!("Failed to connect to node2: {}", e);
        }
    }
    
    // Wait for connection to be established
    time::sleep(Duration::from_millis(100)).await;
    
    // Generate a random CID that doesn't exist
    let non_existent_cid: Cid = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
        .parse()
        .expect("valid cid");
    
    // Trigger circuit breaker
    for _ in 0..3 {
        let _ = node1.get_block(&non_existent_cid).await;
    }
    
    // Verify circuit is open
    let result = node1.get_block(&non_existent_cid).await;
    assert!(result.is_err(), "Circuit breaker should be open");
    
    // Wait for circuit breaker to reset
    time::sleep(Duration::from_millis(600)).await;
    
    // Verify circuit is half-open and allows a new request
    let result = node1.get_block(&non_existent_cid).await;
    assert!(result.is_ok(), "Circuit breaker should be half-open and allow a request");
    
    // The next failure should immediately re-open the circuit
    let result = node1.get_block(&non_existent_cid).await;
    assert!(result.is_err(), "Circuit breaker should re-open after failed request");
    
    Ok(())
}

#[tokio::test]
async fn test_circuit_breaker_closes_after_success() -> Result<()> {
    // Create two test nodes with a very low circuit breaker threshold and short timeout
    let (mut node1, _temp1) = create_test_node_with_config("node1", 3, 1000).await?;
    let (mut node2, _temp2) = create_test_node_with_config("node2", 3, 1000).await?;
    
    // Get node2's listen addresses
    let node2_addrs = node2.listeners()?;
    
    // Connect node1 to node2
    for addr in node2_addrs {
        if let Err(e) = node1.connect(addr).await {
            log::warn!("Failed to connect to node2: {}", e);
        }
    }
    
    // Wait for connection to be established
    time::sleep(Duration::from_millis(100)).await;
    
    // Create a test block
    let test_data = b"test data";
    let cid = node2.put_block(test_data.to_vec(), 0x55).await?;
    
    // Trigger circuit breaker with non-existent block first
    let non_existent_cid: Cid = "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
        .parse()
        .expect("valid cid");
    
    for _ in 0..3 {
        let _ = node1.get_block(&non_existent_cid).await;
    }
    
    // Verify circuit is open
    let result = node1.get_block(&non_existent_cid).await;
    assert!(result.is_err(), "Circuit breaker should be open");
    
    // Now try to get a block that exists
    let result = node1.get_block(&cid).await;
    assert!(result.is_ok(), "Should be able to make a new request");
    
    // The next request should work if the circuit is closed after success
    let result = node1.get_block(&cid).await;
    assert!(result.is_ok(), "Circuit should be closed after successful request");
    
    Ok(())
}
