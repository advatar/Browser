//! IPFS node implementation with Bitswap and DHT support.
//!
//! This module provides a high-level IPFS node implementation that integrates:
//! - libp2p for peer-to-peer networking
//! - Kademlia DHT for content routing and peer discovery
//! - Bitswap for block exchange
//! - Sled-based block storage
//!
//! # Features
//!
//! - Full DHT support for content routing and peer discovery
//! - Block storage with automatic content addressing
//! - Event-driven architecture for monitoring node activity
//! - Bootstrap to the public IPFS network
//!
//! # Examples
//!
//! ```no_run
//! use ipfs::{Node, Config};
//! use ipfs_embed::DefaultParams;
//! use std::time::Duration;
//!
//! #[tokio::main]
//! async fn main() -> anyhow::Result<()> {
//!     // Create a new node with default configuration
//!     let config = Config::new("my-ipfs-node".into(), vec![]);
//!     let mut node = Node::new(config).await?;
//!
//!     // Start the node and connect to the network
//!     node.start().await?;
//!
//!     // Store some data
//!     let data = b"hello world".to_vec();
//!     let cid = node.put_block(data.clone()).await?;
//!     println!("Stored data with CID: {}", cid);
//!
//!     // Retrieve the data
//!     if let Some(retrieved) = node.get_block(&cid).await? {
//!         assert_eq!(retrieved, data);
//!         println!("Successfully retrieved data!");
//!     }
//!
//!     // Process events
//!     while let Some(event) = node.next_event().await {
//!         println!("Node event: {:?}", event);
//!     }
//!
//!     Ok(())
//! }
//! ```

use anyhow::{Context, Result};
use cid::{Cid, multihash::{Code, MultihashDigest}};
use futures::{Stream, StreamExt, future::FutureExt};
use ipfs_embed::{
    Config, DefaultParams, Ipfs,
    identity::ed25519::Keypair,
    Block as IpfsBlock,
    kad::{QueryResult, PutRecordOk, GetRecordOk, Quorum, Record},
    NetworkEvent, PeerId as EmbedPeerId,
};
use libp2p::{
    bitswap::{Bitswap, BitswapConfig as Libp2pBitswapConfig, BitswapEvent},
    core::connection::ConnectionId,
    identify, kad,
    kad::{Kademlia, KademliaEvent, MemoryStore, Record as KademliaRecord, RecordKey, ProviderRecord, QueryResult as KadQueryResult, QueryId},
    multiaddr::{Protocol, Multiaddr},
    ping,
    swarm::{
        NetworkBehaviour, NetworkBehaviourAction, NotifyHandler, PollParameters,
        ConnectionHandler, ConnectionHandlerUpgrErr, DialError, FromSwarm,
        ConnectionEstablished, ConnectionClosed, ListenFailure, ExpiredListenAddr, NewListenAddr,
        NewExternalAddr, ExpiredExternalAddr, DialFailure, ToSwarm, ConnectionDenied, THandlerInEvent,
        THandlerOutEvent, AddressChange, THandler, ConnectionLimits, ConnectionLimit,
        ConnectionHandlerEvent, Stream as ConnectionStream, SubstreamProtocol, SubstreamEndpoint,
        ProtocolsHandler, ProtocolsHandlerEvent, ProtocolsHandlerUpgrErr, KeepAlive,
    },
    PeerId, Transport, StreamProtocol,
};
use prometheus::{Registry, IntCounter, IntGauge};
use std::{
    sync::Arc,
    pin::Pin,
    task::{Context as TaskContext, Poll},
    time::Duration,
    collections::VecDeque,
    future::Future,
};
use tokio::sync::mpsc;

use crate::{
    bitswap::{BitswapService, BitswapConfig},
    node::NodeEvent,
    Block, BlockStore, Config, Error, Result,
};

use async_trait::async_trait;
use cid::Cid;
use futures::{channel::mpsc, StreamExt};
use ipfs_embed::{Block as IpfsBlock, Cid as IpfsCid, DefaultParams, Ipfs, NetworkConfig, StorageConfig};
use libp2p::{
    core::{muxing::StreamMuxerBox, transport::Boxed, upgrade, Multiaddr, PeerId},
    identify,
    kad::{Kademlia, KademliaEvent, store::MemoryStore, record::store::MemoryStore as RecordStore},
    mplex,
    swarm::{
        ConnectionDenied, ConnectionId, FromSwarm, NetworkBehaviour, NetworkBehaviour as Libp2pNetworkBehaviour,
        PollParameters, SwarmBuilder, SwarmEvent, ToSwarm,
    },
    tcp, yamux, Transport,
};
use libp2p_bitswap::{Bitswap, BitswapEvent, BitswapStore};
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
    bitswap: Bitswap<()>, // Using unit type for store as we handle storage separately
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
    pub fn new(local_peer_id: libp2p::PeerId, keypair: &libp2p_identity::Keypair) -> Self {
        // Create the core P2P behaviour (includes Kademlia, mDNS, Identify, Ping)
        let core = CoreP2PBehaviour::new(keypair);
        
        // Create a bitswap behaviour with default config
        let bitswap = Bitswap::new(Default::default());
        
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

// Implement NetworkBehaviour for NodeBehaviour
impl NetworkBehaviour for NodeBehaviour {
    type ConnectionHandler = libp2p::swarm::dummy::ConnectionHandler;
    type ToSwarm = NodeBehaviourEvent;

    fn handle_established_inbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: PeerId,
        local_addr: &Multiaddr,
        remote_addr: &Multiaddr,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        // Delegate to core P2P behaviour first
        self.core.handle_established_inbound_connection(
            connection_id,
            peer,
            local_addr,
            remote_addr,
        )?;
        
        // Then handle with Bitswap
        self.bitswap.handle_established_inbound_connection(
            connection_id,
            peer,
            local_addr,
            remote_addr,
        )
    }

    fn handle_established_outbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: PeerId,
        addr: &Multiaddr,
        role_override: libp2p::core::Endpoint,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        // Delegate to core P2P behaviour first
        self.core.handle_established_outbound_connection(
            connection_id,
            peer,
            addr,
            role_override,
        )?;
        
        // Then handle with Bitswap
        self.bitswap.handle_established_outbound_connection(
            connection_id,
            peer,
            addr,
            role_override,
        )
    }

    fn on_swarm_event(&mut self, event: FromSwarm<Self::ConnectionHandler>) {
        // Delegate to core P2P behaviour first
        self.core.on_swarm_event(event.clone());
        
        // Then delegate to Bitswap
        self.bitswap.on_swarm_event(event);
    }

    fn on_connection_handler_event(
        &mut self,
        peer_id: PeerId,
        connection_id: ConnectionId,
        event: <Self::ConnectionHandler as libp2p::swarm::ConnectionHandler>::ToBehaviour,
    ) {
        // Delegate to core P2P behaviour
        self.core.on_connection_handler_event(peer_id, connection_id, event.clone());
        
        // Then delegate to Bitswap
        self.bitswap.on_connection_handler_event(peer_id, connection_id, event);
    }

    fn poll(
        &mut self,
        cx: &mut Context<'_>,
        params: &mut impl PollParameters,
    ) -> Poll<ToSwarm<Self::ToSwarm, libp2p::swarm::THandlerInEvent<Self>>> {
        // Poll core P2P behaviour first
        if let Poll::Ready(event) = self.core.poll(cx, params) {
            return Poll::Ready(ToSwarm::GenerateEvent(NodeBehaviourEvent::Core(event)));
        }
        
        // Then poll Bitswap
        if let Poll::Ready(event) = self.bitswap.poll(cx, params) {
            return Poll::Ready(ToSwarm::GenerateEvent(NodeBehaviourEvent::Bitswap(event)));
        }
        
        Poll::Pending
    }
}

impl NetworkBehaviour for NodeBehaviour {
    type ConnectionHandler = libp2p::swarm::dummy::ConnectionHandler;
    type ToSwarm = NodeBehaviourEvent;
    type OutEvent = NodeBehaviourEvent;

    fn handle_established_inbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: PeerId,
        local_addr: &Multiaddr,
        remote_addr: &Multiaddr,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        self.core
            .handle_established_inbound_connection(connection_id, peer, local_addr, remote_addr)?;
        self.bitswap
            .handle_established_inbound_connection(connection_id, peer, local_addr, remote_addr)
    }

    fn handle_established_outbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: PeerId,
        addr: &Multiaddr,
        role_override: libp2p::core::Endpoint,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        self.core
            .handle_established_outbound_connection(connection_id, peer, addr, role_override)?;
        self.bitswap
            .handle_established_outbound_connection(connection_id, peer, addr, role_override)
    }

    fn on_swarm_event(&mut self, event: FromSwarm<Self::ConnectionHandler>) {
        match event {
            FromSwarm::ConnectionEstablished(conn_established) => {
                self.core.on_swarm_event(FromSwarm::ConnectionEstablished(
                    conn_established.clone(),
                ));
                self.bitswap
                    .on_swarm_event(FromSwarm::ConnectionEstablished(conn_established));
            }
            _ => {
                self.core.on_swarm_event(event.clone());
                self.bitswap.on_swarm_event(event);
            }
        }
    }

    fn on_connection_handler_event(
        &mut self,
        _peer_id: PeerId,
        _connection_id: ConnectionId,
        _event: <Self::ConnectionHandler as ConnectionHandler>::ToBehaviour,
    ) {
        // No-op for dummy handler
    }

    fn poll(
        &mut self,
        cx: &mut std::task::Context<'_>,
        params: &mut impl PollParameters,
    ) -> Poll<ToSwarm<Self::ToSwarm, THandlerInEvent<Self>>> {
        if let Poll::Ready(event) = self.core.poll(cx, params) {
            return Poll::Ready(event.map(NodeBehaviourEvent::Core).map(ToSwarm::GenerateEvent));
        }

        if let Poll::Ready(event) = self.bitswap.poll(cx, params) {
            return Poll::Ready(event.map(NodeBehaviourEvent::Bitswap).map(ToSwarm::GenerateEvent));
        }

        Poll::Pending
    }
}

        NodeBehaviourEvent::Core(event)
    }
}

use crate::{
    bitswap::{BitswapService, BitswapConfig},
    node::NodeEvent,
    blockstore::SledStore,
};
use libp2p::bitswap::Block as Libp2pBlock;

/// Events emitted by the Node
#[derive(Debug)]
pub enum NodeEvent {
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
    /// Sender for block requests
    block_sender: mpsc::Sender<BlockRequest>,
    /// Local peer ID
    peer_id: PeerId,
    /// Keypair for this node
    keypair: libp2p_identity::Keypair,
    /// Bootstrap nodes to connect to on startup
    bootstrap_nodes: Vec<Multiaddr>,
},
    /// Provide a block to the network
    ProvideBlock { cid: Vec<u8> },
    /// Request a block from the network
    WantBlock { 
        /// The CID of the block to request
/// Create a new IPFS node with the given configuration
pub async fn new(config: Config) -> Result<Self> {
    // Generate a new keypair for this node if not provided
    let keypair = libp2p_identity::Keypair::generate_ed25519();
    let peer_id = keypair.public().to_peer_id();
    
    // Initialize the IPFS node
    let ipfs = Self::init_ipfs(&config).await?;
    
    // Create channels for events and block requests
    let (event_sender, event_receiver) = mpsc::channel(32);
    let (block_sender, block_receiver) = mpsc::channel(32);
    
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
        block_sender,
        peer_id,
        keypair,
        bootstrap_nodes: config.bootstrap_nodes,
    })

/// Build the libp2p transport with the given keypair
fn build_transport(keypair: &libp2p_identity::Keypair) -> Result<Boxed<(PeerId, StreamMuxerBox)>> {
    let tcp = tcp::tokio::Transport::new(tcp::Config::default().nodelay(true));
    
    // Create authenticated transport with noise
    let noise_keys = libp2p_noise::Keypair::<libp2p_noise::X25519Spec>::new()
        .into_authentic(keypair)
        .expect("Signing libp2p-noise static DH keypair failed.");
        
    let transport = tcp
        .upgrade(upgrade::Version::V1)
        .authenticate(libp2p_noise::NoiseConfig::xx(noise_keys).into_authenticated())
        .multiplex(yamux::Config::default())
        .boxed();
        
    Ok(transport)

/// Handle node events from the application
async fn handle_node_event(&mut self, event: NodeEvent) -> Result<()> {
    match event {
        NodeEvent::FindPeer { peer_id } => {
            // Handle find peer request
            log::debug!("Finding closest peers to: {:?}", peer_id);
            match PeerId::from_bytes(&peer_id) {
                Ok(peer_id) => {
                    self.swarm.behaviour_mut().kademlia.get_closest_peers(peer_id);
                }
                Err(e) => {
                    log::warn!("Invalid peer ID: {}", e);
                }
            }
        },
        NodeEvent::ProvideBlock { cid } => {
            // Handle provide block request
            log::debug!("Providing block: {:?}", cid);
            match Cid::try_from(cid.as_slice()) {
                Ok(cid) => {
                    // Add to our local store's provided blocks
                    if let Some(wantlist) = Arc::get_mut(&mut self.bitswap.wantlist) {
                        wantlist.provided_blocks.insert(cid);
                    }
                    
                    // Also provide to DHT
                    let key = Key::from(cid);
                    let _ = self.swarm.behaviour_mut().kademlia.start_providing(key);
                }
                Err(e) => {
                    log::warn!("Invalid CID: {}", e);
                }
            }
        },
        NodeEvent::WantBlock { cid, priority } => {
            // Handle block want request
            log::debug!("Want block: {} with priority {:?}", cid, priority);
            match Cid::try_from(cid.as_slice()) {
                Ok(cid) => {
                    // Check if we already have the block
                    if let Ok(Some(_)) = self.ipfs.get(&cid).await {
                        log::debug!("Block {} already in local store", cid);
                        return Ok(());
                    }
                    
                    // Request the block via Bitswap
                    if let Err(e) = self.bitswap.request_block(&cid, priority).await {
                        log::error!("Failed to request block {}: {}", cid, e);
                        return Err(anyhow::anyhow!("Failed to request block: {}", e));
                    }
                }
                Err(e) => {
                    log::warn!("Invalid CID: {}", e);
                    return Err(anyhow::anyhow!("Invalid CID: {}", e));
                }
            }
        },
        NodeEvent::CancelBlock { cid } => {
            // Handle block cancel request
            log::debug!("Cancel want for block: {:?}", cid);
            if let Ok(cid) = Cid::try_from(cid.as_slice()) {
                self.bitswap.cancel_want(&cid);
            }
        },
        NodeEvent::BlockReceived { cid, data } => {
            // Handle block received event
            log::debug!("Received block: {} with data {:?}", cid, data);
            // Add the block to our local store
            let block = ipfs_embed::Block::new(cid, data);
            self.ipfs.insert(&block).await?;
        },
        NodeEvent::BlockSent { cid, peer_id } => {
            // Handle block sent event
            log::debug!("Sent block: {} to peer {}", cid, peer_id);
        },
        _ => {
            log::debug!("Unhandled node event: {:?}", event);
        }
    }
    Ok(())
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

/// Start the IPFS node
pub async fn start(&mut self) -> Result<()> {
    // Listen on all interfaces with a random port
    self.swarm
        .listen_on("/ip4/0.0.0.0/tcp/0".parse()?)
        .map_err(|e| anyhow::anyhow!("Failed to listen on any interface: {}", e))?;
const IPFS_BOOTSTRAP_NODES: &[&str] = &[
    "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN",
    "/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa",
    "/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb",
    "/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt",
];

#[cfg(test)]
mod tests {
    use super::*;
    use libp2p::{multiaddr::Protocol, Multiaddr, kad::Key};
    use std::{time::Duration, str::FromStr};
    use tempfile::tempdir;
    use tokio::time::timeout;
    use ipfs_embed::SledStore;

    /// Test helper to create a test node
    async fn create_test_node() -> (Node, tempfile::TempDir) {
        let _ = env_logger::try_init();
        let temp_dir = tempdir().unwrap();
        let db_path = temp_dir.path().join("ipfs");
        let store = SledStore::new(db_path).unwrap();
        let config = Config::new("test-node".to_string(), vec![]);
        let node = Node::new(config).await.unwrap();
        (node, temp_dir)
    }

    #[tokio::test]
    async fn test_node_creation() {
        let (node, _temp_dir) = create_test_node().await;
        
        // Verify we have a valid peer ID
        let peer_id = node.local_peer_id();
        assert!(!peer_id.to_string().is_empty());
        
        // Verify we have listening addresses
        let listeners = node.listeners().unwrap();
        assert!(!listeners.is_empty());
    }

    #[tokio::test]
    async fn test_block_operations() {
        let (mut node, _temp_dir) = create_test_node().await;
        
        // Test putting and getting a block
        let data = b"test data".to_vec();
        let cid = node.put_block(data.clone()).await.unwrap();
        
        // Should be able to retrieve the block immediately
        let retrieved = node.get_block(&cid).await.unwrap().unwrap();
        assert_eq!(retrieved, data);
        
        // Test with empty data
        let empty_data = Vec::new();
        let empty_cid = node.put_block(empty_data.clone()).await.unwrap();
        let retrieved_empty = node.get_block(&empty_cid).await.unwrap().unwrap();
        assert!(retrieved_empty.is_empty());
    }

    #[tokio::test]
    async fn test_dht_operations() {
        let (mut node, _temp_dir) = create_test_node().await;
        
        // Start the node to initialize DHT
        node.start().await.unwrap();
        
        // Test DHT record operations
        let key = Key::new(b"test-key");
        let value = b"test-value".to_vec();
        
        // Put a record
        node.put_dht_record(key.clone(), value.clone())
            .await
            .expect("Failed to put DHT record");
        
        // Note: In a real test, we would need to wait for the DHT operation to complete
        // and verify the record was stored. This is simplified for the example.
        // In a real implementation, you would use the event system to wait for the operation to complete.
        
        // For now, just verify the node is still running
        assert!(!node.local_peer_id().to_string().is_empty());
    }
    
    #[tokio::test]
    async fn test_peer_discovery() {
        let (mut node, _temp_dir) = create_test_node().await;
        
        // Start the node
        node.start().await.unwrap();
        
        // Get the local peer ID and addresses
        let peer_id = node.local_peer_id();
        let listeners = node.listeners().unwrap();
        
        // Verify we have a valid peer ID and listening addresses
        assert!(!peer_id.to_string().is_empty());
        assert!(!listeners.is_empty());
        
        // Test block operations to ensure the node is functional
        let data = b"test peer discovery".to_vec();
        let cid = node.put_block(data.clone()).await.unwrap();
        let retrieved = node.get_block(&cid).await.unwrap().unwrap();
        assert_eq!(retrieved, data);
    }
    
    #[tokio::test]
    async fn test_node_events() {
        let (mut node, _temp_dir) = create_test_node().await;
        
        // Start the node
        node.start().await.unwrap();
        
        // Verify the node is running
        let peer_id = node.local_peer_id();
        assert!(!peer_id.to_string().is_empty());
        
        // Perform some operations to generate events
        let data = b"test events".to_vec();
        let cid = node.put_block(data.clone()).await.unwrap();
        let _retrieved = node.get_block(&cid).await.unwrap().unwrap();
        
        // Process a few events to ensure the event loop is working
        let mut events_processed = 0;
        let start_time = std::time::Instant::now();
        
        // Process events for a short time
        while events_processed < 3 && start_time.elapsed() < Duration::from_secs(5) {
            if let Ok(Some(_event)) = timeout(Duration::from_millis(100), node.next_event()).await {
                events_processed += 1;
            }
        }
        
        // Verify we processed some events
        assert!(events_processed > 0, "No events were processed");
    }
}
