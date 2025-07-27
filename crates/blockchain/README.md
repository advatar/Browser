# Blockchain Crate

This crate provides blockchain integration for the Browser project, including Substrate client, wallet management, and transaction handling.

## Features

- Substrate client for interacting with Substrate-based blockchains
- Wallet management with support for multiple key types (sr25519, ed25519, ecdsa)
- Transaction creation, signing, and submission
- Chain synchronization and block subscription
- Support for Substrate and Ethereum-compatible chains

## Prerequisites

- Rust toolchain (latest stable version)
- Substrate node binary (for local testing)

## Running Tests

### Unit Tests

Run the unit tests with:

```bash
cargo test --lib
```

### Integration Tests

The integration tests require a local Substrate node. The test framework can automatically start a local node for testing.

1. Make sure you have the Substrate node binary (`substrate`) installed and available in your PATH.

2. Run the integration tests:

```bash
# Run all tests
cargo test --test integration_tests -- --test-threads=1

# Run a specific test
cargo test --test integration_tests test_client_connection -- --nocapture
```

### Test Coverage

To generate a test coverage report (requires `cargo-tarpaulin`):

```bash
cargo tarpaulin --lib --tests --out Html
```

## Usage

### Creating a Client

```rust
use blockchain::{SubstrateClient, SubstrateConfig};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let config = SubstrateConfig {
        node_url: "ws://127.0.0.1:9944".to_string(),
        ..Default::default()
    };
    
    let client = SubstrateClient::new(config).await?;
    
    // Use the client...
    
    Ok(())
}
```

### Wallet Operations

```rust
use blockchain::{Wallet, KeyPair, KeyType};

let mut wallet = Wallet::new();

// Generate a new key pair
let key_pair = KeyPair::generate(KeyType::Sr25519);
wallet.add_key("alice", key_pair)?;

// Sign a message
let message = b"Hello, world!";
let signature = wallet.sign("alice", message)?;

// Verify the signature
let is_valid = wallet.verify("alice", message, &signature);
```

### Transaction Handling

```rust
use blockchain::{TransactionBuilder, Transaction};
use sp_keyring::AccountKeyring;

// Create a new transaction
let tx = TransactionBuilder::new()
    .from("5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY")
    .unwrap()
    .to("5FHneW46xGXgs5mUiveU4sbTyGBzmstUspZC92UhjJM694ty")
    .unwrap()
    .amount(1000)
    .nonce(0)
    .tip(10)
    .build()?;

// Sign the transaction
let signed_tx = tx.sign(&key_pair)?;

// Submit the transaction
let tx_hash = client.submit_transaction(signed_tx).await?;
```

### Chain Synchronization

```rust
use blockchain::{ChainSync, SyncConfig};
use std::sync::Arc;

let config = SyncConfig {
    download_bodies: true,
    ..Default::default()
};

let mut chain_sync = ChainSync::new(Arc::new(client), config).await?;

// Start the synchronization
let sync_handle = tokio::spawn(async move {
    chain_sync.start().await
});

// Get the current status
let status = chain_sync.status();

// Stop the synchronization
sync_handle.abort();
```

## License

This project is licensed under the [MIT License](LICENSE).
