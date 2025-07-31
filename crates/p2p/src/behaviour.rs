//! Custom network behaviour combining Identify, Ping, Kademlia, and mDNS.

use libp2p_core::{Endpoint, Multiaddr, connection::ConnectionId, upgrade};
use libp2p_identity::Keypair;
use libp2p_swarm::{
    ConnectionDenied, FromSwarm, NetworkBehaviour,
    PollParameters, ToSwarm, ConnectionHandler, ConnectionHandlerUpgrErr,
    THandlerInEvent, THandlerOutEvent, THandler, StreamMuxerBox, ConnectionHandlerEvent,
    StreamUpgradeError, SubstreamProtocol, upgrade, ConnectedPoint, 
    handler::ConnectionEvent, ConnectionHandlerUpgrErr::Timer,
};
use libp2p_identify as identify;
use libp2p_ping as ping;
use std::task::{Context, Poll};
use std::{collections::VecDeque, time::Duration, pin::Pin, future::Future, io};
use futures::io::{AsyncRead, AsyncWrite};
use void::Void;
use async_trait::async_trait;
use libp2p_core::upgrade::ProtocolName;
use std::borrow::Cow;

/// Events sent from the behaviour to the connection handler
#[derive(Debug)]
pub enum P2PInEvent {
    /// An event for the Identify protocol
    Identify(<identify::handler::IdentifyPushHandler as ConnectionHandler>::FromBehaviour),
    /// A ping event
    Ping(<ping::handler::PingHandler as ConnectionHandler>::FromBehaviour),
}

/// Events sent from the connection handler to the behaviour
#[derive(Debug)]
pub enum P2PHandlerEvent {
    /// An event from the Identify protocol
    Identify(<identify::handler::IdentifyPushHandler as ConnectionHandler>::ToBehaviour),
    /// A ping event
    Ping(<ping::handler::PingHandler as ConnectionHandler>::ToBehaviour),
}

/// Protocol for inbound substreams
#[derive(Debug, Clone)]
pub struct P2PInboundProtocol;

/// Protocol for outbound substreams
#[derive(Debug, Clone)]
pub struct P2POutboundProtocol;

impl upgrade::UpgradeInfo for P2PInboundProtocol {
    type Info = &'static [u8];
    type InfoIter = std::iter::Once<Self::Info>;

    fn protocol_info(&self) -> Self::InfoIter {
        // We'll use the identify protocol name for now, as it's the only one we support
        std::iter::once(b"/ipfs/id/1.0.0")
    }
}

#[async_trait::async_trait]
impl<TSocket> upgrade::InboundUpgrade<TSocket> for P2PInboundProtocol
where
    TSocket: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    type Output = P2PInboundProtocolOutput;
    type Error = std::io::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Output, Self::Error>> + Send>>;

    fn upgrade_inbound(self, socket: TSocket, _: Self::Info) -> Self::Future {
        // For now, we'll just try to parse as identify protocol
        let identify = identify::handler::IdentifyPushHandler::protocol()
            .upgrade_inbound(socket, ())
            .map_ok(P2PInboundProtocolOutput::Identify);
        
        Box::pin(identify)
    }
}

impl upgrade::UpgradeInfo for P2POutboundProtocol {
    type Info = &'static [u8];
    type InfoIter = std::iter::Once<Self::Info>;

    fn protocol_info(&self) -> Self::InfoIter {
        // We'll use the ping protocol name for outbound connections
        std::iter::once(b"/ipfs/ping/1.0.0")
    }
}

#[async_trait::async_trait]
impl<TSocket> upgrade::OutboundUpgrade<TSocket> for P2POutboundProtocol
where
    TSocket: AsyncRead + AsyncWrite + Unpin + Send + 'static,
{
    type Output = P2POutboundProtocolOutput;
    type Error = std::io::Error;
    type Future = Pin<Box<dyn Future<Output = Result<Self::Output, Self::Error>> + Send>>;

    fn upgrade_outbound(self, socket: TSocket, _: Self::Info) -> Self::Future {
        // For now, we'll just try to use the ping protocol
        let ping = ping::handler::PingHandler::protocol()
            .upgrade_outbound(socket, ())
            .map_ok(P2POutboundProtocolOutput::Ping);
        
        Box::pin(ping)
    }
}

/// Output of inbound protocol negotiation
#[derive(Debug)]
pub enum P2PInboundProtocolOutput {
    /// Identify protocol output
    Identify(<identify::handler::IdentifyPushHandler as ConnectionHandler>::InboundProtocol),
    /// Ping protocol output
    Ping(<ping::handler::PingHandler as ConnectionHandler>::InboundProtocol),
}

/// Output of outbound protocol negotiation
#[derive(Debug)]
pub enum P2POutboundProtocolOutput {
    /// Identify protocol output
    Identify(<identify::handler::IdentifyPushHandler as ConnectionHandler>::OutboundProtocol),
    /// Ping protocol output
    Ping(<ping::handler::PingHandler as ConnectionHandler>::OutboundProtocol),
}

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

/// Custom connection handler that combines multiple protocols
pub struct P2PConnectionHandler {
    identify: identify::handler::IdentifyPushHandler,
    ping: ping::handler::PingHandler,
    events: VecDeque<ConnectionHandlerEvent<(), (), P2PEvent, std::io::Error>>,
}

impl ConnectionHandler for P2PConnectionHandler {
    type FromBehaviour = P2PInEvent;
    type ToBehaviour = P2PHandlerEvent;
    type Error = std::io::Error;
    type InboundProtocol = P2PInboundProtocol;
    type OutboundProtocol = P2POutboundProtocol;
    type InboundOpenInfo = ();
    type OutboundOpenInfo = ();
    type CloseBehaviour = void::Void;

    fn listen_protocol(&self) -> SubstreamProtocol<Self::InboundProtocol, Self::InboundOpenInfo> {
        SubstreamProtocol::new(P2PInboundProtocol, ())
    }

    fn on_behaviour_event(&mut self, event: Self::FromBehaviour) {
        match event {
            P2PInEvent::Identify(event) => self.identify.on_behaviour_event(event),
            P2PInEvent::Ping(event) => self.ping.on_behaviour_event(event),
        }
    }

    fn on_connection_event(
        &mut self,
        event: ConnectionEvent<
            '_,
            Self::InboundProtocol,
            Self::OutboundProtocol,
            Self::InboundOpenInfo,
            Self::OutboundOpenInfo,
        >,
    ) {
        match event {
            ConnectionEvent::FullyNegotiatedInbound(protocol, _) => match protocol {
                P2PInboundProtocolOutput::Identify(protocol) => {
                    self.identify.on_connection_event(ConnectionEvent::FullyNegotiatedInbound(protocol, ()));
                }
                P2PInboundProtocolOutput::Ping(protocol) => {
                    self.ping.on_connection_event(ConnectionEvent::FullyNegotiatedInbound(protocol, ()));
                }
            },
            ConnectionEvent::FullyNegotiatedOutbound(protocol, _) => match protocol {
                P2POutboundProtocolOutput::Identify(protocol) => {
                    self.identify.on_connection_event(ConnectionEvent::FullyNegotiatedOutbound(protocol, ()));
                }
                P2POutboundProtocolOutput::Ping(protocol) => {
                    self.ping.on_connection_event(ConnectionEvent::FullyNegotiatedOutbound(protocol, ()));
                }
            },
            ConnectionEvent::AddressChange(address) => {
                self.identify.on_connection_event(ConnectionEvent::AddressChange(address.clone()));
                self.ping.on_connection_event(ConnectionEvent::AddressChange(address));
            }
            ConnectionEvent::DialUpgradeError(DialUpgradeError { info, error }) => {
                log::error!("Dial upgrade error: {:?}", error);
            }
            ConnectionEvent::ListenUpgradeError(_) => {}
            ConnectionEvent::LocalProtocolsChange(_) => {}
            ConnectionEvent::RemoteProtocolsChange(_) => {}
        }
    }

    fn connection_keep_alive(&self) -> KeepAlive {
        // Keep the connection alive if either handler wants to keep it alive
        let identify_keep_alive = self.identify.connection_keep_alive();
        let ping_keep_alive = self.ping.connection_keep_alive();
        
        match (identify_keep_alive, ping_keep_alive) {
            (KeepAlive::Yes, _) | (_, KeepAlive::Yes) => KeepAlive::Yes,
            (KeepAlive::No, KeepAlive::No) => KeepAlive::No,
            (KeepAlive::Until(t1), KeepAlive::Until(t2)) => KeepAlive::Until(t1.min(t2)),
            (KeepAlive::Until(t), KeepAlive::No) | (KeepAlive::No, KeepAlive::Until(t)) => KeepAlive::Until(t),
            _ => KeepAlive::No,
        }
    }
    
    fn poll_close(&mut self, _: &mut Context<'_>) -> Poll<Option<Self::CloseBehaviour>> {
        Poll::Ready(None)
    }

    fn poll(
        &mut self,
        cx: &mut Context<'_>,
    ) -> Poll<ConnectionHandlerEvent<Self::OutboundProtocol, Self::OutboundOpenInfo, Self::ToBehaviour, Self::Error>> {
        // Check if we have any buffered events to process
        if let Some(event) = self.events.pop_front() {
            return Poll::Ready(event);
        }
        
        // Poll the identify handler
        match self.identify.poll(cx) {
            Poll::Ready(ConnectionHandlerEvent::OutboundSubstreamRequest { protocol, info }) => {
                self.events.push_back(ConnectionHandlerEvent::OutboundSubstreamRequest { protocol, info });
                Poll::Pending
            }
            Poll::Ready(ConnectionHandlerEvent::Custom(event)) => {
                Poll::Ready(ConnectionHandlerEvent::Custom(P2PHandlerEvent::Identify(event)))
            }
            Poll::Ready(ConnectionHandlerEvent::Close(err)) => {
                Poll::Ready(ConnectionHandlerEvent::Close(err))
            }
            Poll::Pending => {
                // Continue to ping handler
                match self.ping.poll(cx) {
                    Poll::Ready(ConnectionHandlerEvent::OutboundSubstreamRequest { protocol, info }) => {
                        self.events.push_back(ConnectionHandlerEvent::OutboundSubstreamRequest { protocol, info });
                        Poll::Pending
                    }
                    Poll::Ready(ConnectionHandlerEvent::Custom(event)) => {
                        Poll::Ready(ConnectionHandlerEvent::Custom(P2PHandlerEvent::Ping(event)))
                    }
                    Poll::Ready(ConnectionHandlerEvent::Close(err)) => {
                        Poll::Ready(ConnectionHandlerEvent::Close(err))
                    }
                    Poll::Pending => Poll::Pending,
                }
            }
        }
    }
}

impl Default for P2PConnectionHandler {
    fn default() -> Self {
        Self {
            identify: identify::handler::IdentifyPushHandler::default(),
            ping: ping::handler::PingHandler::default(),
            events: VecDeque::new(),
        }
    }
}

/// Network behaviour that combines multiple protocols
pub struct P2PBehaviour {
    /// Local peer ID
    local_peer_id: libp2p_identity::PeerId,
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
    type ConnectionHandler = P2PConnectionHandler;
    type ToSwarm = P2PEvent;

    fn handle_established_inbound_connection(
        &mut self,
        _connection_id: ConnectionId,
        _peer: PeerId,
        _local_addr: &Multiaddr,
        _remote_addr: &Multiaddr,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        Ok(P2PConnectionHandler {
            identify: self.identify.new_handler(),
            ping: self.ping.new_handler(),
            events: VecDeque::new(),
        })
    }

    fn handle_established_outbound_connection(
        &mut self,
        _connection_id: ConnectionId,
        _peer: PeerId,
        _addr: &Multiaddr,
        _role_override: Endpoint,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        Ok(P2PConnectionHandler {
            identify: self.identify.new_handler(),
            ping: self.ping.new_handler(),
            events: VecDeque::new(),
        })
    }

    fn on_swarm_event(&mut self, event: FromSwarm<Self::ConnectionHandler>) {
        match &event {
            FromSwarm::ConnectionEstablished(_) => {}
            FromSwarm::ConnectionClosed(_) => {}
            FromSwarm::AddressChange(_) => {}
            FromSwarm::DialFailure(_) => {}
            FromSwarm::ListenFailure(_) => {}
            FromSwarm::NewListener(_) => {}
            FromSwarm::NewListenAddr(_) => {}
            FromSwarm::ExpiredListenAddr(_) => {}
            FromSwarm::ListenerError(_) => {}
            FromSwarm::ListenerClosed(_) => {}
            FromSwarm::NewExternalAddr(_) => {}
            FromSwarm::ExpiredExternalAddr(_) => {}
            _ => {}
        }

        // Delegate to inner behaviours
        self.identify.on_swarm_event(event.clone());
        self.ping.on_swarm_event(event.clone());
        #[cfg(feature = "kad")]
        self.kademlia.on_swarm_event(event.clone());
        #[cfg(feature = "mdns")]
        self.mdns.on_swarm_event(event);
    }

    fn on_connection_handler_event(
        &mut self,
        peer_id: PeerId,
        connection_id: ConnectionId,
        event: <<Self::ConnectionHandler as IntoConnectionHandler>::Handler as ConnectionHandler>::ToBehaviour,
    ) {
        match event {
            P2PHandlerEvent::Identify(event) => {
                self.identify.on_connection_handler_event(peer_id, connection_id, event);
            }
            P2PHandlerEvent::Ping(event) => {
                self.ping.on_connection_handler_event(peer_id, connection_id, event);
            }
        }
    }

    fn poll(
        &mut self,
        cx: &mut Context<'_>,
        _params: &mut impl PollParameters,
    ) -> Poll<ToSwarm<Self::ToSwarm, libp2p_swarm::THandlerInEvent<Self>>> {
        // Poll identify
        if let Poll::Ready(event) = self.identify.poll(cx, &mut ()) {
            match event {
                ToSwarm::GenerateEvent(event) => {
                    return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Identify(event)));
                }
                ToSwarm::Dial { opts } => {
                    return Poll::Ready(ToSwarm::Dial { opts });
                }
                ToSwarm::NotifyHandler { peer_id, handler, event } => {
                    return Poll::Ready(ToSwarm::NotifyHandler { peer_id, handler, event });
                }
                ToSwarm::ReportObservedAddr { address, score } => {
                    return Poll::Ready(ToSwarm::ReportObservedAddr { address, score });
                }
                ToSwarm::CloseConnection { peer_id, connection } => {
                    return Poll::Ready(ToSwarm::CloseConnection { peer_id, connection });
                }
                _ => {}
            }
        }

        // Poll ping
        if let Poll::Ready(event) = self.ping.poll(cx, &mut ()) {
            match event {
                ToSwarm::GenerateEvent(event) => {
                    return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Ping(event)));
                }
                ToSwarm::Dial { opts } => {
                    return Poll::Ready(ToSwarm::Dial { opts });
                }
                ToSwarm::NotifyHandler { peer_id, handler, event } => {
                    return Poll::Ready(ToSwarm::NotifyHandler { peer_id, handler, event });
                }
                ToSwarm::CloseConnection { peer_id, connection } => {
                    return Poll::Ready(ToSwarm::CloseConnection { peer_id, connection });
                }
                _ => {}
            }
        }

        // Poll Kademlia if enabled
        #[cfg(feature = "kad")]
        if let Poll::Ready(event) = self.kademlia.poll(cx, &mut ()) {
            match event {
                ToSwarm::GenerateEvent(event) => {
                    return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Kademlia(event)));
                }
                ToSwarm::Dial { opts } => {
                    return Poll::Ready(ToSwarm::Dial { opts });
                }
                ToSwarm::NotifyHandler { peer_id, handler, event } => {
                    return Poll::Ready(ToSwarm::NotifyHandler { peer_id, handler, event });
                }
                ToSwarm::CloseConnection { peer_id, connection } => {
                    return Poll::Ready(ToSwarm::CloseConnection { peer_id, connection });
                }
                _ => {}
            }
        }

        // Poll mDNS if enabled
        #[cfg(feature = "mdns")]
        if let Poll::Ready(event) = self.mdns.poll(cx, &mut ()) {
            match event {
                ToSwarm::GenerateEvent(event) => {
                    return Poll::Ready(ToSwarm::GenerateEvent(P2PEvent::Mdns(event)));
                }
                ToSwarm::Dial { opts } => {
                    return Poll::Ready(ToSwarm::Dial { opts });
                }
                ToSwarm::NotifyHandler { peer_id, handler, event } => {
                    return Poll::Ready(ToSwarm::NotifyHandler { peer_id, handler, event });
                }
                ToSwarm::CloseConnection { peer_id, connection } => {
                    return Poll::Ready(ToSwarm::CloseConnection { peer_id, connection });
                }
                _ => {}
            }
        }

        Poll::Pending
    }
}

/// Create a new P2PBehaviour with the given keypair
pub fn new(keypair: &libp2p_identity::Keypair) -> P2PBehaviour {
    // Get the peer ID directly from the keypair
    let local_peer_id = keypair.public().to_peer_id();
    
    // Note: In libp2p 0.51.x, identify now uses the keypair directly
    let identify = identify::Behaviour::new(identify::Config::new(
        "/ipfs/id/1.0.0".to_string(),
        keypair.public().clone()
    ).with_agent_version("browser-p2p/0.1.0"));
    
    // Initialize ping behaviour (removed with_keep_alive as it's deprecated)
    let ping = ping::Behaviour::new(ping::Config::new());
    
    // Initialize Kademlia if enabled
    #[cfg(feature = "kad")]
    let kademlia = {
        let store = MemoryStore::new(local_peer_id);
        Kademlia::new(local_peer_id, store)
    };
    
    // Create mDNS if enabled
    #[cfg(feature = "mdns")]
    let mdns = {
        Mdns::new(MdnsConfig::default())
            .expect("mDNS service creation failed")
    };
    
    Self {
        local_peer_id,
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
        // Return the stored peer ID
        self.local_peer_id
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

#[cfg(test)]
mod tests {
    use super::*;

    fn test_new() {
        let keypair = libp2p_identity::ed25519::Keypair::generate();
        let behaviour = P2PBehaviour::new(&keypair.into());
        assert_eq!(behaviour.local_peer_id(), keypair.public().to_peer_id());
    }
}
