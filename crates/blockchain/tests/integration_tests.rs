//! Integration tests for the blockchain crate
//! 
//! These tests will automatically start a local Substrate node in --dev mode.

use anyhow::Result;
use sp_core::{
    crypto::{Pair, Ss58Codec},
    sr25519::Pair as Sr25519Pair,
};
use sp_keyring::AccountKeyring;
use std::{sync::Arc, time::Duration};
use substrate_subxt::{Client, DefaultNodeRuntime, PairSigner};
use tempfile::tempdir;

mod test_utils;
use test_utils::{with_test_node, with_test_node_async};

use blockchain::{
    client::{SubstrateClient, SubstrateConfig},
    wallet::{KeyPair, KeyType, Wallet},
    transaction::{Transaction, TransactionBuilder},
    sync::{ChainSync, SyncConfig},
};

/// Test helper to create a test client
async fn create_test_client(node_url: &str) -> Result<SubstrateClient> {
    let config = SubstrateConfig {
        node_url: node_url.to_string(),
        ..Default::default()
    };
    
    let client = SubstrateClient::new(config).await?;
    Ok(client)
}

/// Test helper to wait for a number of blocks
async fn wait_for_blocks(client: &SubstrateClient, count: u32) -> Result<()> {
    const BLOCK_TIMEOUT: Duration = Duration::from_secs(30);
    
    let mut subscription = client.inner().blocks().subscribe_finalized().await?;
    
    for _ in 0..count {
        match tokio::time::timeout(BLOCK_TIMEOUT, subscription.next()).await {
            Ok(Some(Ok(_))) => {}
            Ok(Some(Err(e))) => return Err(e.into()),
            Ok(None) => break,
            Err(_) => return Err(anyhow::anyhow!("Timeout waiting for block")),
        }
    }
    
    Ok(())
}

/// Test that we can connect to a local Substrate node
#[tokio::test]
async fn test_client_connection() -> Result<()> {
    with_test_node_async(|config| async move {
        let client = create_test_client(&config.node_url).await?;
    
    // Get the genesis hash
    let genesis_hash = client
        .inner()
        .rpc()
        .genesis_hash()
        .await?;
        
    assert!(!genesis_hash.is_zero(), "Genesis hash should not be zero");
    
    // Get the runtime version
    let runtime_version = client
        .inner()
        .rpc()
        .runtime_version(None)
        .await?;
        
        assert!(!runtime_version.spec_name.is_empty(), "Runtime spec name should not be empty");
        
        Ok(())
    }).await
}

/// Test wallet operations
#[test]
fn test_wallet_operations() -> Result<()> {
    with_test_node(|_| {
        let mut wallet = Wallet::new();
    
    // Create a key pair from a seed
    let key_pair = KeyPair::from_seed(
        &[0u8; 32],
        KeyType::Sr25519,
    )?;
    
    // Add the key to the wallet
    wallet.add_key("test_key", key_pair.clone())?;
    
    // Test retrieving the key
    let retrieved = wallet.get_key("test_key").unwrap();
    assert_eq!(
        hex::encode(retrieved.public_key()),
        hex::encode(key_pair.public_key())
    );
    
    // Test signing and verification
    let message = b"test message";
    let signature = key_pair.sign(message);
        assert!(key_pair.verify(message, &signature));
        
        Ok(())
    })
}

/// Test transaction creation and signing
#[test]
fn test_transaction_signing() -> Result<()> {
    with_test_node(|_| {
        // Create a key pair for testing
        let pair = Sr25519Pair::from_string("//Alice", None)?;
    let signer = PairSigner::<DefaultNodeRuntime, _>::new(pair.clone());
    
    // Create a test transaction
    let tx = TransactionBuilder::new()
        .from(&hex::encode(pair.public().0))
        .unwrap()
        .to("5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY")
        .unwrap()
        .amount(1000)
        .nonce(0)
        .tip(10)
        .build()?;
    
    // Sign the transaction
    let signed_tx = tx.sign(&pair)?;
    
    // Verify the signature
        assert!(signed_tx.verify());
        
        Ok(())
    })
}

/// Test chain synchronization
#[tokio::test]
async fn test_chain_sync() -> Result<()> {
    with_test_node_async(|config| async move {
        let client = Arc::new(create_test_client(&config.node_url).await?);
    
    // Create a temporary directory for the database
    let temp_dir = tempdir()?;
    
    // Configure chain sync
    let config = SyncConfig {
        download_bodies: true,
        max_concurrent_requests: 5,
        max_blocks_per_request: 32,
        request_timeout_secs: 30,
        max_blocks_in_memory: 100,
    };
    
    // Create chain sync
    let mut chain_sync = ChainSync::new(client.clone(), config).await?;
    
    // Start synchronization
    let sync_handle = tokio::spawn(async move {
        chain_sync.start().await
    });
    
    // Wait for a few blocks to be processed
    tokio::time::sleep(Duration::from_secs(5)).await;
    
    // Check the sync status
    match chain_sync.status() {
        blockchain::sync::SyncStatus::Syncing { current, highest } => {
            assert!(current > 0, "Should have synced at least one block");
            assert!(highest > 0, "Should have seen at least one block");
        }
        blockchain::sync::SyncStatus::Synced { best } => {
            assert!(best > 0, "Should have synced at least one block");
        }
        blockchain::sync::SyncStatus::Error(e) => {
            panic!("Chain sync error: {}", e);
        }
    }
    
        // Stop the sync
        sync_handle.abort();
        
        Ok(())
    }).await
}

/// Test end-to-end transaction submission
#[tokio::test]
async fn test_transaction_submission() -> Result<()> {
    with_test_node_async(|config| async move {
        let client = create_test_client(&config.node_url).await?;
    
    // Get the Alice key pair
    let alice = AccountKeyring::Alice.pair();
    let alice_signer = PairSigner::<DefaultNodeRuntime, _>::new(alice.clone());
    
    // Get the Bob account ID
    let bob = AccountKeyring::Bob.to_account_id();
    
    // Get the current balance of Bob
    let initial_balance = client
        .inner()
        .fetch_or_default(&bob, None)
        .await?;
    
    // Create and sign a transfer transaction
    let tx = TransactionBuilder::new()
        .from(&hex::encode(alice.public().0))
        .unwrap()
        .to(&hex::encode(bob.as_ref()))
        .unwrap()
        .amount(1_000_000_000) // 1 token (assuming 12 decimals)
        .nonce(
            client
                .inner()
                .system()
                .account_nonce(&alice.public().into())
                .await?,
        )
        .tip(0)
        .build()?;
    
    let signed_tx = tx.sign(&alice)?;
    
    // Submit the transaction
    let tx_hash = client
        .inner()
        .tx()
        .sign_and_submit_default(&signed_tx, &alice_signer)
        .await?;
    
    // Wait for the transaction to be included in a block
    let _block_hash = client
        .inner()
        .rpc()
        .author_wait_for(tx_hash)
        .await?;
    
    // Wait for a few blocks to ensure the transaction is finalized
    wait_for_blocks(&client, 3).await?;
    
    // Check the new balance of Bob
    let new_balance = client
        .inner()
        .fetch_or_default(&bob, None)
        .await?;
    
        assert!(
            new_balance > initial_balance,
            "Bob's balance should have increased"
        );
        
        Ok(())
    }).await
}

/// Test wallet integration with the blockchain
#[tokio::test]
async fn test_wallet_integration() -> Result<()> {
    with_test_node_async(|config| async move {
        let client = create_test_client(&config.node_url).await?;
        let mut wallet = Wallet::new();
    
    // Create a new key pair in the wallet
    let key_pair = KeyPair::from_seed(
        &[1u8; 32],
        KeyType::Sr25519,
    )?;
    
    wallet.add_key("test_account", key_pair.clone())?;
    
    // Get the account ID
    let account_id = key_pair.to_ss58();
    
    // Get the balance (should be zero for a new account)
    let balance = client
        .inner()
        .fetch_or_default(&account_id.parse()?, None)
        .await?;
    
        assert_eq!(balance, 0, "New account should have zero balance");
        
        Ok(())
    }).await
}
