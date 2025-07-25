//! IPFS node implementation with enhanced P2P capabilities.

use crate::{
    bitswap::{Bitswap, BitswapConfig, BitswapEvent, Priority},
    node::NodeEvent,
    Block, BlockStore, Config, Error, Result,
};

use async_trait::async_trait;
use cid::{multihash, Cid};
use futures::{channel::mpsc, StreamExt};
use ipfs_embed::{Block as IpfsBlock, DefaultParams, Ipfs, NetworkConfig, StorageConfig};
use libp2p::{
    core::{muxing::StreamMuxerBox, transport::Boxed, upgrade, Multiaddr, PeerId},
    identify,
    kad::{Kademlia, KademliaEvent, store::MemoryStore, record::store::MemoryStore as RecordStore, record::Key},
    mplex,
    noise,
    swarm::{
        ConnectionDenied, ConnectionId, FromSwarm, NetworkBehaviour, NetworkBehaviour as Libp2pNetworkBehaviour,
        PollParameters, SwarmBuilder, SwarmEvent, ToSwarm,
    },
    tcp, yamux, Transport,
};
use libp2p_bitswap::Bitswap as Libp2pBitswap;
use log::{debug, error, info, warn};
use p2p::behaviour::P2PBehaviour as CoreP2PBehaviour;
use std::{collections::HashSet, path::Path, sync::Arc, task::{Context, Poll}, time::Duration};
use tokio::sync::{mpsc::Sender, Mutex};

/// A combined network behaviour that includes all the behaviours we need
#[derive(NetworkBehaviour)]
#[behaviour(out_event = "NodeBehaviourEvent")]
pub struct NodeBehaviour {
    /// Core P2P behaviour (Kademlia, mDNS, Identify, Ping)
    core: CoreP2PBehaviour,
    /// Bitswap protocol for block exchange
    bitswap: Libp2pBitswap<()>, // Using unit type for store as we handle storage separately
}

/// Events emitted by the combined network behaviour
#[derive(Debug)]
pub enum NodeBehaviourEvent {
    /// Event from the core P2P behaviour (Kademlia, mDNS, Identify, Ping)
    Core(<CoreP2PBehaviour as NetworkBehaviour>::ToSwarm),
    /// Bitswap protocol event
    Bitswap(BitswapEvent),
}

impl NodeBehaviour {
    /// Create a new NodeBehaviour with the given local peer ID and keypair
    pub fn new(peer_id: PeerId, keypair: &libp2p_identity::Keypair) -> Self {
        // Create the core P2P behaviour (includes Kademlia, mDNS, Identify, Ping)
        let core = CoreP2PBehaviour::new(keypair);
        
        // Create a bitswap behaviour with default config
        let bitswap = Libp2pBitswap::new(Default::default());
        
        Self { core, bitswap }
    }
    
    /// Get a mutable reference to the Kademlia instance (if enabled)
    #[cfg(feature = "kad")]
    pub fn kademlia(&mut self) -> &mut Kademlia<MemoryStore> {
        self.core.kademlia()
    }
    
    /// Bootstrap the Kademlia DHT (if enabled)
    #[cfg(feature = "kad")]
    pub fn bootstrap_kademlia(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        self.core.bootstrap_kademlia()
    }
    
    /// Start providing a value in the DHT (if Kademlia is enabled)
    #[cfg(feature = "kad")]
    pub fn start_providing(&mut self, key: Vec<u8>) -> Result<(), Box<dyn std::error::Error>> {
        self.core.start_providing(key)
    }
    
    /// Get the list of known peers (if mDNS is enabled)
    #[cfg(feature = "mdns")]
    pub fn discovered_peers(&self) -> Vec<libp2p::PeerId> {
        self.core.discovered_peers()
    }
}

/// An IPFS node that implements the IPFS protocol
pub struct Node {
    /// The underlying IPFS-embed node
    ipfs: Ipfs<DefaultParams>,
    /// The libp2p swarm with our custom behaviour
    swarm: Swarm<NodeBehaviour>,
    /// Sender for node events
    event_sender: mpsc::Sender<NodeEvent>,
    /// Receiver for node events
    event_receiver: mpsc::Receiver<NodeEvent>,
    /// Local peer ID
    peer_id: PeerId,
    /// Keypair for this node
    keypair: libp2p_identity::Keypair,
    /// Bootstrap nodes to connect to on startup
    bootstrap_nodes: Vec<Multiaddr>,
}

impl Node {
    /// Create a new IPFS node with the given configuration
    pub async fn new(config: Config) -> Result<Self> {
        // Generate a new keypair for this node if not provided
        let keypair = libp2p_identity::Keypair::generate_ed25519();
        let peer_id = keypair.public().to_peer_id();
        
        // Initialize the IPFS node
        let ipfs = Self::init_ipfs(&config).await?;
        
        // Create channels for events
        let (event_sender, event_receiver) = mpsc::channel(32);
        
        // Create the network behaviour with our keypair
        let behaviour = NodeBehaviour::new(peer_id, &keypair);
        
        // Create the transport
        let transport = Self::build_transport(&keypair)?;
        
        // Create the swarm
        let swarm = SwarmBuilder::with_tokio_executor(transport, behaviour, peer_id).build();
        
        Ok(Self {
            ipfs,
            swarm,
            event_sender,
            event_receiver,
            peer_id,
            keypair,
            bootstrap_nodes: config.bootstrap_nodes,
        })
    }
    
    /// Build the libp2p transport with the given keypair
    fn build_transport(keypair: &libp2p_identity::Keypair) -> Result<Boxed<(PeerId, StreamMuxerBox)>> {
        let tcp = tcp::tokio::Transport::new(tcp::Config::default().nodelay(true));
        
        // Create authenticated transport with noise
        let noise_keys = noise::Keypair::<noise::X25519Spec>::new()
            .into_authentic(keypair)
            .expect("Signing libp2p-noise static DH keypair failed.");
            
        let transport = tcp
            .upgrade(upgrade::Version::V1)
            .authenticate(noise::NoiseConfig::xx(noise_keys).into_authenticated())
            .multiplex(yamux::Config::default())
            .boxed();
            
        Ok(transport)
    }
    
    /// Initialize the IPFS node
    async fn init_ipfs(config: &Config) -> Result<Ipfs<DefaultParams>> {
        // Configure storage
        let storage = StorageConfig::new(
            config.repo_path.clone(),
            config.storage_max_block_size,
            config.storage_max_block_count,
        );
        
        // Configure network
        let network = NetworkConfig::new()
            .with_listen_addrs(config.listen_addrs.clone())
            .with_bootstrap_nodes(config.bootstrap_nodes.clone())
            .with_mdns(config.mdns_enabled)
            .with_kademlia(config.kademlia_enabled);
        
        // Create the IPFS node
        let ipfs = Ipfs::<DefaultParams>::new(storage, network).await?;
        
        Ok(ipfs)
    }
    
    /// Start the IPFS node
    pub async fn start(&mut self) -> Result<()> {
        // Listen on all interfaces with a random port
        self.swarm
            .listen_on("/ip4/0.0.0.0/tcp/0".parse()?)
            .map_err(|e| anyhow::anyhow!("Failed to listen on any interface: {}", e))?;
            
        // Bootstrap Kademlia if enabled
        #[cfg(feature = "kad")]
        {
            if let Err(e) = self.swarm.behaviour_mut().bootstrap_kademlia() {
                log::warn!("Failed to bootstrap Kademlia: {}", e);
            } else {
                log::info!("Kademlia DHT bootstrapped successfully");
            }
        }
        
        // Connect to bootstrap nodes
        self.connect_to_bootstrap_nodes().await?;
        
        // Start the event loop
        self.run_event_loop().await;
        
        Ok(())
    }
    
    /// Connect to bootstrap nodes
    async fn connect_to_bootstrap_nodes(&mut self) -> Result<()> {
        for addr in &self.bootstrap_nodes {
            match addr.clone().with(Protocol::P2p(self.peer_id.into())) {
                Ok(addr) => {
                    if let Err(e) = self.swarm.dial(addr) {
                        log::warn!("Failed to dial bootstrap node {}: {}", addr, e);
                    } else {
                        log::debug!("Dialed bootstrap node: {}", addr);
                    }
                }
                Err(e) => {
                    log::warn!("Invalid bootstrap address {}: {}", addr, e);
                }
            }
        }
        Ok(())
    }
    
    /// Run the main event loop
    async fn run_event_loop(&mut self) {
        loop {
            tokio::select! {
                // Handle swarm events
                event = self.swarm.next() => {
                    if let Some(event) = event {
                        self.handle_swarm_event(event).await;
                    }
                },
                // Handle node events from application
                event = self.event_receiver.next() => {
                    if let Some(event) = event {
                        if let Err(e) = self.handle_node_event(event).await {
                            log::error!("Error handling node event: {}", e);
                        }
                    }
                },
            }
        }
    }
    
    /// Handle swarm events
    async fn handle_swarm_event(&mut self, event: SwarmEvent<NodeBehaviourEvent>) {
        match event {
            SwarmEvent::Behaviour(event) => {
                match event {
                    NodeBehaviourEvent::Core(event) => {
                        // Handle core P2P events
                        log::debug!("Core P2P event: {:?}", event);
                    }
                    NodeBehaviourEvent::Bitswap(event) => {
                        // Handle Bitswap events
                        log::debug!("Bitswap event: {:?}", event);
                    }
                }
            }
            SwarmEvent::NewListenAddr { address, .. } => {
                log::info!("Listening on {}", address);
            }
            SwarmEvent::IncomingConnection { local_addr, send_back_addr, .. } => {
                log::debug!("Incoming connection from {} to {}", send_back_addr, local_addr);
            }
            SwarmEvent::ConnectionEstablished { peer_id, endpoint, .. } => {
                log::info!("Connected to {} via {}", peer_id, endpoint.get_remote_address());
            }
            SwarmEvent::ConnectionClosed { peer_id, endpoint, .. } => {
                log::info!("Disconnected from {} via {}", peer_id, endpoint.get_remote_address());
            }
            SwarmEvent::Dialing(peer_id) => {
                log::debug!("Dialing {}", peer_id);
            }
            _ => {}
        }
    }
    
    /// Handle node events from the application
    async fn handle_node_event(&mut self, event: NodeEvent) -> Result<()> {
        match event {
            NodeEvent::FindPeer { peer_id } => {
                log::debug!("Finding peer: {:?}", peer_id);
                #[cfg(feature = "kad")]
                {
                    if let Ok(peer_id) = PeerId::from_bytes(&peer_id) {
                        self.swarm.behaviour_mut().kademlia().get_closest_peers(peer_id);
                    }
                }
            }
            NodeEvent::ProvideBlock { cid } => {
                log::debug!("Providing block: {:?}", cid);
                #[cfg(feature = "kad")]
                {
                    if let Ok(cid) = Cid::try_from(cid.as_slice()) {
                        let _ = self.swarm.behaviour_mut().start_providing(cid.to_bytes());
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }
    
    /// Get a block from the IPFS node
    pub async fn get_block(&self, cid: &Cid) -> Result<Option<Vec<u8>>> {
        if let Ok(Some(block)) = self.ipfs.get(cid).await {
            Ok(Some(block.data().to_vec()))
        } else {
            Ok(None)
        }
    }
    
    /// Store a block in the IPFS node and announce it to the network
    pub async fn put_block(
        &mut self,
        data: Vec<u8>,
        codec: Option<cid::Codec>,
        hash: Option<multihash::Code>,
    ) -> Result<Cid> {
        // Create a CID for the data
        let cid = self.ipfs.create_block(data, codec, hash).await?;
        
        // Announce the block to the DHT if Kademlia is enabled
        #[cfg(feature = "kad")]
        {
            let key = cid.to_bytes();
            if let Err(e) = self.swarm.behaviour_mut().start_providing(key) {
                log::warn!("Failed to announce block to DHT: {}", e);
            } else {
                log::debug!("Announced block {} to DHT", cid);
            }
        }
        
        Ok(cid)
    }
    
    /// Check if a block exists locally
    pub async fn has_block(&self, cid: &Cid) -> bool {
        self.ipfs.get(cid).await.is_ok()
    }
    
    /// Get the size of a block
    pub async fn block_size(&self, cid: &Cid) -> Option<usize> {
        self.ipfs.get(cid).await.ok().map(|b| b.data().len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    
    #[tokio::test]
    async fn test_node_creation() {
        let temp_dir = tempdir().unwrap();
        let config = Config {
            repo_path: temp_dir.path().to_path_buf(),
            listen_addrs: vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()],
            bootstrap_nodes: vec![],
            storage_max_block_size: 1024 * 1024,
            storage_max_block_count: 1000,
            mdns_enabled: true,
            kademlia_enabled: true,
        };
        
        let node = Node::new(config).await;
        assert!(node.is_ok());
    }
    
    #[tokio::test]
    async fn test_block_operations() {
        let temp_dir = tempdir().unwrap();
        let config = Config {
            repo_path: temp_dir.path().to_path_buf(),
            listen_addrs: vec!["/ip4/0.0.0.0/tcp/0".parse().unwrap()],
            bootstrap_nodes: vec![],
            storage_max_block_size: 1024 * 1024,
            storage_max_block_count: 1000,
            mdns_enabled: true,
            kademlia_enabled: true,
        };
        
        let mut node = Node::new(config).await.unwrap();
        
        // Test putting a block
        let data = b"hello world".to_vec();
        let cid = node.put_block(data.clone(), None, None).await.unwrap();
        
        // Test getting the block
        let retrieved = node.get_block(&cid).await.unwrap();
        assert_eq!(retrieved, Some(data));
        
        // Test has_block
        assert!(node.has_block(&cid).await);
        
        // Test block_size
        assert_eq!(node.block_size(&cid).await, Some(11));
    }
}
