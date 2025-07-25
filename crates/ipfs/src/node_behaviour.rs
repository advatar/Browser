use libp2p::{
    core::connection::ConnectionId,
    identify::{Identify, IdentifyEvent},
    kad::{Kademlia, KademliaEvent, QueryId, QueryResult, Record, RecordKey},
    mdns::{Mdns, MdnsEvent},
    ping::{Ping, PingEvent, PingSuccess},
    swarm::{
        ConnectionHandler, ConnectionHandlerUpgrErr, DialError, FromSwarm, NetworkBehaviour,
        NetworkBehaviourAction, NotifyHandler, PollParameters, ToSwarm,
    },
    Multiaddr, PeerId,
};
use std::collections::HashMap;
use std::task::{Context, Poll};

use crate::{
    bitswap::Bitswap,
    dht::DhtEvent,
    node::{NodeEvent, NodeEventSender},
};

/// Combined network behaviour for the IPFS node
pub struct NodeBehaviour {
    /// Kademlia DHT for peer and content routing
    pub kademlia: Kademlia,
    
    /// mDNS for local peer discovery
    pub mdns: Mdns,
    
    /// Identify protocol for peer information exchange
    pub identify: Identify,
    
    /// Ping protocol for latency measurement
    pub ping: Ping,
    
    /// Bitswap protocol for block exchange
    pub bitswap: Bitswap,
    
    /// Sender for node events
    event_sender: NodeEventSender,
    
    /// Active DHT queries
    active_queries: HashMap<QueryId, QueryInfo>,
}

/// Information about an active DHT query
struct QueryInfo {
    /// The peer that initiated the query
    peer_id: PeerId,
    /// The key being queried
    key: Vec<u8>,
    /// When the query was started
    started: std::time::Instant,
}

impl NodeBehaviour {
    /// Create a new NodeBehaviour
    pub fn new(local_peer_id: PeerId, keypair: &libp2p::identity::Keypair) -> Self {
        // Create a Kademlia DHT with an in-memory store
        let store = libp2p::kad::store::MemoryStore::new(local_peer_id);
        let kademlia = Kademlia::new(local_peer_id, store);
        
        // Create mDNS for local peer discovery
        let mdns = Mdns::new(Default::default())
            .expect("Failed to create mDNS service");
        
        // Create Identify service
        let identify = Identify::new(
            "/ipfs/0.1.0".to_string(),
            keypair.public().to_peer_id().to_string(),
        );
        
        // Create Ping service
        let ping = Ping::new(Ping::default().with_keep_alive(true));
        
        // Create Bitswap service
        let bitswap = Bitswap::new(Default::default());
        
        // Create event channel
        let (event_sender, _) = futures::channel::mpsc::channel(32);
        
        Self {
            kademlia,
            mdns,
            identify,
            ping,
            bitswap,
            event_sender,
            active_queries: HashMap::new(),
        }
    }
    
    /// Get the local peer ID
    pub fn local_peer_id(&self) -> PeerId {
        self.kademlia.local_peer_id().clone()
    }
    
    /// Bootstrap the DHT
    pub fn bootstrap(&mut self) -> Result<(), String> {
        self.kademlia.bootstrap()
    }
    
    /// Start providing a value in the DHT
    pub fn start_providing(&mut self, key: Vec<u8>) -> Result<QueryId, String> {
        let key = RecordKey::new(&key);
        self.kademlia.start_providing(key)
    }
    
    /// Get providers for a key from the DHT
    pub fn get_providers(&mut self, key: Vec<u8>) -> Result<QueryId, String> {
        let key = RecordKey::new(&key);
        self.kademlia.get_providers(key)
    }
    
    /// Put a record into the DHT
    pub fn put_record(
        &mut self,
        key: Vec<u8>,
        value: Vec<u8>,
        quorum: libp2p::kad::Quorum,
    ) -> Result<QueryId, String> {
        let key = RecordKey::new(&key);
        let record = Record {
            key,
            value,
            publisher: None,
            expires: None,
        };
        self.kademlia.put_record(record, quorum)
    }
    
    /// Get a record from the DHT
    pub fn get_record(&mut self, key: Vec<u8>) -> Result<QueryId, String> {
        let key = RecordKey::new(&key);
        self.kademlia.get_record(&key, libp2p::kad::Quorum::One)
    }
}

impl NetworkBehaviour for NodeBehaviour {
    type ConnectionHandler = libp2p::swarm::dummy::ConnectionHandler;
    type ToSwarm = NodeEvent;
    
    fn handle_established_inbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: PeerId,
        local_addr: &Multiaddr,
        remote_addr: &Multiaddr,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        // Forward to all behaviours that need to know about new connections
        self.kademlia.handle_established_inbound_connection(
            connection_id,
            peer,
            local_addr,
            remote_addr,
        )?;
        
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
        )
    }
    
    fn handle_established_outbound_connection(
        &mut self,
        connection_id: ConnectionId,
        peer: PeerId,
        addr: &Multiaddr,
        role_override: libp2p::core::Endpoint,
    ) -> Result<libp2p::swarm::THandler<Self>, ConnectionDenied> {
        // Forward to all behaviours that need to know about new connections
        self.kademlia.handle_established_outbound_connection(
            connection_id,
            peer,
            addr,
            role_override,
        )?;
        
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
        )
    }
    
    fn on_swarm_event(&mut self, event: FromSwarm<Self::ConnectionHandler>) {
        match event {
            FromSwarm::ConnectionEstablished(connection_established) => {
                self.kademlia.on_swarm_event(FromSwarm::ConnectionEstablished(
                    connection_established.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::ConnectionEstablished(
                    connection_established.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::ConnectionEstablished(
                    connection_established,
                ));
            }
            FromSwarm::ConnectionClosed(connection_closed) => {
                self.kademlia.on_swarm_event(FromSwarm::ConnectionClosed(
                    connection_closed.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::ConnectionClosed(
                    connection_closed.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::ConnectionClosed(connection_closed));
            }
            FromSwarm::AddressChange(address_change) => {
                self.kademlia.on_swarm_event(FromSwarm::AddressChange(
                    address_change.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::AddressChange(
                    address_change.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::AddressChange(address_change));
            }
            FromSwarm::DialFailure(dial_failure) => {
                self.kademlia.on_swarm_event(FromSwarm::DialFailure(
                    dial_failure.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::DialFailure(
                    dial_failure.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::DialFailure(dial_failure));
            }
            FromSwarm::ListenFailure(listen_failure) => {
                self.kademlia.on_swarm_event(FromSwarm::ListenFailure(
                    listen_failure.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::ListenFailure(
                    listen_failure.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::ListenFailure(listen_failure));
            }
            FromSwarm::NewListener(new_listener) => {
                self.kademlia.on_swarm_event(FromSwarm::NewListener(
                    new_listener.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::NewListener(
                    new_listener.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::NewListener(new_listener));
            }
            FromSwarm::NewListenAddr(new_listen_addr) => {
                self.kademlia.on_swarm_event(FromSwarm::NewListenAddr(
                    new_listen_addr.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::NewListenAddr(
                    new_listen_addr.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::NewListenAddr(new_listen_addr));
            }
            FromSwarm::ExpiredListenAddr(expired_listen_addr) => {
                self.kademlia.on_swarm_event(FromSwarm::ExpiredListenAddr(
                    expired_listen_addr.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::ExpiredListenAddr(
                    expired_listen_addr.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::ExpiredListenAddr(expired_listen_addr));
            }
            FromSwarm::ListenerError(listener_error) => {
                self.kademlia.on_swarm_event(FromSwarm::ListenerError(
                    listener_error.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::ListenerError(
                    listener_error.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::ListenerError(listener_error));
            }
            FromSwarm::ListenerClosed(listener_closed) => {
                self.kademlia.on_swarm_event(FromSwarm::ListenerClosed(
                    listener_closed.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::ListenerClosed(
                    listener_closed.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::ListenerClosed(listener_closed));
            }
            FromSwarm::NewExternalAddr(new_external_addr) => {
                self.kademlia.on_swarm_event(FromSwarm::NewExternalAddr(
                    new_external_addr.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::NewExternalAddr(
                    new_external_addr.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::NewExternalAddr(new_external_addr));
            }
            FromSwarm::ExpiredExternalAddr(expired_external_addr) => {
                self.kademlia.on_swarm_event(FromSwarm::ExpiredExternalAddr(
                    expired_external_addr.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::ExpiredExternalAddr(
                    expired_external_addr.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::ExpiredExternalAddr(expired_external_addr));
            }
            FromSwarm::NewExternalAddrCandidate(new_external_addr_candidate) => {
                self.kademlia.on_swarm_event(FromSwarm::NewExternalAddrCandidate(
                    new_external_addr_candidate.clone(),
                ));
                self.identify.on_swarm_event(FromSwarm::NewExternalAddrCandidate(
                    new_external_addr_candidate.clone(),
                ));
                self.ping.on_swarm_event(FromSwarm::NewExternalAddrCandidate(
                    new_external_addr_candidate,
                ));
            }
        }
    }
    
    fn on_connection_handler_event(
        &mut self,
        peer_id: PeerId,
        connection_id: ConnectionId,
        event: <Self::ConnectionHandler as ConnectionHandler>::ToBehaviour,
    ) {
        // Forward to all behaviours that handle connection events
        self.kademlia.on_connection_handler_event(
            peer_id,
            connection_id,
            event.clone(),
        );
        self.identify.on_connection_handler_event(
            peer_id,
            connection_id,
            event.clone(),
        );
        self.ping.on_connection_handler_event(peer_id, connection_id, event);
    }
    
    fn poll(
        &mut self,
        cx: &mut Context<'_>,
        params: &mut impl PollParameters,
    ) -> Poll<ToSwarm<Self::ToSwarm, libp2p::swarm::THandlerInEvent<Self>>> {
        // Poll Kademlia
        if let Poll::Ready(event) = self.kademlia.poll(cx, params) {
            match event {
                ToSwarm::GenerateEvent(event) => match event {
                    KademliaEvent::QueryResult { id, result, .. } => {
                        if let Some(query_info) = self.active_queries.remove(&id) {
                            match result {
                                QueryResult::Bootstrap(Ok(ok)) => {
                                    return Poll::Ready(ToSwarm::GenerateEvent(
                                        NodeEvent::DhtEvent(DhtEvent::Bootstrapped { peer_id: ok.peer_id }),
                                    ));
                                }
                                QueryResult::GetProviders(Ok(providers)) => {
                                    return Poll::Ready(ToSwarm::GenerateEvent(
                                        NodeEvent::DhtEvent(DhtEvent::ProvidersFound {
                                            key: query_info.key,
                                            providers: providers.providers,
                                        }),
                                    ));
                                }
                                QueryResult::GetRecord(Ok(record)) => {
                                    return Poll::Ready(ToSwarm::GenerateEvent(
                                        NodeEvent::DhtEvent(DhtEvent::ValueFound {
                                            key: record.record.key.into_vec(),
                                            value: record.record.value,
                                        }),
                                    ));
                                }
                                QueryResult::StartProviding(Ok(key)) => {
                                    return Poll::Ready(ToSwarm::GenerateEvent(
                                        NodeEvent::DhtEvent(DhtEvent::Providing {
                                            key: key.into_vec(),
                                        }),
                                    ));
                                }
                                QueryResult::PutRecord(Ok(key)) => {
                                    return Poll::Ready(ToSwarm::GenerateEvent(
                                        NodeEvent::DhtEvent(DhtEvent::ValueStored {
                                            key: key.into_vec(),
                                        }),
                                    ));
                                }
                                _ => {}
                            }
                        }
                    }
                    _ => {}
                },
                _ => return Poll::Ready(event.map_out(|e| NodeEvent::DhtEvent(e.into()))),
            }
        }
        
        // Poll mDNS
        if let Poll::Ready(event) = self.mdns.poll(cx, params) {
            match event {
                ToSwarm::GenerateEvent(event) => match event {
                    MdnsEvent::Discovered(discovered) => {
                        for (peer_id, addr) in discovered {
                            self.kademlia.add_address(&peer_id, addr);
                        }
                    }
                    MdnsEvent::Expired(expired) => {
                        for (peer_id, addr) in expired {
                            self.kademlia.remove_address(&peer_id, &addr);
                        }
                    }
                },
                _ => return Poll::Ready(event.map_out(NodeEvent::MdnsEvent)),
            }
        }
        
        // Poll Identify
        if let Poll::Ready(event) = self.identify.poll(cx, params) {
            match event {
                ToSwarm::GenerateEvent(event) => match event {
                    IdentifyEvent::Received { peer_id, info } => {
                        // Add discovered addresses to Kademlia
                        for addr in info.listen_addrs {
                            self.kademlia.add_address(&peer_id, addr);
                        }
                        return Poll::Ready(ToSwarm::GenerateEvent(NodeEvent::PeerIdentified {
                            peer_id,
                            info,
                        }));
                    }
                    _ => {}
                },
                _ => return Poll::Ready(event.map_out(NodeEvent::IdentifyEvent)),
            }
        }
        
        // Poll Ping
        if let Poll::Ready(event) = self.ping.poll(cx, params) {
            match event {
                ToSwarm::GenerateEvent(event) => match event {
                    PingEvent { peer, result: Ok(PingSuccess::Ping { rtt }) } => {
                        return Poll::Ready(ToSwarm::GenerateEvent(NodeEvent::PingSuccess {
                            peer,
                            rtt,
                        }));
                    }
                    PingEvent { peer, result: Err(e) } => {
                        return Poll::Ready(ToSwarm::GenerateEvent(NodeEvent::PingFailure {
                            peer,
                            error: e.to_string(),
                        }));
                    }
                },
                _ => return Poll::Ready(event.map_out(|e| NodeEvent::PingEvent(e.into()))),
            }
        }
        
        // Poll Bitswap
        if let Poll::Ready(event) = self.bitswap.poll(cx, params) {
            return Poll::Ready(event.map_out(NodeEvent::BitswapEvent));
        }
        
        Poll::Pending
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use libp2p::identity::Keypair;
    
    #[test]
    fn test_node_behaviour_creation() {
        let local_key = Keypair::generate_ed25519();
        let local_peer_id = local_key.public().to_peer_id();
        
        let behaviour = NodeBehaviour::new(local_peer_id, &local_key);
        
        assert_eq!(behaviour.local_peer_id(), local_peer_id);
    }
    
    #[test]
    fn test_dht_operations() {
        let local_key = Keypair::generate_ed25519();
        let local_peer_id = local_key.public().to_peer_id();
        
        let mut behaviour = NodeBehaviour::new(local_peer_id, &local_key);
        
        // Test bootstrap
        assert!(behaviour.bootstrap().is_ok());
        
        // Test providing a key
        let key = b"test_key".to_vec();
        assert!(behaviour.start_providing(key.clone()).is_ok());
        
        // Test getting providers
        assert!(behaviour.get_providers(key).is_ok());
    }
}
