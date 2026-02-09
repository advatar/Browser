//! IPFS node implementation.

use crate::ipfs::{Block, BlockStore, Config, Error, NodeEvent, Repo, Result};
use futures::{
    channel::{mpsc, oneshot},
    Stream, StreamExt,
};
use libp2p::{
    identity::Keypair,
    swarm::{NetworkBehaviour, Swarm, SwarmBuilder, SwarmEvent},
    Multiaddr, PeerId,
};
use std::{collections::HashSet, sync::Arc, time::Duration};
use tokio::sync::Mutex;

/// Commands that can be sent to the node.
pub enum NodeCommand {
    /// Connect to a peer.
    Connect(PeerId, Vec<Multiaddr>, oneshot::Sender<Result<()>>),
    /// Disconnect from a peer.
    Disconnect(PeerId, oneshot::Sender<Result<()>>),
    /// Add a block to the node.
    AddBlock(Block),
    /// Get a block from the node.
    GetBlock(Cid, oneshot::Sender<Result<Option<Block>>>),
    /// Check if a block exists.
    HasBlock(Cid, oneshot::Sender<bool>),
    /// Shut down the node.
    Shutdown,
}

/// The IPFS node implementation.
pub struct Node {
    /// The node's peer ID.
    peer_id: PeerId,
    /// The node's keypair.
    keypair: Keypair,
    /// The node's configuration.
    config: Config,
    /// The node's repository.
    repo: Arc<Repo>,
    /// Sender for node commands.
    command_sender: mpsc::Sender<NodeCommand>,
    /// Receiver for node events.
    event_receiver: mpsc::Receiver<NodeEvent>,
    /// Set of connected peers.
    connected_peers: Arc<Mutex<HashSet<PeerId>>>,
}

impl Node {
    /// Create a new IPFS node with the given configuration.
    pub fn new(config: Config) -> Result<Self> {
        // Generate a new keypair if one isn't provided
        let keypair = Keypair::generate_ed25519();
        let peer_id = PeerId::from_public_key(&keypair.public());

        // Create the repository
        let repo = Arc::new(Repo::new(&config.repo_path)?);

        // Create channels for commands and events
        let (command_sender, command_receiver) = mpsc::channel(32);
        let (event_sender, event_receiver) = mpsc::channel(32);

        // Initialize connected peers set
        let connected_peers = Arc::new(Mutex::new(HashSet::new()));

        // Start the node's event loop
        let node = Self {
            peer_id,
            keypair,
            config,
            repo: repo.clone(),
            command_sender,
            event_receiver,
            connected_peers: connected_peers.clone(),
        };

        // Start the node's background tasks
        node.start_background_tasks(command_receiver, event_sender, connected_peers);

        Ok(node)
    }

    /// Start the node's background tasks.
    fn start_background_tasks(
        &self,
        mut command_receiver: mpsc::Receiver<NodeCommand>,
        event_sender: mpsc::Sender<NodeEvent>,
        connected_peers: Arc<Mutex<HashSet<PeerId>>>,
    ) {
        let repo = self.repo.clone();

        tokio::spawn(async move {
            while let Some(command) = command_receiver.next().await {
                match command {
                    NodeCommand::Connect(peer_id, _addrs, responder) => {
                        let mut peers = connected_peers.lock().await;
                        peers.insert(peer_id);
                        drop(peers);
                        let _ = event_sender
                            .clone()
                            .send(NodeEvent::PeerConnected(peer_id))
                            .await;
                        let _ = responder.send(Ok(()));
                    }
                    NodeCommand::Disconnect(peer_id, responder) => {
                        let mut peers = connected_peers.lock().await;
                        peers.remove(&peer_id);
                        drop(peers);
                        let _ = event_sender
                            .clone()
                            .send(NodeEvent::PeerDisconnected(peer_id))
                            .await;
                        let _ = responder.send(Ok(()));
                    }
                    NodeCommand::AddBlock(block) => {
                        if let Err(e) = repo.put_block(block) {
                            let _ = event_sender
                                .clone()
                                .send(NodeEvent::Error(e.to_string()))
                                .await;
                        }
                    }
                    NodeCommand::GetBlock(cid, sender) => {
                        let result = repo.get_block(&cid);
                        let _ = sender.send(result);
                    }
                    NodeCommand::HasBlock(cid, sender) => {
                        let result = repo.has_block(&cid).unwrap_or(false);
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
            .send(NodeCommand::Connect(peer_id, addrs, sender))
            .await?;
        receiver.await.map_err(|_| Error::ChannelClosed)
    }

    /// Disconnect from a peer.
    pub async fn disconnect(&self, peer_id: PeerId) -> Result<()> {
        let (sender, receiver) = oneshot::channel();
        self.command_sender
            .clone()
            .send(NodeCommand::Disconnect(peer_id, sender))
            .await?;
        receiver.await.map_err(|_| Error::ChannelClosed)
    }

    /// Get the next event from the node.
    pub async fn next_event(&mut self) -> Option<NodeEvent> {
        self.event_receiver.next().await
    }

    /// Get the list of connected peers.
    pub async fn connected_peers(&self) -> Vec<PeerId> {
        let peers = self.connected_peers.lock().await;
        peers.iter().cloned().collect()
    }
}

#[async_trait::async_trait]
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
        let temp_dir = tempdir()?;
        let config = Config::new(temp_dir.path());
        let node = Node::new(config)?;

        // Verify the node has a valid peer ID
        assert!(!node.peer_id().to_string().is_empty());

        Ok(())
    }

    #[tokio::test]
    async fn test_block_storage() -> Result<()> {
        let temp_dir = tempdir()?;
        let config = Config::new(temp_dir.path());
        let mut node = Node::new(config)?;

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
