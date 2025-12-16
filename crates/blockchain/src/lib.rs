//! # Blockchain
//!
//! This crate provides blockchain integration for the Browser project, including
//! Substrate client, wallet management, and transaction handling.
//!
//! ## Features
//! - Substrate client for interacting with Substrate-based blockchains
//! - Wallet management with support for multiple key types
//! - Transaction creation, signing, and submission
//! - Support for substrate and Ethereum-compatible chains

#![warn(missing_docs)]
#![warn(unused_extern_crates)]
#![forbid(unsafe_code)]

use sp_runtime::codec;

#[cfg(feature = "substrate")]
mod client;
#[cfg(feature = "substrate")]
mod sync;
#[cfg(feature = "substrate")]
mod transaction;
mod wallet;

// Re-export the most commonly used types
#[cfg(feature = "substrate")]
pub use client::{Client, SubstrateClient, SubstrateConfig};
pub use sp_core::{
    crypto::{Pair, Ss58Codec},
    sr25519,
};
#[cfg(feature = "substrate")]
pub use sp_runtime::{
    Justifications, MultiSignature,
    generic::Era,
    traits::{Block as BlockT, Header as HeaderT},
};
#[cfg(feature = "substrate")]
pub use sync::{BlockData, ChainSync, SyncConfig, SyncStatus};
#[cfg(feature = "substrate")]
pub use transaction::{Transaction, TransactionBuilder, TransactionReceipt};
pub use wallet::{KeyPair, KeyType, Wallet, WalletError};

/// Error type for the blockchain crate
#[derive(thiserror::Error, Debug)]
pub enum Error {
    /// Client error
    #[error("Client error: {0}")]
    Client(#[from] anyhow::Error),

    /// Wallet error
    #[error("Wallet error: {0}")]
    Wallet(#[from] WalletError),

    /// Transaction error
    #[error("Transaction error: {0}")]
    Transaction(String),

    /// Codec error
    #[error("Codec error: {0}")]
    Codec(#[from] codec::Error),

    /// Other error
    #[error("Blockchain error: {0}")]
    Other(String),
}

/// Result type for the blockchain crate
pub type Result<T> = std::result::Result<T, Error>;

#[cfg(all(test, feature = "substrate"))]
mod tests {
    use super::*;
    use sp_keyring::AccountKeyring;

    #[test]
    fn test_account_id_conversion() {
        let alice = AccountKeyring::Alice.to_account_id();
        let encoded = hex::encode(alice.as_ref());
        let decoded = hex::decode(encoded).unwrap();
        let account_id = sp_core::crypto::AccountId32::try_from(decoded.as_slice()).unwrap();
        assert_eq!(alice, account_id);
    }
}
