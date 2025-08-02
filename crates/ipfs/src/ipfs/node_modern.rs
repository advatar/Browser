//! Modern IPFS node implementation using rust-ipfs.

use crate::ipfs::{Block, BlockStore, Config, Error, NodeEvent, Result};
use async_trait::async_trait;
use futures::{
    channel::{mpsc, oneshot},
    Stream, StreamExt,
};
use libp2p::{
    core::{muxing::StreamMuxerBox, transport::Boxed, upgrade},
    identity::Keypair,
    mplex, noise,
    swarm::{NetworkBehaviour, Swarm, SwarmBuilder, SwarmEvent},
    tcp, yamux, Multiaddr, PeerId, Transport,
};
use rust_ipfs::{Ipfs, IpfsOptions, Node as IpfsNode, TestTypes, UninitializedIpfs};
use std::{
    collections::HashSet,
    sync::{Arc, Mutex},
    time::Duration,
};

/// A modern IPFS node implementation using rust-ipfs.
pub struct Node {
    /// The underlying rust-ipfs node.
    ipfs: Ipfs<TestTypes>,
    /// The node's peer ID.
    peer_id: PeerId,
    /// Channel for sending commands to the node.
    command_sender: mpsc::Sender<NodeCommand>,
    /// Channel for receiving events from the node.
    event_receiver: mpsc::Receiver<NodeEvent>,
    /// Set of connected peers.
    connected_peers: Arc<Mutex<HashSet<PeerId>>>,
}

/// Commands that can be sent to the node.
pub enum NodeCommand {
    /// Connect to a peer.
    Connect(PeerId, Vec<Multiaddr>),
    /// Disconnect from a peer.
    Disconnect(PeerId),
    /// Add a block to the node.
    AddBlock(Block),
    /// Get a block from the node.
    GetBlock(Cid, oneshot::Sender<Result<Option<Block>>>>,
    /// Check if a block exists.
    HasBlock(Cid, oneshot::Sender<bool>),
    /// Shut down the node.
    Shutdown,
}

impl Node {
    /// Create a new IPFS node with the given configuration.
    pub async fn new(config: Config) -> Result<Self> {
        // Initialize the rust-ipfs node
        let options = IpfsOptions::inmemory_with_generated_keys();
        let (ipfs, fut) = UninitializedIpfs::new(options).start().await?;
        
        // Start the node's background task
        tokio::spawn(fut);
        
        // Create channels for commands and events
        let (command_sender, command_receiver) = mpsc::channel(32);
        let (event_sender, event_receiver) = mpsc::channel(32);
        
        // Initialize connected peers set
        let connected_peers = Arc::new(Mutex::new(HashSet::new()));
        
        // Start the node's background tasks
        let node = Self {
            ipfs: ipfs.clone(),
            peer_id: ipfs.keypair().public().to_peer_id(),
            command_sender,
            event_receiver,
            connected_peers: connected_peers.clone(),
        };
        
        // Start the node's background tasks
        node.start_background_tasks(ipfs, command_receiver, event_sender, connected_peers);
        
        Ok(node)
    }
    
    /// Start the node's background tasks.
    fn start_background_tasks(
        &self,
        ipfs: Ipfs<TestTypes>,
        mut command_receiver: mpsc::Receiver<NodeCommand>,
        event_sender: mpsc::Sender<NodeEvent>,
        connected_peers: Arc<Mutex<HashSet<PeerId>>>,
    ) {
        let ipfs_clone = ipfs.clone();
        
        tokio::spawn(async move {
            while let Some(command) = command_receiver.next().await {
                match command {
                    NodeCommand::Connect(peer_id, addrs) => {
                        if let Err(e) = ipfs_clone.connect(peer_id, addrs).await {
                            let _ = event_sender.clone()
                                .send(NodeEvent::Error(format!("Failed to connect to peer: {}", e)))
                                .await;
                        } else {
                            let _ = event_sender.clone()
                                .send(NodeEvent::PeerConnected(peer_id))
                                .await;
                            connected_peers.lock().unwrap().insert(peer_id);
                        }
                    }
                    NodeCommand::Disconnect(peer_id) => {
                        if let Err(e) = ipfs_clone.disconnect(peer_id).await {
                            let _ = event_sender.clone()
                                .send(NodeEvent::Error(format!("Failed to disconnect from peer: {}", e)))
                                .await;
                        } else {
                            let _ = event_sender.clone()
                                .send(NodeEvent::PeerDisconnected(peer_id))
                                .await;
                            connected_peers.lock().unwrap().remove(&peer_id);
                        }
                    }
                    NodeCommand::AddBlock(block) => {
                        let cid = block.cid().clone();
                        let data = block.into_data();
                        if let Err(e) = ipfs_clone.put_block(data, cid.to_string()).await {
                            let _ = event_sender.clone()
                                .send(NodeEvent::Error(format!("Failed to add block: {}", e)))
                                .await;
                        } else {
                            let _ = event_sender.clone()
                                .send(NodeEvent::BlockReceived(cid))
                                .await;
                        }
                    }
                    NodeCommand::GetBlock(cid, sender) => {
                        let result = match ipfs_clone.get_block(&cid.to_string()).await {
                            Ok(data) => Ok(Some(Block::with_cid(cid, data))),
                            Err(_) => Ok(None),
                        };
                        let _ = sender.send(result);
                    }
                    NodeCommand::HasBlock(cid, sender) => {
                        let result = ipfs_clone.has_block(&cid.to_string()).await.unwrap_or(false);
                        let _ = sender.send(result);
                    }
                    NodeCommand::Shutdown => {
                        break;
                    }
                }
            }
        });
    }
    
    /// Get the node's peer ID.
    pub fn peer_id(&self) -> &PeerId {
        &self.peer_id
    }
    
    /// Connect to a peer.
    pub async fn connect(&self, peer_id: PeerId, addrs: Vec<Multiaddr>) -> Result<()> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::Connect(peer_id, addrs))
            .await?;
        receiver.await.map_err(|_| Error::ChannelClosed)
    }
    
    /// Disconnect from a peer.
    pub async fn disconnect(&self, peer_id: PeerId) -> Result<()> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::Disconnect(peer_id))
            .await?;
        receiver.await.map_err(|_| Error::ChannelClosed)
    }
    
    /// Get the next event from the node.
    pub async fn next_event(&mut self) -> Option<NodeEvent> {
        self.event_receiver.next().await
    }
    
    /// Get the list of connected peers.
    pub async fn connected_peers(&self) -> Vec<PeerId> {
        self.connected_peers.lock().unwrap().iter().cloned().collect()
    }
}

#[async_trait]
impl BlockStore for Node {
    async fn get_block(&self, cid: &Cid) -> Result<Option<Block>> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::GetBlock(cid.clone(), sender))
            .await?;
        receiver.await.map_err(|_| Error::ChannelClosed)?
    }
    
    async fn put_block(&mut self, block: Block) -> Result<Cid> {
        let cid = block.cid().clone();
        self.command_sender
            .clone()
            .send(NodeCommand::AddBlock(block))
            .await?;
        Ok(cid)
    }
    
    async fn has_block(&self, cid: &Cid) -> Result<bool> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::HasBlock(cid.clone(), sender))
            .await?;
        receiver.await.map_err(|_| Error::ChannelClosed)
    }
}

impl Drop for Node {
    fn drop(&mut self) {
        // Try to send a shutdown command, but don't block if the channel is full
        let _ = self.command_sender.try_send(NodeCommand::Shutdown);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    
    #[tokio::test]
    async fn test_node_creation() -> Result<()> {
        let config = Config::default();
        let node = Node::new(config).await?;
        
        // Verify the node has a valid peer ID
        assert!(!node.peer_id().to_string().is_empty());
        
        Ok(())
    }
    
    #[tokio::test]
    async fn test_block_storage() -> Result<()> {
        let config = Config::default();
        let mut node = Node::new(config).await?;
        
        // Create a test block
        let data = b"test data".to_vec();
        let block = Block::new(data.clone());
        let cid = block.cid().clone();
        
        // Test block storage and retrieval
        assert!(!node.has_block(&cid).await?);
        node.put_block(block).await?;
        assert!(node.has_block(&cid).await?);
        
        if let Some(retrieved_block) = node.get_block(&cid).await? {
            assert_eq!(retrieved_block.data(), data.as_slice());
        } else {
            panic!("Block not found in node");
        }
        
        Ok(())
    }
}
