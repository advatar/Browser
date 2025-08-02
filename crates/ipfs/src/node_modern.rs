//! Modern IPFS node implementation using rust-ipfs.

use crate::{Block, BlockStore, Config, Error, Result};
use async_trait::async_trait;
use cid::Cid;
use futures::{channel::mpsc, StreamExt};
use ipfs_node::{Node as IpfsNode, NodeEvent as IpfsNodeEvent};
use libp2p::PeerId;
use log::{debug, error, info, warn};
use std::{
    collections::HashSet,
    path::Path,
    sync::Arc,
    task::{Context, Poll},
    time::Duration,
};
use tokio::sync::Mutex;

/// An IPFS node that implements the IPFS protocol using rust-ipfs
pub struct Node {
    /// The underlying rust-ipfs node
    ipfs: IpfsNode,
    /// Channel for sending commands to the node
    command_sender: mpsc::Sender<NodeCommand>,
    /// Channel for receiving events from the node
    event_receiver: mpsc::Receiver<NodeEvent>,
    /// Set of connected peers
    connected_peers: Arc<Mutex<HashSet<PeerId>>>,
}

/// Commands that can be sent to the node
#[derive(Debug)]
pub enum NodeCommand {
    /// Connect to a peer
    Connect(PeerId, Vec<libp2p::Multiaddr>),
    /// Disconnect from a peer
    Disconnect(PeerId),
    /// Add a block to the node
    AddBlock(Block),
    /// Get a block from the node
    GetBlock(Cid, oneshot::Sender<Result<Option<Block>>>),
    /// Check if a block exists
    HasBlock(Cid, oneshot::Sender<bool>),
    /// Shut down the node
    Shutdown,
}

/// Events emitted by the node
#[derive(Debug)]
pub enum NodeEvent {
    /// A new peer has connected
    PeerConnected(PeerId),
    /// A peer has disconnected
    PeerDisconnected(PeerId),
    /// A new block was received
    BlockReceived(Cid),
    /// An error occurred
    Error(Error),
}

impl Node {
    /// Create a new IPFS node with the given configuration
    pub fn new(config: Config) -> Result<Self> {
        // Initialize the rust-ipfs node
        let ipfs = ipfs_node::Node::new(config)?;
        
        // Create channels for commands and events
        let (command_sender, command_receiver) = mpsc::channel(32);
        let (event_sender, event_receiver) = mpsc::channel(32);
        
        // Initialize connected peers set
        let connected_peers = Arc::new(Mutex::new(HashSet::new()));
        
        // Start the node's event loop
        let ipfs_clone = ipfs.clone();
        let connected_peers_clone = connected_peers.clone();
        
        tokio::spawn(async move {
            let mut command_receiver = command_receiver;
            let event_sender = event_sender;
            
            while let Some(command) = command_receiver.next().await {
                match command {
                    NodeCommand::Connect(peer_id, addrs) => {
                        if let Err(e) = ipfs_clone.connect(peer_id, addrs).await {
                            let _ = event_sender.clone().send(NodeEvent::Error(e.into())).await;
                        }
                    }
                    NodeCommand::Disconnect(peer_id) => {
                        if let Err(e) = ipfs_clone.disconnect(peer_id).await {
                            let _ = event_sender.clone().send(NodeEvent::Error(e.into())).await;
                        }
                    }
                    NodeCommand::AddBlock(block) => {
                        if let Err(e) = ipfs_clone.add_block(block).await {
                            let _ = event_sender.clone().send(NodeEvent::Error(e.into())).await;
                        }
                    }
                    NodeCommand::GetBlock(cid, sender) => {
                        let result = ipfs_clone.get_block(&cid).await;
                        let _ = sender.send(result);
                    }
                    NodeCommand::HasBlock(cid, sender) => {
                        let result = ipfs_clone.has_block(&cid).await.unwrap_or(false);
                        let _ = sender.send(result);
                    }
                    NodeCommand::Shutdown => {
                        break;
                    }
                }
            }
        });
        
        // Start processing node events
        let ipfs_clone = ipfs.clone();
        let event_sender_clone = event_sender.clone();
        let connected_peers_clone = connected_peers.clone();
        
        tokio::spawn(async move {
            let mut event_stream = ipfs_clone.events();
            
            while let Some(event) = event_stream.next().await {
                match event {
                    IpfsNodeEvent::PeerConnected(peer_id) => {
                        connected_peers_clone.lock().await.insert(peer_id);
                        let _ = event_sender_clone.clone()
                            .send(NodeEvent::PeerConnected(peer_id))
                            .await;
                    }
                    IpfsNodeEvent::PeerDisconnected(peer_id) => {
                        connected_peers_clone.lock().await.remove(&peer_id);
                        let _ = event_sender_clone.clone()
                            .send(NodeEvent::PeerDisconnected(peer_id))
                            .await;
                    }
                    IpfsNodeEvent::BlockReceived(cid) => {
                        let _ = event_sender_clone.clone()
                            .send(NodeEvent::BlockReceived(cid))
                            .await;
                    }
                    _ => {}
                }
            }
        });
        
        Ok(Self {
            ipfs,
            command_sender,
            event_receiver,
            connected_peers,
        })
    }
    
    /// Start the IPFS node
    pub async fn start(&mut self) -> Result<()> {
        self.ipfs.start().await?;
        Ok(())
    }
    
    /// Connect to a peer
    pub async fn connect(&mut self, peer_id: PeerId, addrs: Vec<libp2p::Multiaddr>) -> Result<()> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::Connect(peer_id, addrs))
            .await
            .map_err(|_| Error::ChannelClosed)?;
        receiver.await.map_err(|_| Error::ChannelClosed)
    }
    
    /// Disconnect from a peer
    pub async fn disconnect(&mut self, peer_id: PeerId) -> Result<()> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::Disconnect(peer_id))
            .await
            .map_err(|_| Error::ChannelClosed)?;
        receiver.await.map_err(|_| Error::ChannelClosed)
    }
    
    /// Get the next event from the node
    pub async fn next_event(&mut self) -> Option<NodeEvent> {
        self.event_receiver.next().await
    }
    
    /// Get the local peer ID
    pub fn local_peer_id(&self) -> PeerId {
        self.ipfs.peer_id()
    }
    
    /// Get the list of connected peers
    pub async fn connected_peers(&self) -> Vec<PeerId> {
        self.connected_peers.lock().await.iter().cloned().collect()
    }
}

#[async_trait]
impl BlockStore for Node {
    async fn get_block(&self, cid: &Cid) -> Result<Option<Block>> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::GetBlock(*cid, sender))
            .await
            .map_err(|_| Error::ChannelClosed)?;
        receiver.await.map_err(|_| Error::ChannelClosed)?
    }
    
    async fn put_block(&mut self, block: Block) -> Result<Cid> {
        let cid = block.cid();
        self.command_sender
            .clone()
            .send(NodeCommand::AddBlock(block))
            .await
            .map_err(|_| Error::ChannelClosed)?;
        Ok(cid)
    }
    
    async fn has_block(&self, cid: &Cid) -> Result<bool> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::HasBlock(*cid, sender))
            .await
            .map_err(|_| Error::ChannelClosed)?;
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
    use cid::multihash::Multihash;
    use libp2p::Multiaddr;
    use std::str::FromStr;
    
    #[tokio::test]
    async fn test_node_creation() {
        let config = Config::new(std::env::temp_dir().join("ipfs-test"));
        let mut node = Node::new(config).expect("failed to create node");
        assert!(node.start().await.is_ok(), "failed to start node");
    }
    
    #[tokio::test]
    async fn test_block_operations() {
        let config = Config::new(std::env::temp_dir().join("ipfs-test-blocks"));
        let mut node = Node::new(config).expect("failed to create node");
        node.start().await.expect("failed to start node");
        
        // Test adding a block
        let data = b"test data".to_vec();
        let block = Block::new(data.clone());
        let cid = node.put_block(block).await.expect("failed to put block");
        
        // Test getting the block
        let retrieved = node.get_block(&cid).await.expect("failed to get block");
        assert!(retrieved.is_some(), "block not found");
        assert_eq!(retrieved.unwrap().data(), &data);
        
        // Test has_block
        assert!(node.has_block(&cid).await.expect("has_block failed"));
    }
}
