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
        // First check if the requested block number is within range
        let latest_block = self.client.blocks().at_latest().await?;
        let latest_number = latest_block.number();
        
        if number > latest_number {
            // Block number is in the future, doesn't exist yet
            return Ok(None);
        }
        
        // Get the block at the specific number
        let block_result = self.client.blocks().at_height(number).await;
        
        match block_result {
            Ok(target_block) => {
                let header = target_block.header().clone();
                let hash = target_block.hash();
                
                // Get block body if configured
                let body = if self.config.download_bodies {
                    let extrinsics_result = target_block.extrinsics().await;
                    match extrinsics_result {
                        Ok(extrinsics) => {
                            let collected: Result<Vec<_>, _> = extrinsics.collect();
                            match collected {
                                Ok(ext_vec) => Some(ext_vec),
                                Err(e) => {
                                    log::warn!("Failed to collect extrinsics for block #{}: {}", number, e);
                                    None
                                }
                            }
                        },
                        Err(e) => {
                            log::warn!("Failed to get extrinsics for block #{}: {}", number, e);
                            None
                        }
                    }
                } else {
                    None
                };
                
                // Get justifications if available
                // In production code, we need to query the runtime API for justifications
                let justifications = match target_block.justifications().await {
                    Ok(Some(j)) => Some(j),
                    Ok(None) => None,
                    Err(e) => {
                        log::debug!("No justifications available for block #{}: {}", number, e);
                        None
                    }
                };
                
                Ok(Some(BlockData {
                    header,
                    body,
                    justifications,
                    hash,
                    number,
                }))
            },
            Err(e) => {
                log::debug!("Failed to get block #{}: {}", number, e);
                Ok(None)
            }
        }
    }
    
    /// Background synchronization loop
    async fn background_sync_loop(client: Arc<OnlineClient<PolkadotConfig>>) -> Result<()> {
        log::info!("Starting background chain synchronization loop");
        
        // Create intervals for different sync operations
        let mut fast_sync_interval = interval(Duration::from_secs(5));  // Quick checks for new blocks
        let mut full_sync_interval = interval(Duration::from_secs(30)); // Full sync checks
        let mut health_check_interval = interval(Duration::from_secs(60)); // Network health checks
        
        // Track metrics for sync performance
        let mut last_sync_time = Instant::now();
        let mut blocks_processed = 0;
        let mut consecutive_errors = 0;
        
        // Subscribe to new block notifications
        let mut blocks_sub = match client.blocks().subscribe_finalized().await {
            Ok(sub) => {
                log::info!("Successfully subscribed to finalized blocks");
                Some(sub)
            },
            Err(e) => {
                log::warn!("Failed to subscribe to finalized blocks: {}", e);
                None
            }
        };
        
        loop {
            tokio::select! {
                // Process new blocks from subscription
                maybe_block = async {
                    if let Some(sub) = &mut blocks_sub {
                        sub.next().await
                    } else {
                        // If subscription is not available, never select this branch
                        futures::future::pending().await
                    }
                } => {
                    match maybe_block {
                        Some(Ok(block)) => {
                            let number = block.number();
                            let hash = block.hash();
                            log::info!("New finalized block: #{} ({})", number, hash);
                            
                            // Process the new block
                            blocks_processed += 1;
                            consecutive_errors = 0;
                        },
                        Some(Err(e)) => {
                            log::error!("Error in block subscription: {}", e);
                            consecutive_errors += 1;
                            
                            // Attempt to resubscribe if we get too many errors
                            if consecutive_errors > 3 {
                                log::warn!("Too many subscription errors, attempting to resubscribe");
                                blocks_sub = match client.blocks().subscribe_finalized().await {
                                    Ok(sub) => {
                                        log::info!("Successfully resubscribed to finalized blocks");
                                        consecutive_errors = 0;
                                        Some(sub)
                                    },
                                    Err(e) => {
                                        log::error!("Failed to resubscribe to finalized blocks: {}", e);
                                        None
                                    }
                                };
                            }
                        },
                        None => {
                            log::warn!("Block subscription ended, attempting to resubscribe");
                            blocks_sub = match client.blocks().subscribe_finalized().await {
                                Ok(sub) => {
                                    log::info!("Successfully resubscribed to finalized blocks");
                                    Some(sub)
                                },
                                Err(e) => {
                                    log::error!("Failed to resubscribe to finalized blocks: {}", e);
                                    None
                                }
                            };
                        }
                    }
                },
                
                // Fast sync check for new blocks
                _ = fast_sync_interval.tick() => {
                    if let Err(e) = Self::perform_sync_check(&client).await {
                        log::debug!("Error during fast sync check: {}", e);
                        consecutive_errors += 1;
                    }
                },
                
                // Full sync check
                _ = full_sync_interval.tick() => {
                    // Calculate sync metrics
                    let elapsed = last_sync_time.elapsed();
                    let blocks_per_minute = if elapsed.as_secs() > 0 {
                        (blocks_processed as f64 / elapsed.as_secs() as f64) * 60.0
                    } else {
                        0.0
                    };
                    
                    log::info!("Sync metrics: {} blocks processed in the last {} seconds ({:.2} blocks/minute)", 
                        blocks_processed, elapsed.as_secs(), blocks_per_minute);
                    
                    // Reset metrics
                    last_sync_time = Instant::now();
                    blocks_processed = 0;
                    
                    // Perform a full sync check
                    if let Err(e) = Self::perform_sync_check(&client).await {
                        log::error!("Error during full sync check: {}", e);
                        consecutive_errors += 1;
                    } else {
                        consecutive_errors = 0;
                    }
                },
                
                // Network health check
                _ = health_check_interval.tick() => {
                    // Check node health and connection status
                    match client.rpc().system_health().await {
                        Ok(health) => {
                            log::info!("Node health: peers={}, syncing={}, should_have_peers={}", 
                                health.peers, health.is_syncing, health.should_have_peers);
                            
                            // If we're not connected to any peers but should be, log a warning
                            if health.peers == 0 && health.should_have_peers {
                                log::warn!("Node has no peers but should have peers");
                            }
                        },
                        Err(e) => {
                            log::error!("Failed to check node health: {}", e);
                            consecutive_errors += 1;
                        }
                    }
                },
                
                // Handle shutdown signal
                _ = tokio::signal::ctrl_c() => {
                    log::info!("Shutting down chain synchronization");
                    break;
                }
            }
            
            // If we have too many consecutive errors, delay before continuing
            if consecutive_errors > 5 {
                log::warn!("Too many consecutive errors ({}), pausing sync for recovery", consecutive_errors);
                tokio::time::sleep(Duration::from_secs(10)).await;
                consecutive_errors = 0;
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
            // Collect events into a vector to properly handle the async stream
            let event_vec = events.collect::<Result<Vec<_>, _>>().await?;
            let event_count = event_vec.len();
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
