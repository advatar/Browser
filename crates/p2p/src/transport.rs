use futures::future::Ready;
use futures::future;
use libp2p_core::{PeerId, Transport};
use libp2p_core::muxing::StreamMuxerBox;
use libp2p_core::transport::{DialOpts, ListenerId, TransportError, TransportEvent};
use std::io::{Error as IoError, ErrorKind};
use std::pin::Pin;
use std::task::{Context as TaskContext, Poll};

/// Creates a dummy transport that always returns an error
/// This is a temporary workaround for dependency conflicts
pub fn dummy_transport() -> libp2p_core::transport::Boxed<(PeerId, StreamMuxerBox)> {
    // Create a dummy transport that always returns an error
    // This is a temporary solution until we can resolve the dependency conflicts
    let transport = DummyTransport {};
    
    // Box the transport to ensure type compatibility
    transport.boxed()
}

/// A dummy transport implementation that always fails
/// Used as a workaround for dependency conflicts
#[derive(Debug)]
struct DummyTransport {}

impl Transport for DummyTransport {
    type Output = (PeerId, StreamMuxerBox);
    type Error = IoError;  // Use std::io::Error instead of anyhow::Error
    type ListenerUpgrade = Ready<Result<Self::Output, Self::Error>>;
    type Dial = Ready<Result<Self::Output, Self::Error>>;
    
    fn listen_on(&mut self, _id: ListenerId, _addr: libp2p_core::Multiaddr) -> Result<(), TransportError<Self::Error>> {
        Err(TransportError::Other(IoError::new(ErrorKind::Other, "Dummy transport does not support listening")))
    }
    
    fn remove_listener(&mut self, _id: ListenerId) -> bool {
        false
    }
    
    fn dial(&mut self, _addr: libp2p_core::Multiaddr, _opts: DialOpts) -> Result<Self::Dial, TransportError<Self::Error>> {
        Ok(future::ready(Err(IoError::new(ErrorKind::Other, "Dummy transport does not support dialing"))))
    }
    
    // dial_as_listener method removed as it's not part of the Transport trait in this version
    
    // address_translation method removed as it's not part of the Transport trait in this version
    
    fn poll(self: Pin<&mut Self>, _cx: &mut TaskContext<'_>) -> Poll<TransportEvent<Self::ListenerUpgrade, Self::Error>> {
        Poll::Pending
    }
}

/// Create a boxed dummy transport
/// Returns a properly boxed transport for Swarm construction
pub fn create_dummy_transport() -> libp2p_core::transport::Boxed<(PeerId, StreamMuxerBox)> {
    // Create and box a new dummy transport to provide a valid Swarm implementation
    dummy_transport().boxed()
}

pub fn boxed_dummy_transport() -> libp2p_core::transport::Boxed<(PeerId, StreamMuxerBox)> {
    // Return the boxed dummy transport
    dummy_transport()
}
