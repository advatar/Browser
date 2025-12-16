//! Example demonstrating block exchange between two nodes using Bitswap.
//!
//! This example creates two IPFS nodes, connects them, and demonstrates block exchange.

#![cfg(feature = "legacy")] // Retired by default: example depends on legacy Node API
use anyhow::Result;
use cid::Cid;
use futures::StreamExt;
use ipfs::{Config, Node, SledStore};
use libp2p::identity::Keypair;
use std::path::PathBuf;
use std::time::Duration;
use tokio::time;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    env_logger::Builder::from_default_env()
        .filter_level(log::LevelFilter::Info)
        .init();

    println!("Starting Bitswap block exchange example...");

    // Create a temporary directory for node1's data
    let temp_dir1 = tempfile::tempdir()?;
    let node1 = create_node("Node 1", temp_dir1.path().to_path_buf()).await?;

    // Create a temporary directory for node2's data
    let temp_dir2 = tempfile::tempdir()?;
    let mut node2 = create_node("Node 2", temp_dir2.path().to_path_buf()).await?;

    // Get node1's listen addresses
    let node1_addrs = node1.listen_addrs().await?;
    println!("Node 1 listening on: {:?}", node1_addrs);

    // Connect node2 to node1
    for addr in node1_addrs {
        if let Err(e) = node2.connect(addr).await {
            log::warn!("Failed to connect to node1: {}", e);
        }
    }

    println!("Waiting for nodes to connect...");
    time::sleep(Duration::from_secs(2)).await;

    // Create some test data on node1
    let test_data = b"Hello from Node 1 via Bitswap!".to_vec();
    println!(
        "Storing data on Node 1: {}",
        String::from_utf8_lossy(&test_data)
    );

    let cid = node1.put_block(test_data.clone()).await?;
    println!("Stored data with CID: {}", cid);

    // Wait for DHT propagation
    println!("Waiting for DHT propagation...");
    time::sleep(Duration::from_secs(2)).await;

    // Try to retrieve the data from node2
    println!("Retrieving data from Node 2...");
    if let Some(retrieved_data) = node2.get_block(&cid).await? {
        let message = String::from_utf8_lossy(&retrieved_data);
        println!("Node 2 retrieved data: {}", message);
        assert_eq!(retrieved_data, test_data);
    } else {
        println!("Failed to retrieve data from Node 2");
    }

    // Keep the nodes running for a bit to observe the exchange
    println!("Block exchange complete. Press Ctrl+C to exit...");
    time::sleep(Duration::from_secs(10)).await;

    Ok(())
}

/// Helper function to create and start a node with the given name and data directory
async fn create_node(name: &str, data_dir: PathBuf) -> Result<Node> {
    println!("Creating {}...", name);

    // Generate a random keypair for the node
    let keypair = Keypair::generate_ed25519();

    // Create a config with the data directory
    let config = Config::default()
        .with_keypair(keypair)
        .with_repo_path(data_dir.clone())
        .with_listen_addr("/ip4/0.0.0.0/tcp/0".parse()?);

    // Create a new Sled store
    let store = SledStore::open(data_dir.join("blocks"))?;

    // Create and start the node
    let mut node = Node::new(config, store).await?;
    node.start().await?;

    // Spawn a task to process node events
    let mut events = node.events();
    let node_name = name.to_string();
    tokio::spawn(async move {
        while let Some(event) = events.next().await {
            match event {
                ipfs::NodeEvent::PeerDiscovered(peer_id) => {
                    println!("{}: Discovered peer: {}", node_name, peer_id);
                }
                ipfs::NodeEvent::BlockReceived(cid) => {
                    println!("{}: Received block: {}", node_name, cid);
                }
                _ => {}
            }
        }
    });

    Ok(node)
}
