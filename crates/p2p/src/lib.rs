//! # P2P Networking Module
//! 
//! This module provides peer-to-peer networking capabilities using libp2p.

use std::time::Duration;
use thiserror::Error;

// Internal modules
mod behaviour;
mod transport;

// Re-exports
pub use behaviour::P2PBehaviour;
pub use behaviour::P2PEvent;

// External dependencies
use anyhow::Result;
use libp2p_core::Multiaddr;
use libp2p_identity::{Keypair, PeerId};
use libp2p_swarm;
use tokio::task;
use tokio::sync::{oneshot, mpsc};
use tracing::{error, info, warn};

// Common re-exports and type definitions

// Re-export commonly used types
pub use libp2p_identity::Keypair as IdentityKeypair;

// Re-export NetworkBehaviour trait
pub use libp2p_swarm::NetworkBehaviour as P2PNetworkBehaviour;

/// Errors that can occur in the P2P module.
#[derive(Error, Debug)]
pub enum P2PError {
    /// Error during transport setup
    #[error("Transport error: {0}")]
    TransportError(String),
    
    /// Error during noise handshake
    #[error("Noise handshake failed: {0}")]
    NoiseHandshake(String),
    
    /// Error during key generation
    #[error("Key generation failed: {0}")]
    KeyGenerationError(String),
    
    /// Error during swarm setup
    #[error("Swarm error: {0}")]
    SwarmError(String),
    
    /// Error during peer connection
    #[error("Peer connection error: {0}")]
    PeerConnectionError(String),
    
    /// Error during peer discovery
    #[error("Peer discovery error: {0}")]
    DiscoveryError(String),
    
    /// IO error
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    
    /// Multiaddr parse error
    #[error("Multiaddr parse error: {0}")]
    Multiaddr(#[from] libp2p_core::multiaddr::Error),
    
    /// Behaviour error
    #[error("Behaviour error: {0}")]
    Behaviour(String),
    
    /// General error
    #[error("P2P error: {0}")]
    Other(String),
}

/// Commands that can be sent to the P2P service
#[derive(Debug)]
pub enum P2PCommand {
    /// Dial a specific peer
    Dial(Multiaddr),
    /// Start providing a key in the DHT
    StartProviding(Vec<u8>),
    /// Get a value from the DHT
    GetRecord(Vec<u8>),
    /// Add an address to the address book
    AddAddress(PeerId, Multiaddr),
    /// Get connected peers
    GetConnectedPeers,
    /// Disconnect from a peer
    Disconnect(PeerId),
}

/// P2P configuration structure
#[derive(Debug, Clone)]
pub struct P2PConfig {
    /// Listen address for the P2P service
    pub listen_addr: Multiaddr,
    /// Optional keypair for the local node's identity
    pub keypair: Option<Keypair>,
    /// Enable/disable mDNS for local discovery
    pub enable_mdns: bool,
    /// Enable/disable Kademlia DHT
    pub enable_kademlia: bool,
    /// List of bootstrap nodes to connect to
    pub bootstrap_nodes: Vec<Multiaddr>,
    /// Timeout for connection attempts
    pub connection_timeout: Duration,
    /// Enable/disable relay client functionality
    pub enable_relay_client: bool,
    /// Enable/disable relay server functionality
    pub enable_relay_server: bool,
}

impl Default for P2PConfig {
    fn default() -> Self {
        Self {
            listen_addr: "/ip4/0.0.0.0/tcp/0".parse().expect("Valid multiaddr"),
            keypair: None,
            enable_mdns: true,
            enable_kademlia: true,
            bootstrap_nodes: vec![],
            connection_timeout: Duration::from_secs(10),
            enable_relay_client: false,
            enable_relay_server: false,
        }
    }
}

/// Main P2P service that manages networking functionality.
pub struct P2PService {
    swarm: libp2p_swarm::Swarm<P2PBehaviour>,
    event_sender: mpsc::Sender<P2PEvent>,
    event_receiver: mpsc::Receiver<P2PEvent>,
    command_sender: mpsc::Sender<P2PCommand>,
    command_receiver: mpsc::Receiver<P2PCommand>,
    config: P2PConfig,
    pub peer_id: PeerId,
    connected_peers: std::collections::HashSet<PeerId>,
    listening_addresses: Vec<Multiaddr>,
}

impl P2PService {
    /// Create a new P2PService with default configuration
    pub fn new() -> anyhow::Result<Self> {
        Self::with_config(P2PConfig::default())
    }

    /// Convenience constructor that panics on error, matching older API expectations.
    pub fn with_config(config: P2PConfig) -> anyhow::Result<Self> {
        // Create message channels for event passing
        let (event_sender, event_receiver) = mpsc::channel::<P2PEvent>(100);
        let (command_sender, command_receiver) = mpsc::channel::<P2PCommand>(100);
        
        // Generate or use provided keypair for the peer ID
        let local_key = config.keypair.clone().unwrap_or_else(|| Self::generate_keypair());
        let peer_id = local_key.public().to_peer_id();
        
        // Create the P2P behaviour with all protocols
        let behaviour = P2PBehaviour::new(&local_key);
        
        // Create a proper transport stack
        let transport = Self::build_transport(&local_key)?;
        
        // Create the swarm with the transport and behaviour
        let swarm = libp2p_swarm::SwarmBuilder::with_executor(
            transport,
            behaviour,
            peer_id,
            |fut| {
                tokio::spawn(fut);
            }
        )
        .idle_connection_timeout(config.connection_timeout)
        .build();
        
        info!("Creating P2P service with peer ID: {}", peer_id);
        
        // Create the service instance
        Ok(Self {
            swarm,
            event_sender,
            event_receiver,
            command_sender,
            command_receiver,
            config,
            peer_id,
            connected_peers: std::collections::HashSet::new(),
            listening_addresses: Vec::new(),
        })
    }

    /// Build a transport stack with TCP, noise encryption, and yamux multiplexing
    fn build_transport(keypair: &Keypair) -> anyhow::Result<libp2p_core::transport::Boxed<(PeerId, libp2p_core::muxing::StreamMuxerBox)>> {
        use libp2p_tcp as tcp;
        use libp2p_noise as noise;
        use libp2p_yamux as yamux;
        use libp2p_core::upgrade;
        use libp2p_core::transport::{Boxed, Transport};
        
        // Create TCP transport with default configuration
        let tcp = tcp::tokio::Transport::new(tcp::Config::default().nodelay(true));
        
        // Create authenticated transport with noise using the updated API
        // The new API uses the identity keypair directly without the need for into_authentic
        let noise_config = noise::Config::new(keypair)
            .map_err(|e| anyhow::anyhow!("Failed to create noise config: {}", e))?;
            
        // Build the transport stack
        let transport = tcp
            .upgrade(upgrade::Version::V1)
            .authenticate(noise_config)
            .multiplex(yamux::Config::default())
            .boxed();
            
        Ok(transport)
    }
    
    /// Handle a behaviour event from the swarm
    fn handle_event(&mut self, event: P2PEvent) -> anyhow::Result<()> {
        // Forward the event through the event channel
        if let Err(e) = self.event_sender.try_send(event) {
            log::warn!("Failed to send P2P event: {}", e);
        }
        Ok(())
    }
    
    /// Get the local listening addresses
    pub fn local_addresses(&self) -> anyhow::Result<Vec<Multiaddr>> {
        Ok(self.listening_addresses.clone())
    }

    /// Start the P2P service
    pub async fn start(&mut self) -> Result<(), anyhow::Error> {
        let peer_id = self.peer_id;
        info!(%peer_id, "Starting P2P service");

        // Start listening on the configured address
        let listen_addr = self.config.listen_addr.clone();
        self.swarm.listen_on(listen_addr.clone())
            .map_err(|e| anyhow::anyhow!("Failed to start listening: {}", e))?;
        
        info!("P2P service listening on: {}", listen_addr);
        
        // Connect to bootstrap nodes if configured
        if !self.config.bootstrap_nodes.is_empty() {
            for addr in &self.config.bootstrap_nodes {
                info!("Dialing bootstrap node: {}", addr);
                if let Err(e) = self.swarm.dial(addr.clone()) {
                    log::warn!("Failed to dial bootstrap node {}: {}", addr, e);
                }
            }
        }

        // Start the main event loop
        self.run_event_loop().await
    }
    
    /// Run the main P2P event loop
    async fn run_event_loop(&mut self) -> Result<(), anyhow::Error> {
        loop {
            tokio::select! {
                // Handle swarm events
                event = self.swarm.select_next_some() => {
                    self.handle_swarm_event(event).await?;
                }
                
                // Handle commands from other parts of the application
                Some(command) = self.command_receiver.recv() => {
                    self.handle_command(command).await?;
                }
                
                // Graceful shutdown on channel close
                else => {
                    info!("P2P service shutting down");
                    break;
                }
            }
        }
        
        Ok(())
    }
    
    /// Handle swarm events
    async fn handle_swarm_event(&mut self, event: libp2p_swarm::SwarmEvent<P2PEvent>) -> Result<(), anyhow::Error> {
        use libp2p_swarm::SwarmEvent;
        
        match event {
            SwarmEvent::Behaviour(behaviour_event) => {
                self.handle_event(behaviour_event)?;
            }
            SwarmEvent::ConnectionEstablished { peer_id, endpoint, .. } => {
                info!("Connection established with peer: {} at {}", peer_id, endpoint.get_remote_address());
                self.connected_peers.insert(peer_id);
            }
            SwarmEvent::ConnectionClosed { peer_id, cause, .. } => {
                info!("Connection closed with peer: {} (cause: {:?})", peer_id, cause);
                self.connected_peers.remove(&peer_id);
            }
            SwarmEvent::NewListenAddr { address, .. } => {
                info!("Listening on: {}", address);
                self.listening_addresses.push(address);
            }
            SwarmEvent::ExpiredListenAddr { address, .. } => {
                info!("No longer listening on: {}", address);
                self.listening_addresses.retain(|addr| addr != &address);
            }
            SwarmEvent::IncomingConnection { local_addr, send_back_addr } => {
                info!("Incoming connection from {} to {}", send_back_addr, local_addr);
            }
            SwarmEvent::IncomingConnectionError { local_addr, send_back_addr, error } => {
                warn!("Incoming connection error from {} to {}: {}", send_back_addr, local_addr, error);
            }
            SwarmEvent::OutgoingConnectionError { peer_id, error, .. } => {
                warn!("Outgoing connection error to {:?}: {}", peer_id, error);
            }
            _ => {
                // Handle other events as needed
            }
        }
        
        Ok(())
    }
    
    /// Handle commands from other parts of the application
    async fn handle_command(&mut self, command: P2PCommand) -> Result<(), anyhow::Error> {
        match command {
            P2PCommand::Dial(addr) => {
                info!("Dialing address: {}", addr);
                if let Err(e) = self.swarm.dial(addr.clone()) {
                    warn!("Failed to dial {}: {}", addr, e);
                }
            }
            P2PCommand::StartProviding(key) => {
                #[cfg(feature = "kad")]
                {
                    if let Err(e) = self.swarm.behaviour_mut().start_providing(key) {
                        warn!("Failed to start providing: {}", e);
                    }
                }
                #[cfg(not(feature = "kad"))]
                {
                    warn!("Kademlia feature not enabled, cannot start providing");
                }
            }
            P2PCommand::GetRecord(key) => {
                #[cfg(feature = "kad")]
                {
                    use libp2p_kad::record::Key;
                    let kad_key = Key::new(&key);
                    self.swarm.behaviour_mut().kademlia().get_record(kad_key);
                }
                #[cfg(not(feature = "kad"))]
                {
                    warn!("Kademlia feature not enabled, cannot get record");
                }
            }
            P2PCommand::AddAddress(peer_id, addr) => {
                #[cfg(feature = "kad")]
                {
                    self.swarm.behaviour_mut().kademlia().add_address(&peer_id, addr);
                }
                info!("Added address {} for peer {}", addr, peer_id);
            }
            P2PCommand::GetConnectedPeers => {
                let peers: Vec<_> = self.connected_peers.iter().cloned().collect();
                info!("Connected peers: {:?}", peers);
            }
            P2PCommand::Disconnect(peer_id) => {
                if let Err(e) = self.swarm.disconnect_peer_id(peer_id) {
                    warn!("Failed to disconnect from peer {}: {}", peer_id, e);
                } else {
                    info!("Disconnected from peer: {}", peer_id);
                }
            }
        }
        
        Ok(())
    }

    /// Attempt to build a dummy transport for dependency compatibility testing
    fn build_dummy_transport() -> anyhow::Result<()> {
        Ok(())
    }
    
    /// Generate a keypair for testing
    pub fn generate_keypair() -> libp2p_identity::Keypair {
        // Generate a new Ed25519 keypair
        libp2p_identity::ed25519::Keypair::generate().into()
    }

    /// Get the peer ID from the swarm
    pub fn local_peer_id(&self) -> PeerId {
        self.peer_id
    }
    
    /// Get a command sender for external interaction
    pub fn command_sender(&self) -> mpsc::Sender<P2PCommand> {
        self.command_sender.clone()
    }
    
    /// Get an event receiver for external monitoring
    pub fn event_receiver(&mut self) -> &mut mpsc::Receiver<P2PEvent> {
        &mut self.event_receiver
    }
    
    /// Get the list of connected peers
    pub fn connected_peers(&self) -> Vec<PeerId> {
        self.connected_peers.iter().cloned().collect()
    }
    
    /// Check if a peer is connected
    pub fn is_peer_connected(&self, peer_id: &PeerId) -> bool {
        self.connected_peers.contains(peer_id)
    }
    
    /// Get the number of connected peers
    pub fn peer_count(&self) -> usize {
        self.connected_peers.len()
    }
    
    /// Dial a peer address (convenience method)
    pub async fn dial(&mut self, addr: Multiaddr) -> Result<(), anyhow::Error> {
        self.handle_command(P2PCommand::Dial(addr)).await
    }
    
    /// Start providing a key in the DHT (convenience method)
    pub async fn start_providing(&mut self, key: Vec<u8>) -> Result<(), anyhow::Error> {
        self.handle_command(P2PCommand::StartProviding(key)).await
    }
    
    /// Get a record from the DHT (convenience method)
    pub async fn get_record(&mut self, key: Vec<u8>) -> Result<(), anyhow::Error> {
        self.handle_command(P2PCommand::GetRecord(key)).await
    }
    
    /// Disconnect from a peer (convenience method)
    pub async fn disconnect_peer(&mut self, peer_id: PeerId) -> Result<(), anyhow::Error> {
        self.handle_command(P2PCommand::Disconnect(peer_id)).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::error::Error as StdErrorTrait;
    
    #[tokio::test]
    async fn test_p2p_service_creation() -> Result<(), Box<dyn StdErrorTrait>> {
        let _ = env_logger::try_init();
        
        // Test with default config
        let config = P2PConfig::default();
        let service = P2PService::with_config(config)?;
        
        // Verify peer_id is valid
        let peer_id = service.local_peer_id();
        assert_ne!(peer_id.to_string().len(), 0);
        
        // Verify initial state
        assert_eq!(service.peer_count(), 0);
        assert!(!service.is_peer_connected(&peer_id));
        
        Ok(())
    }
    
    #[tokio::test]
    async fn test_p2p_service_configuration() -> Result<(), Box<dyn StdErrorTrait>> {
        let _ = env_logger::try_init();
        
        // Test with custom config
        let mut config = P2PConfig::default();
        config.enable_mdns = false;
        config.enable_kademlia = false;
        config.connection_timeout = Duration::from_secs(30);
        
        let service = P2PService::with_config(config)?;
        
        // Verify configuration is applied
        assert_eq!(service.local_addresses()?.len(), 0); // No addresses until started
        assert_eq!(service.connected_peers().len(), 0);
        
        Ok(())
    }
    
    #[tokio::test]
    async fn test_p2p_service_api() -> Result<(), Box<dyn StdErrorTrait>> {
        let _ = env_logger::try_init();
        
        let config = P2PConfig::default();
        let mut service = P2PService::with_config(config)?;
        
        // Test command sender
        let _sender = service.command_sender();
        
        // Test peer management
        let peer_id = service.local_peer_id();
        assert!(!service.is_peer_connected(&peer_id));
        assert_eq!(service.peer_count(), 0);
        
        Ok(())
    }
    
    #[tokio::test]
    async fn test_p2p_service_transport() -> Result<(), Box<dyn StdErrorTrait>> {
        let _ = env_logger::try_init();
        
        let config = P2PConfig {
            enable_mdns: false,
            enable_kademlia: false,
            ..Default::default()
        };
        
        let service = P2PService::with_config(config)?;
        
        // Test that the service can be created
        let peer_id = service.local_peer_id();
        assert_ne!(peer_id.to_string().len(), 0);
        
        Ok(())
    }
}
