//! Configuration for the IPFS node.

use libp2p::Multiaddr;
use std::path::PathBuf;

/// Configuration for the IPFS node.
#[derive(Debug, Clone)]
pub struct Config {
    /// Path to the IPFS repository
    pub repo_path: PathBuf,
    /// Listening addresses
    pub listen_on: Vec<Multiaddr>,
    /// Bootstrap nodes
    pub bootstrap_nodes: Vec<Multiaddr>,
    /// Enable DHT server
    pub dht_server: bool,
    /// Enable mDNS for local discovery
    pub mdns: bool,
    /// Enable metrics collection
    pub metrics: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            repo_path: dirs::home_dir()
                .unwrap_or_else(|| PathBuf::from("."))
                .join(".ipfs"),
            listen_on: vec![
                "/ip4/0.0.0.0/tcp/0".parse().unwrap(),
                "/ip6/::/tcp/0".parse().unwrap(),
            ],
            bootstrap_nodes: vec![
                "/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN".parse().unwrap(),
            ],
            dht_server: true,
            mdns: true,
            metrics: false,
        }
    }
}

impl Config {
    /// Create a new config with the given repo path
    pub fn new(repo_path: impl Into<PathBuf>) -> Self {
        let mut config = Self::default();
        config.repo_path = repo_path.into();
        config
    }
    
    /// Set the listening addresses
    pub fn listen_on(mut self, addrs: Vec<Multiaddr>) -> Self {
        self.listen_on = addrs;
        self
    }
    
    /// Set the bootstrap nodes
    pub fn bootstrap_nodes(mut self, nodes: Vec<Multiaddr>) -> Self {
        self.bootstrap_nodes = nodes;
        self
    }
    
    /// Enable/disable DHT server
    pub fn dht_server(mut self, enabled: bool) -> Self {
        self.dht_server = enabled;
        self
    }
    
    /// Enable/disable mDNS
    pub fn mdns(mut self, enabled: bool) -> Self {
        self.mdns = enabled;
        self
    }
    
    /// Enable/disable metrics
    pub fn metrics(mut self, enabled: bool) -> Self {
        self.metrics = enabled;
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_config_defaults() {
        let config = Config::default();
        assert!(!config.listen_on.is_empty());
        assert!(!config.bootstrap_nodes.is_empty());
        assert!(config.dht_server);
        assert!(config.mdns);
        assert!(!config.metrics);
    }
}
