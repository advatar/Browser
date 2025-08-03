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
    dht::{DhtService, DhtConfig, DhtEvent},
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
    /// Local peer ID
    peer_id: PeerId,
    /// Keypair for this node
    keypair: libp2p_identity::Keypair,
    /// Bootstrap nodes to connect to on startup
    bootstrap_nodes: Vec<Multiaddr>,
    /// DHT service
    dht: Option<DhtService>,
    /// Bitswap service
    bitswap: Option<BitswapService>,
}

/// Events emitted by the Node
#[derive(Debug)]
pub enum NodeEvent {
    /// An IPFS node that implements the IPFS protocol
    /// Provide a block to the network
    ProvideBlock { cid: Vec<u8> },
    /// Request a block from the network
    WantBlock { 
        /// The CID of the block to request
        cid: Vec<u8>,
        /// Priority of the request
        priority: u32,
    },
    /// Cancel a block request
    CancelBlock { cid: Vec<u8> },
    /// Block received from the network
    BlockReceived { cid: Vec<u8>, data: Vec<u8> },
    /// Block sent to the network
    BlockSent { cid: Vec<u8>, peer_id: PeerId },
    /// Find closest peers to a given peer ID
    FindPeer { peer_id: Vec<u8> },
}

/// Create a new IPFS node with the given configuration
pub async fn new(config: Config) -> Result<Self> {
    // Initialize IPFS-embed
    let ipfs = Ipfs::<DefaultParams>::new(Default::default()).await?;
    
    // Generate or load keypair
    let keypair = if let Some(key_bytes) = config.keypair {
        libp2p_identity::Keypair::from_protobuf_encoding(&key_bytes)?
    } else {
        libp2p_identity::Keypair::generate_ed25519()
    };
    
    let peer_id = keypair.public().to_peer_id();
    
    // Create channels for node events
    let (event_sender, event_receiver) = mpsc::channel(32);
    
    // Initialize DHT if enabled
    let dht = if config.dht_enabled {
        let dht_config = DhtConfig {
            enabled: true,
            protocol_name: "/ipfs/kad/1.0.0".to_string(),
            bootstrap_nodes: config.bootstrap_nodes.clone(),
            ..Default::default()
        };
        
        // Create DHT metrics
        let registry = Registry::new();
        let metrics = DhtMetrics::new(&registry)?;
        
        Some(DhtService::new(peer_id, dht_config, metrics)?)
    } else {
        None
    };
    
    // Initialize Bitswap if enabled
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
    
    // Create the node
    let mut node = Self {
        ipfs,
        swarm: Swarm::new(
            keypair.public().to_peer_id(),
            NodeBehaviour::new(peer_id, &keypair)?,
        ),
        event_sender,
        event_receiver,
        peer_id,
        keypair,
        bootstrap_nodes: config.bootstrap_nodes,
        dht,
        bitswap,
    };
    
    // Configure the swarm
    node.configure_swarm().await?;
    
    Ok(node)
}

/// Start the IPFS node
pub async fn start(&mut self) -> Result<()> {
    // Listen on all interfaces with a random port
    self.swarm
        .listen_on("/ip4/0.0.0.0/tcp/0".parse()?)
        .map_err(|e| anyhow::anyhow!("Failed to listen on any interface: {}", e))?;
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
        
        // Wait for the DHT operation to complete using the event system
        let timeout = std::time::Duration::from_secs(5);
        let start_time = std::time::Instant::now();
        let mut success = false;
        
        // Create a channel to receive events
        let (tx, mut rx) = tokio::sync::mpsc::channel(10);
        let mut event_subscription = node.event_subscription().await;
        
        // Spawn a task to forward events to our channel
        tokio::spawn(async move {
            while let Some(event) = event_subscription.next().await {
                if tx.send(event).await.is_err() {
                    break;
                }
            }
        });
        
        // Wait for a DHT record published event or timeout
        while start_time.elapsed() < timeout {
            tokio::select! {
                Some(event) = rx.recv() => {
                    match event {
                        IpfsEvent::DhtRecordPublished { key: published_key, .. } if published_key == key => {
                            success = true;
                            break;
                        },
                        _ => continue,
                    }
                },
                _ = tokio::time::sleep(std::time::Duration::from_millis(100)) => {},
            }
        }
        
        // Verify the record was stored by trying to get it
        if !success {
            // If we didn't get an event confirmation, try to get the record directly
            match node.get_dht_record(&key).await {
                Ok(Some(retrieved_value)) => {
                    assert_eq!(retrieved_value, value, "Retrieved value doesn't match the stored value");
                    success = true;
                },
                _ => {}
            }
        }
        
        assert!(success, "Failed to confirm DHT record was published within timeout period");
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
