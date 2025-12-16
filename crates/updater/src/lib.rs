//! IPFS-backed update mechanism with signature and integrity verification.
//!
//! This crate provides tooling to securely fetch and apply application updates
//! that are published on IPFS. Updates are represented by signed manifests
//! which point to release artefacts (e.g. binaries). The updater downloads the
//! manifest, verifies its signature, validates the artefact checksum, and then
//! atomically swaps the local binary with the newly downloaded version.
//!
//! ```ignore
//! use cid::Cid;
//! use ed25519_dalek::VerifyingKey;
//! use updater::{IpfsGatewayClient, UpdateStatus, Updater};
//!
//! # async fn demo() -> updater::Result<()> {
//! let gateway = IpfsGatewayClient::builder().build()?;
//! let verifying_key = VerifyingKey::from_bytes(&[0u8; 32]).unwrap();
//! let updater = Updater::new(gateway, verifying_key);
//!
//! let manifest_cid = Cid::try_from("bafy...manifest").unwrap();
//! match updater
//!     .check_for_update_str(env!("CARGO_PKG_VERSION"), &manifest_cid)
//!     .await?
//! {
//!     UpdateStatus::Available(update) => {
//!         let binary_path = std::path::Path::new("/usr/local/bin/browser");
//!         updater.download_and_apply(&update, binary_path).await?;
//!     }
//!     UpdateStatus::UpToDate => {
//!         println!("already at latest version");
//!     }
//! }
//! # Ok(())
//! # }
//! ```

mod error;
mod fetcher;
mod manifest;
mod updater;

pub use error::{Result, UpdaterError};
pub use fetcher::{IpfsFetcher, IpfsGatewayClient, IpfsGatewayClientBuilder};
pub use manifest::{SignedManifest, UpdateManifest};
pub use updater::{AvailableUpdate, DownloadOutcome, UpdateStatus, Updater};
