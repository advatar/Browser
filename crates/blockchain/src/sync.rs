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
use substrate_subxt::{
    blocks::Block as SubxtBlock,
    events::EventsDecoder,
    rpc::Subscription,
    Client, Error as SubxtError,
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
pub struct ChainSync<B, C> 
where
    B: BlockT,
    C: Client<B> + Send + Sync + 'static,
{
    /// The Substrate client
    client: Arc<C>,
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
    /// Block subscription
    block_subscription: Option<Subscription<B>>,
    /// Event decoder for the current runtime
    events_decoder: EventsDecoder<B>,
}

impl<B, C> ChainSync<B, C>
where
    B: BlockT,
    C: Client<B> + Send + Sync + 'static,
{
    /// Create a new chain synchronizer
    pub async fn new(client: Arc<C>, config: SyncConfig) -> Result<Self> {
        let events_decoder = client.events_decoder()?;
        
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
            events_decoder,
        })
    }

    /// Start the synchronization process
    pub async fn start(&mut self) -> Result<()> {
        // Get the current best block
        let best_block = self.client.blocks().at_latest().await?;
        let best_number = best_block.number();
        
        // Update status
        self.highest_seen = Some(best_number);
        self.best_processed = Some(0u32.into());
        
        // Start subscription to new blocks
        self.block_subscription = Some(
            self.client
                .blocks()
                .subscribe_finalized()
                .await?
        );
        
        // Start the sync loop
        self.sync_loop().await?;
        
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
    
    /// The main synchronization loop
    async fn sync_loop(&mut self) -> Result<()> {
        // First, perform a full sync to catch up
        self.full_sync().await?;
        
        // Then listen for new blocks
        if let Some(subscription) = &mut self.block_subscription {
            while let Some(block_result) = subscription.next().await {
                match block_result {
                    Ok(block) => {
                        if let Err(e) = self.handle_new_block(block).await {
                            log::error!("Error handling new block: {}", e);
                            self.status = SyncStatus::Error(format!("Block processing error: {}", e));
                            break;
                        }
                    }
                    Err(e) => {
                        log::error!("Block subscription error: {}", e);
                        self.status = SyncStatus::Error(format!("Subscription error: {}", e));
                        break;
                    }
                }
                
                // Periodic sync
                _ = interval.tick() => {
                    self.full_sync().await?;
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
    
    /// Handle a new block from the subscription
    async fn handle_new_block(&mut self, block: SubxtBlock<B, C>) -> Result<()> {
        let number = block.number();
        let hash = block.hash();
        
        // Update highest seen block
        if self.highest_seen.map_or(true, |h| number > h) {
            self.highest_seen = Some(number);
        }
        
        // Process the block
        self.process_block(block).await?;
        
        // Update status
        if let Some(best) = self.best_processed {
            self.status = SyncStatus::Syncing {
                current: best,
                highest: self.highest_seen.unwrap_or(best),
            };
        }
        
        Ok(())
    }
    
    /// Perform a full synchronization
    async fn full_sync(&mut self) -> Result<()> {
        let best_block = self.client.blocks().at_latest().await?;
        let best_number = best_block.number();
        
        // Update highest seen block
        if self.highest_seen.map_or(true, |h| best_number > h) {
            self.highest_seen = Some(best_number);
        }
        
        // Determine the range of blocks to download
        let start = self.best_processed.unwrap_or(0u32.into()) + 1u32.into();
        let end = best_number.min(start + self.config.max_blocks_per_request.into());
        
        if start > end {
            // We're up to date
            self.status = SyncStatus::Synced { best: best_number };
            return Ok(());
        }
        
        log::info!("Synchronizing blocks {} to {}", start, end);
        
        // Download blocks in parallel
        let mut block_futures = Vec::new();
        
        for number in start..=end {
            let client = self.client.clone();
            let download_bodies = self.config.download_bodies;
            
            block_futures.push(tokio::spawn(async move {
                let block = client.blocks().at(Some(number.into())).await?;
                
                let header = block.header().clone();
                let hash = block.hash();
                
                // Only download the body if configured to do so
                let body = if download_bodies {
                    Some(block.extrinsics().await?)
                } else {
                    None
                };
                
                // Get justifications if available
                let justifications = block.justifications().await?;
                
                Ok::<_, anyhow::Error>(BlockData {
                    header,
                    body,
                    justifications,
                    hash,
                    number,
                })
            }));
        }
        
        // Process blocks as they complete
        let mut stream = futures::stream::iter(block_futures).buffer_unordered(self.config.max_concurrent_requests);
        
        while let Some(result) = stream.next().await {
            match result {
                Ok(Ok(block_data)) => {
                    self.queued_blocks.insert(block_data.number, block_data);
                    
                    // Process blocks in order
                    self.process_queued_blocks().await?;
                }
                Ok(Err(e)) => {
                    log::error!("Error downloading block: {}", e);
                }
                Err(e) => {
                    log::error!("Error in block download task: {}", e);
                }
            }
        }
        
        // Update status
        if let Some(best) = self.best_processed {
            self.status = SyncStatus::Syncing {
                current: best,
                highest: self.highest_seen.unwrap_or(best),
            };
        }
        
        Ok(())
    }
    
    /// Process blocks that are ready to be processed (in order)
    async fn process_queued_blocks(&mut self) -> Result<()> {
        let mut next_expected = self.best_processed.unwrap_or(0u32.into()) + 1u32.into();
        
        while let Some(block_data) = self.queued_remove(&next_expected).await? {
            // Process the block
            let block = self.client.blocks().at(Some(block_data.hash)).await?;
            self.process_block(block).await?;
            
            next_expected += 1u32.into();
        }
        
        Ok(())
    }
    
    /// Process a single block
    async fn process_block(&mut self, block: SubxtBlock<B, C>) -> Result<()> {
        let number = block.number();
        
        // Update best processed block
        if self.best_processed.map_or(true, |b| number > b) {
            self.best_processed = Some(number);
        }
        
        // Process transactions in the block
        if self.config.download_bodies {
            let extrinsics = block.extrinsics().await?;
            
            // Process each transaction in the block
            for (idx, extrinsic) in extrinsics.iter().enumerate() {
                match extrinsic {
                    Ok(ext) => {
                        // Log transaction details
                        log::debug!("Processing transaction {} in block #{}: {:?}", idx, number, ext.index());
                        
                        // Extract transaction metadata
                        if let Ok(call_data) = ext.call_data() {
                            log::trace!("Transaction call data: {} bytes", call_data.len());
                        }
                        
                        // Check if transaction was successful
                        if let Ok(events) = ext.events().await {
                            let success = events.has::<substrate_subxt::events::ExtrinsicSuccess>()?;
                            let failed = events.has::<substrate_subxt::events::ExtrinsicFailed>()?;
                            
                            if success {
                                log::debug!("Transaction {} succeeded", idx);
                            } else if failed {
                                log::warn!("Transaction {} failed", idx);
                            }
                        }
                    }
                    Err(e) => {
                        log::error!("Error decoding transaction {} in block #{}: {}", idx, number, e);
                    }
                }
            }
        }
        
        // Process events in the block
        let events = block.events().await?;
        
        // Process system events
        for event in events.iter() {
            match event {
                Ok(event_details) => {
                    // Log event details
                    log::trace!("Block #{} event: {:?}", number, event_details.pallet_name());
                    
                    // Handle specific event types
                    match event_details.pallet_name() {
                        "System" => {
                            // Handle system events (new account, killed account, etc.)
                            log::debug!("System event in block #{}: {}", number, event_details.variant_name());
                        }
                        "Balances" => {
                            // Handle balance transfer events
                            log::debug!("Balance event in block #{}: {}", number, event_details.variant_name());
                        }
                        "Timestamp" => {
                            // Handle timestamp events
                            log::trace!("Timestamp event in block #{}", number);
                        }
                        pallet => {
                            // Handle other pallet events
                            log::trace!("Event from {} pallet in block #{}: {}", pallet, number, event_details.variant_name());
                        }
                    }
                }
                Err(e) => {
                    log::error!("Error decoding event in block #{}: {}", number, e);
                }
            }
        }
        
        log::debug!("Processed block #{}", number);
        
        Ok(())
    }
    
    /// Remove a block from the queue by number
    async fn queued_remove(&mut self, number: &NumberFor<B>) -> Result<Option<BlockData<B>>> {
        let result = self.queued_blocks.remove(number);
        
        // Clean up old blocks if we have too many in memory
        if self.queued_blocks.len() > self.config.max_blocks_in_memory {
            let mut numbers: Vec<_> = self.queued_blocks.keys().cloned().collect();
            numbers.sort();
            
            // Keep the most recent blocks
            let to_remove = numbers.len().saturating_sub(self.config.max_blocks_in_memory / 2);
            
            for number in numbers.into_iter().take(to_remove) {
                self.queued_blocks.remove(&number);
            }
        }
        
        Ok(result)
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
