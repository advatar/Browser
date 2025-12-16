//! Error types for the IPFS node.

use std::fmt;

/// A specialized `Result` type for IPFS operations.
pub type Result<T> = std::result::Result<T, Error>;

/// The error type for IPFS operations.
#[derive(Debug)]
pub enum Error {
    /// I/O error
    Io(std::io::Error),
    /// CID error
    Cid(cid::Error),
    /// Multiaddress error
    Multiaddr(libp2p::multiaddr::Error),
    /// Peer ID error
    PeerId(libp2p::identity::DecodingError),
    /// Libp2p error
    Libp2p(libp2p::core::transport::TransportError<std::io::Error>),
    /// Channel error
    ChannelClosed,
    /// Other error
    Other(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(e) => write!(f, "I/O error: {}", e),
            Error::Cid(e) => write!(f, "CID error: {}", e),
            Error::Multiaddr(e) => write!(f, "Multiaddress error: {}", e),
            Error::PeerId(e) => write!(f, "Peer ID error: {}", e),
            Error::Libp2p(e) => write!(f, "Libp2p error: {}", e),
            Error::ChannelClosed => write!(f, "Channel closed"),
            Error::Other(msg) => write!(f, "{}", msg),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Error::Io(e) => Some(e),
            Error::Cid(e) => Some(e),
            Error::Multiaddr(e) => Some(e),
            Error::PeerId(e) => Some(e),
            Error::Libp2p(e) => Some(e),
            _ => None,
        }
    }
}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e)
    }
}

impl From<cid::Error> for Error {
    fn from(e: cid::Error) -> Self {
        Error::Cid(e)
    }
}

impl From<libp2p::multiaddr::Error> for Error {
    fn from(e: libp2p::multiaddr::Error) -> Self {
        Error::Multiaddr(e)
    }
}

impl From<libp2p::identity::DecodingError> for Error {
    fn from(e: libp2p::identity::DecodingError) -> Self {
        Error::PeerId(e)
    }
}

impl From<libp2p::core::transport::TransportError<std::io::Error>> for Error {
    fn from(e: libp2p::core::transport::TransportError<std::io::Error>) -> Self {
        Error::Libp2p(e)
    }
}

impl From<futures::channel::mpsc::SendError> for Error {
    fn from(_: futures::channel::mpsc::SendError) -> Self {
        Error::ChannelClosed
    }
}

impl From<futures::channel::oneshot::Canceled> for Error {
    fn from(_: futures::channel::oneshot::Canceled) -> Self {
        Error::ChannelClosed
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display() {
        let io_error = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let error = Error::Io(io_error);
        assert!(error.to_string().contains("I/O error"));

        // Produce a cid::Error by attempting to parse an invalid CID
        let cid_error = cid::Cid::try_from(&b""[..]).unwrap_err();
        let error = Error::Cid(cid_error);
        assert!(error.to_string().contains("CID error"));

        let error = Error::ChannelClosed;
        assert_eq!(error.to_string(), "Channel closed");

        let error = Error::Other("custom error".to_string());
        assert_eq!(error.to_string(), "custom error");
    }
}
