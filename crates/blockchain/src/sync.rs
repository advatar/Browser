use anyhow::{anyhow, Result};
use futures::StreamExt;
use sp_runtime::{
    generic::Block,
    traits::{Block as BlockT, Header as HeaderT, NumberFor},
    Justifications,
};
use std::{
    collections::HashMap,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::time::{interval, Interval};
use subxt::{
    OnlineClient, PolkadotConfig,
};

/// Configuration for chain synchronization
#[derive(Debug, Clone)]
pub struct SyncConfig {
    /// Whether to download full block bodies (true) or just headers (false)
    pub download_bodies: bool,
    /// Maximum number of concurrent download requests
    pub max_concurrent_requests: usize,
    /// Maximum number of blocks to request in a single batch
    pub max_blocks_per_request: u32,
    /// Timeout for block requests in seconds
    pub request_timeout_secs: u64,
    /// Maximum number of blocks to keep in memory
    pub max_blocks_in_memory: usize,
}

impl Default for SyncConfig {
    fn default() -> Self {
        Self {
            download_bodies: true,
            max_concurrent_requests: 10,
            max_blocks_per_request: 128,
            request_timeout_secs: 30,
            max_blocks_in_memory: 1000,
        }
    }
}

/// A block with its header and optional body
#[derive(Debug, Clone)]
pub struct BlockData<B: BlockT> {
    /// Block header
    pub header: B::Header,
    /// Block body (transactions)
    pub body: Option<Vec<B::Extrinsic>>,
    /// Block justifications
    pub justifications: Option<Justifications>,
    /// Block hash
    pub hash: B::Hash,
    /// Block number
    pub number: NumberFor<B>,
}

/// Chain synchronization status
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncStatus<B: BlockT> {
    /// Synchronization is in progress
    Syncing {
        /// Current block being processed
        current: NumberFor<B>,
        /// Highest known block
        highest: NumberFor<B>,
    },
    /// Synchronization is complete
    Synced {
        /// The current best block
        best: NumberFor<B>,
    },
    /// Synchronization is stopped due to an error
    Error(String),
}

/// A chain synchronizer that keeps track of the blockchain state
pub struct ChainSync<B> 
where
    B: BlockT,
{
    /// The Substrate client
    client: Arc<OnlineClient<PolkadotConfig>>,
    /// Synchronization configuration
    config: SyncConfig,
    /// Current synchronization status
    status: SyncStatus<B>,
    /// Blocks that have been downloaded but not yet processed
    queued_blocks: HashMap<NumberFor<B>, BlockData<B>>,
    /// The highest block number we've seen
    highest_seen: Option<NumberFor<B>>,
    /// The best block number we've fully processed
    best_processed: Option<NumberFor<B>>,
    /// Block subscription handle
    block_subscription: Option<tokio::task::JoinHandle<()>>,
}

impl<B> ChainSync<B>
where
    B: BlockT,
{
    /// Create a new chain synchronizer
    pub async fn new(client: Arc<OnlineClient<PolkadotConfig>>, config: SyncConfig) -> Result<Self> {
        Ok(Self {
            client,
            config,
            status: SyncStatus::Syncing {
                current: 0u32.into(),
                highest: 0u32.into(),
            },
            queued_blocks: HashMap::new(),
            highest_seen: None,
            best_processed: None,
            block_subscription: None,
        })
    }

    /// Start the synchronization process
    pub async fn start(&mut self) -> Result<()> {
        log::info!("Starting chain synchronization");
        
        // Get the current best block
        let best_block = self.client.blocks().at_latest().await?;
        let best_number = best_block.number();
        
        log::info!("Current best block: #{}", best_number);
        
        // Update status
        self.highest_seen = Some(best_number);
        self.best_processed = Some(best_number);
        
        self.status = SyncStatus::Synced {
            best: best_number,
        };
        
        // Start the sync loop in a background task
        let client = self.client.clone();
        let sync_handle = tokio::spawn(async move {
            Self::background_sync_loop(client).await
        });
        
        self.block_subscription = Some(sync_handle);
        
        Ok(())
    }
    
    /// Get the current synchronization status
    pub fn status(&self) -> &SyncStatus<B> {
        &self.status
    }
    
    /// Get a block by number
    pub async fn get_block(&self, number: NumberFor<B>) -> Result<Option<BlockData<B>>> {
        // First check if we have it in our queue
        if let Some(block_data) = self.queued_blocks.get(&number) {
            return Ok(Some(block_data.clone()));
        }
        
        // Try to get it from the client
        match self.client.blocks().at_latest().await {
            Ok(block) if block.number() >= number => {
                let target_block = self.client.blocks().at_latest().await?;
                if target_block.number() == number {
                    let header = target_block.header().clone();
                    let hash = target_block.hash();
                    
                    // Get block body if configured
                    let body = if self.config.download_bodies {
                        let extrinsics: Result<Vec<_>, _> = target_block.extrinsics().await?.collect();
                        Some(extrinsics?)
                    } else {
                        None
                    };
                    
                    Ok(Some(BlockData {
                        header,
                        body,
                        justifications: None, // TODO: Get justifications from runtime
                        hash,
                        number,
                    }))
                } else {
                    Ok(None)
                }
            }
            _ => Ok(None),
        }
    }
    
    /// Background synchronization loop
    async fn background_sync_loop(client: Arc<OnlineClient<PolkadotConfig>>) -> Result<()> {
        log::info!("Starting background chain synchronization loop");
        
        // Create interval for periodic sync (every 30 seconds)
        let mut sync_interval = interval(Duration::from_secs(30));
        
        loop {
            tokio::select! {
                // Periodic sync
                _ = sync_interval.tick() => {
                    if let Err(e) = Self::perform_sync_check(&client).await {
                        log::error!("Error during periodic sync: {}", e);
                    }
                }
                
                // Handle shutdown signal
                _ = tokio::signal::ctrl_c() => {
                    log::info!("Shutting down chain synchronization");
                    break;
                }
            }
        }
        
        Ok(())
    }
    
    /// Perform a sync check to get the latest block information
    async fn perform_sync_check(client: &OnlineClient<PolkadotConfig>) -> Result<()> {
        let latest_block = client.blocks().at_latest().await?;
        let block_number = latest_block.number();
        let block_hash = latest_block.hash();
        
        log::debug!("Latest block: #{} ({})", block_number, block_hash);
        
        // Get block events if available
        if let Ok(events) = latest_block.events().await {
            let event_count = events.iter().count();
            log::trace!("Block #{} contains {} events", block_number, event_count);
        }
        
        Ok(())
    }
    

}

#[cfg(test)]
mod tests {
    use super::*;
    use sp_core::H256;
    use sp_runtime::{
        testing::{Block as TestBlock, Header as TestHeader},
        traits::{BlakeTwo256, IdentityLookup},
    };
    
    type TestRuntime = ();
    
    #[tokio::test]
    async fn test_chain_sync_initialization() {
        // Test sync configuration creation
        let config = SyncConfig::default();
        assert!(config.download_bodies);
        assert_eq!(config.max_concurrent_requests, 10);
        assert_eq!(config.max_blocks_per_request, 128);
        assert_eq!(config.request_timeout_secs, 30);
        assert_eq!(config.max_blocks_in_memory, 1000);
    }
    
    #[tokio::test]
    async fn test_sync_status() {
        // Test sync status variants
        let syncing_status: SyncStatus<TestBlock> = SyncStatus::Syncing {
            current: 100u32.into(),
            highest: 200u32.into(),
        };
        
        let synced_status: SyncStatus<TestBlock> = SyncStatus::Synced {
            best: 200u32.into(),
        };
        
        let error_status: SyncStatus<TestBlock> = SyncStatus::Error("Test error".to_string());
        
        // Verify status variants work correctly
        match syncing_status {
            SyncStatus::Syncing { current, highest } => {
                assert_eq!(current, 100u32.into());
                assert_eq!(highest, 200u32.into());
            }
            _ => panic!("Expected syncing status"),
        }
        
        match synced_status {
            SyncStatus::Synced { best } => {
                assert_eq!(best, 200u32.into());
            }
            _ => panic!("Expected synced status"),
        }
        
        match error_status {
            SyncStatus::Error(msg) => {
                assert_eq!(msg, "Test error");
            }
            _ => panic!("Expected error status"),
        }
    }
    
    #[test]
    fn test_block_data_creation() {
        // Create a test block data structure
        let header = TestHeader {
            parent_hash: H256::zero(),
            number: 1u32.into(),
            state_root: H256::zero(),
            extrinsics_root: H256::zero(),
            digest: sp_runtime::generic::Digest::default(),
        };
        
        let block_data: BlockData<TestBlock> = BlockData {
            header: header.clone(),
            body: None,
            justifications: None,
            hash: header.hash(),
            number: header.number,
        };
        
        assert_eq!(block_data.number, 1u32.into());
        assert_eq!(block_data.hash, header.hash());
        assert!(block_data.body.is_none());
        assert!(block_data.justifications.is_none());
    }
}
