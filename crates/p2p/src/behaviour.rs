//! Custom network behaviour combining Identify, Ping, Kademlia, and mDNS.

use libp2p_core::{Endpoint, Multiaddr};
use libp2p_identity::Keypair;
use libp2p_swarm::{
    ConnectionDenied, ConnectionId, FromSwarm, NetworkBehaviour,
    PollParameters, ToSwarm,
};
use libp2p_identify as identify;
use libp2p_ping as ping;
use std::task::{Context, Poll};
use std::{collections::VecDeque, time::Duration};
use void::Void;

#[cfg(feature = "kad")]
use libp2p_kad::{Kademlia, KademliaEvent, record::store::MemoryStore};

#[cfg(feature = "mdns")]
use libp2p_mdns::{tokio::Behaviour as Mdns, Config as MdnsConfig, Event as MdnsEvent};

/// Composite behaviour out-event
#[derive(Debug)]
pub enum P2PEvent {
    /// An event from the Identify protocol
    Identify(identify::Event),
    /// A ping event
    Ping(ping::Event),
    /// A Kademlia event (if Kademlia feature is enabled)
    #[cfg(feature = "kad")]
    Kademlia(KademliaEvent),
    /// An mDNS event (if mDNS feature is enabled)
    #[cfg(feature = "mdns")]
    Mdns(MdnsEvent),
}

/// Network behaviour that combines multiple protocols
pub struct P2PBehaviour {
    /// Identify protocol behaviour
    identify: identify::Behaviour,
    /// Ping protocol behaviour
    ping: ping::Behaviour,
    /// Kademlia DHT (optional)
    #[cfg(feature = "kad")]
    kademlia: Kademlia<MemoryStore>,
    /// mDNS discovery (optional)
    #[cfg(feature = "mdns")]
    mdns: Mdns,
    /// Queue of events to be processed
    events: VecDeque<P2PEvent>,
}

impl NetworkBehaviour for P2PBehaviour {
    type ConnectionHandler = libp2p_swarm::dummy::ConnectionHandler;
    type ToSwarm = P2PEvent;

    fn handle_established_inbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: libp2p_identity::PeerId,
        local_addr: &Multiaddr,
        remote_addr: &Multiaddr,
    ) -> Result<Self::ConnectionHandler, ConnectionDenied> {
        // Delegate to all active behaviours
        self.identify.handle_established_inbound_connection(
            connection_id,
            peer,
            local_addr,
            remote_addr,
        )?;
        self.ping.handle_established_inbound_connection(
            connection_id,
            peer,
            local_addr,
            remote_addr,
        )?;
        
        #[cfg(feature = "kad")]
        self.kademlia.handle_established_inbound_connection(
            connection_id,
            peer,
            local_addr,
            remote_addr,
        )?;
        
        #[cfg(feature = "mdns")]
        self.mdns.handle_established_inbound_connection(
            connection_id,
            peer,
            local_addr,
            remote_addr,
        )?;
        
        Ok(libp2p_swarm::dummy::ConnectionHandler)
    }

    fn handle_established_outbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: libp2p_identity::PeerId,
        addr: &Multiaddr,
        role_override: Endpoint,
    ) -> Result<Self::ConnectionHandler, ConnectionDenied> {
        // Delegate to all active behaviours
        self.identify.handle_established_outbound_connection(
            connection_id,
            peer,
            addr,
            role_override,
        )?;
        self.ping.handle_established_outbound_connection(
            connection_id,
            peer,
            addr,
            role_override,
        )?;
        
        #[cfg(feature = "kad")]
        self.kademlia.handle_established_outbound_connection(
            connection_id,
            peer,
            addr,
            role_override,
        )?;
        
        #[cfg(feature = "mdns")]
        self.mdns.handle_established_outbound_connection(
            connection_id,
            peer,
            addr,
            role_override,
        )?;
        
        Ok(libp2p_swarm::dummy::ConnectionHandler)
    }

    fn on_swarm_event(&mut self, event: FromSwarm<Self::ConnectionHandler>) {
        // Delegate to all active behaviours
        self.identify.on_swarm_event(event.clone());
        self.ping.on_swarm_event(event.clone());
        
        #[cfg(feature = "kad")]
        self.kademlia.on_swarm_event(event.clone());
        
        #[cfg(feature = "mdns")]
        self.mdns.on_swarm_event(event.clone());
        
        // Handle connection established events
        if let FromSwarm::ConnectionEstablished(conn_established) = &event {
            // Add peer to Kademlia if enabled
            #[cfg(feature = "kad")]
            if conn_established.other_established == 0 {
                self.kademlia.add_address(&conn_established.peer_id, conn_established.address.clone());
            }
        }
    }

    fn on_connection_handler_event(
        &mut self,
        peer_id: libp2p_identity::PeerId,
        connection_id: ConnectionId,
        event: <Self::ConnectionHandler as libp2p_swarm::ConnectionHandler>::ToBehaviour,
    ) {
        // Handle events from the connection handler
        match event {}
    }

    fn poll(
        &mut self,
        cx: &mut Context<'_>,
        params: &mut impl PollParameters,
    ) -> Poll<ToSwarm<Self::ToSwarm, libp2p_swarm::THandlerInEvent<Self>>> {
        // Poll identify behaviour
        if let Poll::Ready(event) = self.identify.poll(cx, params) {
            return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Identify(event)));
        }

        // Poll ping behaviour
        if let Poll::Ready(event) = self.ping.poll(cx, params) {
            return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Ping(event)));
        }
        
        // Poll Kademlia if enabled
        #[cfg(feature = "kad")]
        if let Poll::Ready(event) = self.kademlia.poll(cx, params) {
            return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Kademlia(event)));
        }
        
        // Poll mDNS if enabled
        #[cfg(feature = "mdns")]
        if let Poll::Ready(event) = self.mdns.poll(cx, params) {
            return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Mdns(event)));
        }

        Poll::Pending
    }
}

impl P2PBehaviour {
    /// Create a new P2PBehaviour with the given keypair
    pub fn new(keypair: &Keypair) -> Self {
        let local_peer_id = keypair.public().to_peer_id();
        
        // Create identify with protocol name and our keypair's public key
        let identify = identify::Behaviour::new(identify::Config::new(
            "/ipfs/id/1.0.0".to_string(),
            keypair.public(),
        ).with_agent_version("p2p/0.1.0"));
        
        // Create ping behaviour with default configuration
        let ping = ping::Behaviour::new(ping::Config::new()
            .with_interval(Duration::from_secs(15))
            .with_timeout(Duration::from_secs(10)));
        
        // Create Kademlia if enabled
        #[cfg(feature = "kad")]
        let kademlia = {
            let store = MemoryStore::new(local_peer_id);
            let mut kad = Kademlia::new(local_peer_id, store);
            // Bootstrap with some well-known peers
            kad.bootstrap().ok();
            kad
        };
        
        // Create mDNS if enabled
        #[cfg(feature = "mdns")]
        let mdns = {
            Mdns::new(MdnsConfig::default())
                .expect("mDNS service creation failed")
        };
        
        Self {
            identify,
            ping,
            #[cfg(feature = "kad")]
            kademlia,
            #[cfg(feature = "mdns")]
            mdns,
            events: VecDeque::new(),
        }
    }
    
    /// Get the local peer ID
    pub fn local_peer_id(&self) -> libp2p_identity::PeerId {
        self.identify.local_peer_id()
    }
    
    /// Get a mutable reference to the Kademlia instance (if enabled)
    #[cfg(feature = "kad")]
    pub fn kademlia(&mut self) -> &mut Kademlia<MemoryStore> {
        &mut self.kademlia
    }
    
    /// Bootstrap the Kademlia DHT (if enabled)
    #[cfg(feature = "kad")]
    pub fn bootstrap_kademlia(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        self.kademlia.bootstrap()?;
        Ok(())
    }
    
    /// Start providing a value in the DHT (if Kademlia is enabled)
    #[cfg(feature = "kad")]
    pub fn start_providing(&mut self, key: Vec<u8>) -> Result<(), Box<dyn std::error::Error>> {
        use libp2p_kad::record::Key;
        let key = Key::new(&key);
        self.kademlia.start_providing(key)?;
        Ok(())
    }
    
    /// Get the list of known peers (if mDNS is enabled)
    #[cfg(feature = "mdns")]
    pub fn discovered_peers(&self) -> Vec<libp2p_identity::PeerId> {
        self.mdns.discovered_nodes().cloned().collect()
    }
}

// Implement From traits for our event types
impl From<identify::Event> for P2PEvent {
    fn from(event: identify::Event) -> Self {
        P2PEvent::Identify(event)
    }
}

impl From<ping::Event> for P2PEvent {
    fn from(event: ping::Event) -> Self {
        P2PEvent::Ping(event)
    }
}

#[cfg(feature = "kad")]
impl From<KademliaEvent> for P2PEvent {
    fn from(event: KademliaEvent) -> Self {
        P2PEvent::Kademlia(event)
    }
}

#[cfg(feature = "mdns")]
impl From<MdnsEvent> for P2PEvent {
    fn from(event: MdnsEvent) -> Self {
        P2PEvent::Mdns(event)
    }
}

// Default implementation useful for tests
impl Default for P2PBehaviour {
    fn default() -> Self {
        let keypair = Keypair::generate_ed25519();
        Self::new(&keypair)
    }
}
