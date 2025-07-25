use anyhow::Result;
use libp2p::{
    kad::{
        self, Kademlia, KademliaConfig, KademliaEvent, QueryId, QueryResult,
        record::Key as RecordKey, Record, GetRecordOk, PutRecordOk, Quorum,
    },
    Multiaddr, PeerId,
};
use prometheus::{IntCounter, IntGauge};
use std::time::Duration;

/// Configuration for the DHT service
#[derive(Clone, Debug)]
pub struct DhtConfig {
    /// Whether the DHT is enabled
    pub enabled: bool,
    /// Protocol name for the DHT
    pub protocol_name: String,
    /// Bootstrap nodes to connect to
    pub bootstrap_nodes: Vec<Multiaddr>,
    /// Whether to run in server mode
    pub server_mode: bool,
    /// Whether to run in client mode
    pub client_mode: bool,
    /// Record TTL in seconds
    pub record_ttl: u64,
    /// Time between DHT crawls in seconds
    pub crawl_interval: u64,
}

impl Default for DhtConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            protocol_name: "/ipfs/kad/1.0.0".to_string(),
            bootstrap_nodes: vec![],
            server_mode: true,
            client_mode: true,
            record_ttl: 36 * 60 * 60, // 36 hours
            crawl_interval: 300,       // 5 minutes
        }
    }
}

/// Metrics for the DHT service
#[derive(Clone)]
pub struct DhtMetrics {
    /// Number of known peers in the DHT
    pub peers: IntGauge,
    /// Number of records in the DHT
    pub records: IntGauge,
    /// Number of successful DHT operations
    pub operations: IntCounter,
    /// Number of failed DHT operations
    pub errors: IntCounter,
}

impl DhtMetrics {
    /// Create new DHT metrics
    pub fn new(registry: &Registry) -> Result<Self> {
        let metrics = Self {
            peers: register_int_gauge!(
                "ipfs_dht_peers",
                "Number of known peers in the DHT"
            )?,
            records: register_int_gauge!(
                "ipfs_dht_records",
                "Number of records in the DHT"
            )?,
            operations: register_int_counter!(
                "ipfs_dht_operations_total",
                "Total number of DHT operations"
            )?,
            errors: register_int_counter!(
                "ipfs_dht_errors_total",
                "Total number of DHT errors"
            )?,
        };

        Ok(metrics)
    }
}

/// DHT service implementation
pub struct DhtService {
    /// The underlying Kademlia DHT
    pub kademlia: Kademlia<kad::store::MemoryStore>,
    /// DHT configuration
    pub config: DhtConfig,
    /// Metrics
    pub metrics: DhtMetrics,
    /// Active queries
    active_queries: std::collections::HashMap<QueryId, QueryInfo>,
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

impl DhtService {
    /// Create a new DHT service
    pub fn new(
        local_peer_id: PeerId,
        config: DhtConfig,
        metrics: DhtMetrics,
    ) -> Result<Self> {
        // Create a new Kademlia DHT with an in-memory store
        let store = kad::store::MemoryStore::new(local_peer_id);
        let mut kademlia = Kademlia::with_config(
            local_peer_id,
            store,
            KademliaConfig::default(),
        );

        // Set the protocol name
        kademlia.set_protocol_name(config.protocol_name.as_bytes());

        // Set the mode based on config
        kademlia.set_mode(Some(kad::Mode::Server));

        Ok(Self {
            kademlia,
            config,
            metrics,
            active_queries: Default::default(),
        })
    }

    /// Bootstrap the DHT by connecting to bootstrap nodes
    pub fn bootstrap(&mut self) -> Result<()> {
        for addr in &self.config.bootstrap_nodes {
            if let Ok((peer_id, multiaddr)) = addr.clone().try_into() {
                self.kademlia.add_address(&peer_id, multiaddr);
            }
        }

        self.kademlia.bootstrap()?;
        Ok(())
    }

    /// Put a value into the DHT
    pub fn put_value(&mut self, key: Vec<u8>, value: Vec<u8>) -> QueryId {
        let key = RecordKey::new(&key);
        let record = Record {
            key,
            value,
            publisher: None,
            expires: None,
        };

        self.kademlia.put_record(record, Quorum::One)
    }

    /// Get a value from the DHT
    pub fn get_value(&mut self, key: Vec<u8>) -> QueryId {
        let key = RecordKey::new(&key);
        self.kademlia.get_record(&key, Quorum::One)
    }

    /// Provide a value in the DHT
    pub fn start_providing(&mut self, key: Vec<u8>) -> QueryId {
        let key = RecordKey::new(&key);
        self.kademlia.start_providing(key)
    }

    /// Find providers for a key
    pub fn get_providers(&mut self, key: Vec<u8>) -> QueryId {
        let key = RecordKey::new(&key);
        self.kademlia.get_providers(key)
    }

    /// Handle DHT events
    pub fn handle_event(&mut self, event: KademliaEvent) -> Option<DhtEvent> {
        match event {
            KademliaEvent::OutboundQueryProgressed { id, result, .. } => {
                if let Some(query_info) = self.active_queries.remove(&id) {
                    match result {
                        QueryResult::Bootstrap(Ok(ok)) => {
                            self.metrics.operations.inc();
                            Some(DhtEvent::Bootstrapped { peer_id: ok.peer_id })
                        }
                        QueryResult::GetRecord(Ok(GetRecordOk::FoundRecord(record))) => {
                            self.metrics.operations.inc();
                            Some(DhtEvent::ValueFound {
                                key: record.key.into_vec(),
                                value: record.record.value,
                            })
                        }
                        QueryResult::GetRecord(Ok(GetRecordOk::FinishedWithNoAdditionalRecord { .. })) => {
                            self.metrics.operations.inc();
                            Some(DhtEvent::ValueNotFound {
                                key: query_info.key,
                            })
                        }
                        QueryResult::PutRecord(Ok(PutRecordOk { key })) => {
                            self.metrics.operations.inc();
                            Some(DhtEvent::ValueStored { key: key.into_vec() })
                        }
                        QueryResult::StartProviding(Ok(key)) => {
                            self.metrics.operations.inc();
                            Some(DhtEvent::Providing { key: key.into_vec() })
                        }
                        QueryResult::GetProviders(Ok(providers)) => {
                            self.metrics.operations.inc();
                            Some(DhtEvent::ProvidersFound {
                                key: query_info.key,
                                providers: providers.providers,
                            })
                        }
                        _ => {
                            self.metrics.errors.inc();
                            Some(DhtEvent::Error {
                                error: format!("Unexpected query result: {:?}", result),
                            })
                        }
                    }
                } else {
                    self.metrics.errors.inc();
                    Some(DhtEvent::Error {
                        error: format!("Unknown query ID: {:?}", id),
                    })
                }
            }
            _ => None,
        }
    }
}

/// Events emitted by the DHT service
#[derive(Debug)]
pub enum DhtEvent {
    /// The DHT has been bootstrapped
    Bootstrapped { peer_id: PeerId },
    /// A value was found in the DHT
    ValueFound { key: Vec<u8>, value: Vec<u8> },
    /// A value was not found in the DHT
    ValueNotFound { key: Vec<u8> },
    /// A value was successfully stored in the DHT
    ValueStored { key: Vec<u8> },
    /// A provider was found for a key
    ProvidersFound { key: Vec<u8>, providers: Vec<PeerId> },
    /// A key is now being provided by this node
    Providing { key: Vec<u8> },
    /// An error occurred
    Error { error: String },
}

#[cfg(test)]
mod tests {
    use super::*;
    use libp2p::identity::Keypair;
    use prometheus::Registry;

    #[test]
    fn test_dht_service_creation() {
        let local_key = Keypair::generate_ed25519();
        let local_peer_id = PeerId::from(local_key.public());
        let registry = Registry::new();
        let metrics = DhtMetrics::new(&registry).unwrap();
        let config = DhtConfig::default();
        
        let dht = DhtService::new(local_peer_id, config, metrics);
        assert!(dht.is_ok());
    }

    #[test]
    fn test_dht_metrics() {
        let registry = Registry::new();
        let metrics = DhtMetrics::new(&registry).unwrap();
        
        metrics.peers.inc();
        metrics.records.set(42);
        metrics.operations.inc();
        metrics.errors.inc();
        
        // Verify metrics were updated
        assert_eq!(metrics.peers.get(), 1.0);
        assert_eq!(metrics.records.get(), 42.0);
        assert_eq!(metrics.operations.get(), 1.0);
        assert_eq!(metrics.errors.get(), 1.0);
    }
}
