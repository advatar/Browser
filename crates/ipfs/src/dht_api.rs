use anyhow::Result;
use cid::Cid;
use libp2p::{kad::RecordKey, PeerId};
use std::time::Duration;

use crate::{
    dht::{DhtEvent, DhtService},
    node::NodeEvent,
    Block, BlockStore,
};

/// DHT API for the IPFS node
#[async_trait::async_trait]
pub trait DhtApi {
    /// Get a value from the DHT
    async fn get_value(&mut self, key: Vec<u8>) -> Result<Option<Vec<u8>>>;

    /// Put a value into the DHT
    async fn put_value(&mut self, key: Vec<u8>, value: Vec<u8>) -> Result<()>;

    /// Provide a block to the DHT
    async fn provide_block(&mut self, cid: Cid) -> Result<()>;

    /// Find providers for a block in the DHT
    async fn find_providers(&mut self, cid: Cid) -> Result<Vec<PeerId>>;

    /// Find the closest peers to a given key
    async fn find_peer(&mut self, peer_id: PeerId) -> Result<Vec<PeerId>>;

    /// Bootstrap the DHT
    async fn bootstrap(&mut self) -> Result<()>;

    /// Handle DHT events
    fn handle_dht_event(&mut self, event: DhtEvent) -> Result<Option<NodeEvent>>;
}

#[async_trait::async_trait]
impl DhtApi for super::Node {
    async fn get_value(&mut self, key: Vec<u8>) -> Result<Option<Vec<u8>>>> {
        let (sender, mut receiver) = tokio::sync::oneshot::channel();
        
        if let Some(dht) = &mut self.dht {
            let query_id = dht.get_value(key.clone());
            
            // Store the sender to be used when the query completes
            self.pending_dht_queries.insert(query_id, (key, sender));
            
            // Wait for the result with a timeout
            match tokio::time::timeout(Duration::from_secs(30), receiver).await {
                Ok(Ok(Some(value))) => Ok(Some(value)),
                Ok(Ok(None)) => Ok(None),
                Ok(Err(e)) => Err(e),
                Err(_) => Err(anyhow::anyhow!("DHT query timed out")),
            }
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }

    async fn put_value(&mut self, key: Vec<u8>, value: Vec<u8>) -> Result<()> {
        if let Some(dht) = &mut self.dht {
            let query_id = dht.put_value(key, value);
            
            // Store a oneshot sender to be notified when the put completes
            let (sender, receiver) = tokio::sync::oneshot::channel();
            self.pending_dht_queries.insert(query_id, (vec![], sender));
            
            // Wait for the put to complete with a timeout
            match tokio::time::timeout(Duration::from_secs(30), receiver).await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(e)) => Err(e),
                Err(_) => Err(anyhow::anyhow!("DHT put operation timed out")),
            }
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }

    async fn provide_block(&mut self, cid: Cid) -> Result<()> {
        if let Some(dht) = &mut self.dht {
            let key = cid.to_bytes();
            let query_id = dht.start_providing(key);
            
            // Store a oneshot sender to be notified when the provide completes
            let (sender, receiver) = tokio::sync::oneshot::channel();
            self.pending_dht_queries.insert(query_id, (vec![], sender));
            
            // Wait for the provide to complete with a timeout
            match tokio::time::timeout(Duration::from_secs(30), receiver).await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(e)) => Err(e),
                Err(_) => Err(anyhow::anyhow!("DHT provide operation timed out")),
            }
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }

    async fn find_providers(&mut self, cid: Cid) -> Result<Vec<PeerId>> {
        let (sender, receiver) = tokio::sync::oneshot::channel();
        
        if let Some(dht) = &mut self.dht {
            let key = cid.to_bytes();
            let query_id = dht.get_providers(key.clone());
            
            // Store the sender to be used when the query completes
            self.pending_dht_queries.insert(query_id, (key, sender));
            
            // Wait for the result with a timeout
            match tokio::time::timeout(Duration::from_secs(30), receiver).await {
                Ok(Ok(providers)) => Ok(providers),
                Ok(Err(e)) => Err(e),
                Err(_) => Err(anyhow::anyhow!("DHT find providers query timed out")),
            }
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }

    async fn find_peer(&mut self, peer_id: PeerId) -> Result<Vec<PeerId>> {
        let (sender, receiver) = tokio::sync::oneshot::channel();
        
        if let Some(dht) = &mut self.dht {
            let key = peer_id.to_bytes();
            let query_id = dht.get_closest_peers(peer_id);
            
            // Store the sender to be used when the query completes
            self.pending_dht_queries.insert(query_id, (key, sender));
            
            // Wait for the result with a timeout
            match tokio::time::timeout(Duration::from_secs(30), receiver).await {
                Ok(Ok(peers)) => Ok(peers),
                Ok(Err(e)) => Err(e),
                Err(_) => Err(anyhow::anyhow!("DHT find peer query timed out")),
            }
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }

    async fn bootstrap(&mut self) -> Result<()> {
        if let Some(dht) = &mut self.dht {
            dht.bootstrap()
        } else {
            Err(anyhow::anyhow!("DHT is not enabled"))
        }
    }

    fn handle_dht_event(&mut self, event: DhtEvent) -> Result<Option<NodeEvent>> {
        match event {
            DhtEvent::ValueFound { key, value } => {
                // Check if we have a pending query for this key
                if let Some((_, sender)) = self.pending_dht_queries.remove(&key) {
                    let _ = sender.send(Ok(Some(value)));
                }
                Ok(None)
            }
            DhtEvent::ValueNotFound { key } => {
                // Check if we have a pending query for this key
                if let Some((_, sender)) = self.pending_dht_queries.remove(&key) {
                    let _ = sender.send(Ok(None));
                }
                Ok(None)
            }
            DhtEvent::ValueStored { key } => {
                // Check if we have a pending query for this key
                if let Some((_, sender)) = self.pending_dht_queries.remove(&key) {
                    let _ = sender.send(Ok(()));
                }
                Ok(None)
            }
            DhtEvent::ProvidersFound { key, providers } => {
                // Check if we have a pending query for this key
                if let Some((_, sender)) = self.pending_dht_queries.remove(&key) {
                    let _ = sender.send(Ok(providers));
                }
                Ok(None)
            }
            DhtEvent::Bootstrapped { peer_id } => {
                log::info!("DHT bootstrapped with peer: {}", peer_id);
                Ok(Some(NodeEvent::DhtBootstrapped { peer_id }))
            }
            DhtEvent::PeersFound { key, peers } => {
                // Check if we have a pending query for this key
                if let Some((_, sender)) = self.pending_dht_queries.remove(&key) {
                    let _ = sender.send(Ok(peers));
                }
                Ok(None)
            }
            DhtEvent::Error { error } => {
                log::error!("DHT error: {}", error);
                Ok(Some(NodeEvent::DhtError { error }))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use libp2p::identity::Keypair;
    use std::time::Duration;

    #[tokio::test]
    async fn test_dht_operations() -> Result<()> {
        // Create a test node
        let keypair = Keypair::generate_ed25519();
        let peer_id = keypair.public().to_peer_id();
        let registry = prometheus::Registry::new();
        let metrics = DhtMetrics::new(&registry)?;
        let config = DhtConfig::default();
        
        let mut dht = DhtService::new(peer_id, config, metrics)?;
        
        // Test putting and getting a value
        let key = b"test_key".to_vec();
        let value = b"test_value".to_vec();
        
        // Put a value
        dht.put_value(key.clone(), value.clone());
        
        // Process events until we get a response or timeout
        let mut got_value = None;
        let start = std::time::Instant::now();
        
        while start.elapsed() < Duration::from_secs(5) {
            if let Some(event) = dht.next_event().await {
                if let DhtEvent::ValueStored { .. } = event {
                    // Value was stored, now try to get it
                    dht.get_value(key.clone());
                } else if let DhtEvent::ValueFound { value: found_value, .. } = event {
                    got_value = Some(found_value);
                    break;
                }
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        
        assert_eq!(got_value, Some(value));
        
        Ok(())
    }
}
