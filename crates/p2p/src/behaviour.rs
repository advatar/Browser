//! Custom network behaviour combining Identify and Ping protocols.

use libp2p::{
    core::Multiaddr,
    identity::Keypair,
    PeerId,
    swarm::NetworkBehaviour,
};
use libp2p_identify as identify;
use libp2p_ping as ping;

/// Network events emitted by the P2P behaviour
#[derive(Debug)]
pub enum P2PEvent {
    Identify(identify::Event),
    Ping(ping::Event),
}

/// Combined network behaviour for P2P networking
#[derive(NetworkBehaviour)]
#[behaviour(to_swarm = "P2PEvent")]
pub struct P2PBehaviour {
    identify: identify::Behaviour,
    ping: ping::Behaviour,
}

impl P2PBehaviour {
    pub fn new(keypair: &Keypair) -> Self {
        let identify = identify::Behaviour::new(identify::Config::new(
            "/ipfs/id/1.0.0".to_string(),
            keypair.public(),
        ));
        let ping = ping::Behaviour::new(ping::Config::new());

        Self {
            identify,
            ping,
        }
    }

    pub fn local_peer_id(&self) -> PeerId {
        self.identify.local_peer_id()
    }
}

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
