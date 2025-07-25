use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use cid::Cid;
use futures::channel::oneshot;
use libp2p::{
    identity::Keypair,
    kad::{Kademlia, KademliaConfig, KademliaEvent, QueryId, Record},
    Multiaddr, PeerId,
};
use tokio::sync::Mutex;

use crate::{
    bitswap::{BitswapConfig, BitswapService, BitswapMetrics},
    blockstore::BlockStore,
    config::Config,
    dht::{DhtConfig, DhtEvent, DhtMetrics, DhtService},
    node::NodeEvent,
    Block, IpfsError,
};

/// Implementation of the IPFS Node
pub struct Node {
    /// The underlying IPFS block store
    pub block_store: Arc<dyn BlockStore>,
    
    /// The libp2p PeerId of this node
    pub peer_id: PeerId,
    
    /// The libp2p keypair for this node
    pub keypair: Keypair,
    
    /// The DHT service (if enabled)
    pub dht: Option<DhtService>,
    
    /// The Bitswap service (if enabled)
    pub bitswap: Option<BitswapService>,
    
    /// Pending DHT queries
    pending_dht_queries: Mutex<HashMap<QueryId, (Vec<u8>, oneshot::Sender<Result<Vec<u8>, IpfsError>>)>>,
    
    /// Event sender for node events
    event_sender: tokio::sync::mpsc::Sender<NodeEvent>,
    
    /// Event receiver for node events
    event_receiver: tokio::sync::mpsc::Receiver<NodeEvent>,
}

impl Node {
    /// Create a new IPFS node with the given configuration
    pub async fn new(config: Config) -> Result<Self> {
        // Generate or load keypair
        let keypair = config.keypair.unwrap_or_else(|| Keypair::generate_ed25519());
        let peer_id = keypair.public().to_peer_id();
        
        // Create block store
        let block_store = Arc::new(crate::blockstore::SledBlockStore::new(&config.repo_path)?);
        
        // Create event channel
        let (event_sender, event_receiver) = tokio::sync::mpsc::channel(32);
        
        // Create DHT service if enabled
        let dht = if config.dht_enabled {
            let dht_config = DhtConfig {
                enabled: true,
                protocol_name: "/ipfs/kad/1.0.0".to_string(),
                bootstrap_nodes: config.bootstrap_nodes.clone(),
                ..Default::default()
            };
            
            let registry = prometheus::Registry::new();
            let metrics = DhtMetrics::new(&registry)?;
            
            Some(DhtService::new(peer_id, dht_config, metrics)?)
        } else {
            None
        };
        
        // Create Bitswap service if enabled
        let bitswap = if config.bitswap_enabled {
            let bitswap_config = BitswapConfig::default();
            let metrics = BitswapMetrics::new()?;
            
            Some(BitswapService::new(
                peer_id,
                bitswap_config,
                metrics,
                event_sender.clone(),
            )?)
        } else {
            None
        };
        
        Ok(Self {
            block_store,
            peer_id,
            keypair,
            dht,
            bitswap,
            pending_dht_queries: Mutex::new(HashMap::new()),
            event_sender,
            event_receiver,
        })
    }
    
    /// Start the IPFS node
    pub async fn start(&mut self) -> Result<()> {
        // Start DHT if enabled
        if let Some(dht) = &mut self.dht {
            dht.bootstrap()?;
            log::info!("DHT service started and bootstrapped");
        }
        
        // Start Bitswap if enabled
        if let Some(bitswap) = &mut self.bitswap {
            bitswap.start().await?;
            log::info!("Bitswap service started");
        }
        
        // Start the main event loop
        self.run_event_loop().await;
        
        Ok(())
    }
    
    /// Main event loop for the node
    async fn run_event_loop(&mut self) {
        loop {
            tokio::select! {
                // Handle DHT events
                Some(event) = self.dht.as_mut().and_then(|dht| dht.next_event()) => {
                    if let Err(e) = self.handle_dht_event(event).await {
                        log::error!("Error handling DHT event: {}", e);
                    }
                }
                
                // Handle node events
                Some(event) = self.event_receiver.recv() => {
                    if let Err(e) = self.handle_node_event(event).await {
                        log::error!("Error handling node event: {}", e);
                    }
                }
                
                // Handle other events...
                
                // Exit if all senders are dropped
                else => break,
            }
        }
    }
    
    /// Handle a node event
    async fn handle_node_event(&mut self, event: NodeEvent) -> Result<()> {
        match event {
            NodeEvent::FindPeer { peer_id } => {
                if let Some(dht) = &mut self.dht {
                    dht.find_peer(peer_id).await?;
                }
            }
            NodeEvent::ProvideBlock { cid } => {
                if let Some(dht) = &mut self.dht {
                    dht.provide_block(cid).await?;
                }
            }
            _ => {}
        }
        
        Ok(())
    }
    
    /// Get a block from the local store or network
    pub async fn get_block(&self, cid: &Cid) -> Result<Option<Block>> {
        // First try to get from local store
        if let Some(block) = self.block_store.get(cid)? {
            return Ok(Some(block));
        }
        
        // If not found, try to get from network via Bitswap
        if let Some(bitswap) = &self.bitswap {
            if let Some(block) = bitswap.get_block(cid).await? {
                // Store the block locally for future use
                self.block_store.put(&block)?;
                return Ok(Some(block));
            }
        }
        
        Ok(None)
    }
    
    /// Put a block into the local store and announce it
    pub async fn put_block(&self, block: Block) -> Result<()> {
        // Store the block locally
        self.block_store.put(&block)?;
        
        // Announce the block to the DHT if enabled
        if let Some(dht) = &self.dht {
            dht.provide_block(*block.cid()).await?;
        }
        
        Ok(())
    }
}

#[async_trait]
impl crate::dht_api::DhtApi for Node {
    async fn get_value(&mut self, key: Vec<u8>) -> Result<Option<Vec<u8>>> {
        if let Some(dht) = &mut self.dht {
            let (sender, receiver) = oneshot::channel();
            let query_id = dht.get_value(key.clone());
            
            // Store the sender to be used when the query completes
            self.pending_dht_queries.lock().await.insert(query_id, (key, sender));
            
            // Wait for the result with a timeout
            match tokio::time::timeout(Duration::from_secs(30), receiver).await {
                Ok(Ok(Ok(value))) => Ok(Some(value)),
                Ok(Ok(Err(e)))) => Err(e.into()),
                Ok(Err(_)) => Err(anyhow::anyhow!("DHT query channel closed")),
                Err(_) => Err(anyhow::anyhow!("DHT query timed out")),
            }
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }
    
    // Implement other DHT API methods...
    
    async fn bootstrap(&mut self) -> Result<()> {
        if let Some(dht) = &mut self.dht {
            dht.bootstrap()
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }
    
    fn handle_dht_event(&mut self, event: DhtEvent) -> Result<Option<NodeEvent>> {
        // Forward to the DhtApi implementation
        <Self as crate::dht_api::DhtApi>::handle_dht_event(self, event)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    
    #[tokio::test]
    async fn test_node_creation() -> Result<()> {
        let temp_dir = tempdir()?;
        let config = Config {
            repo_path: temp_dir.path().to_path_buf(),
            dht_enabled: true,
            bitswap_enabled: true,
            ..Default::default()
        };
        
        let node = Node::new(config).await?;
        assert_eq!(node.peer_id, node.keypair.public().to_peer_id());
        
        Ok(())
    }
    
    #[tokio::test]
    async fn test_block_operations() -> Result<()> {
        let temp_dir = tempdir()?;
        let config = Config {
            repo_path: temp_dir.path().to_path_buf(),
            dht_enabled: false,
            bitswap_enabled: false,
            ..Default::default()
        };
        
        let node = Node::new(config).await?;
        
        // Create a test block
        let data = b"test data".to_vec();
        let block = Block::new(data)?;
        let cid = *block.cid();
        
        // Put the block
        node.put_block(block).await?;
        
        // Get the block back
        let retrieved = node.get_block(&cid).await?;
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().data(), b"test data");
        
        Ok(())
    }
}
