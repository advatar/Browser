//! A persistent block storage implementation using Sled.
//!
//! This module provides a simple key-value store for IPFS blocks, where the keys are CIDs
//! (Content Identifiers) and the values are the raw block data. The storage is backed by
//! [Sled](https://github.com/spacejam/sled), an embedded database.
//!
//! # Examples
//!
//! ```no_run
//! use ipfs::blockstore::SledStore;
//! use std::path::Path;
//!
//! # fn main() -> anyhow::Result<()> {
//! // Create a new store in a temporary directory
//! let store = SledStore::new("./data/ipfs")?;
//!
//! // Store some data and get its CID
//! let data = b"hello world";
//! let cid = store.put(data)?;
//!
//! // Retrieve the data using the CID
//! if let Some(retrieved) = store.get(&cid)? {
//!     assert_eq!(&retrieved, data);
//! }
//! # Ok(())
//! # }
//! ```

use anyhow::{Context, Result};
use cid::Cid;
use multihash_codetable::{Code, MultihashDigest};
use std::path::Path;

/// A persistent block storage implementation using Sled.
///
/// This store maps CIDs (Content Identifiers) to their corresponding block data.
/// It provides a simple key-value interface where keys are CIDs and values are raw block data.
///
/// # Example
/// ```no_run
/// # use ipfs::blockstore::SledStore;
/// # use std::path::Path;
/// # fn main() -> anyhow::Result<()> {
/// let store = SledStore::new("./data/ipfs")?;
/// let cid = store.put(b"hello world")?;
/// if let Some(data) = store.get(&cid)? {
///     println!("Retrieved: {:?}", data);
/// }
/// # Ok(()) }
/// ```
/// A persistent block storage implementation using Sled.
///
/// This store maps CIDs (Content Identifiers) to their corresponding block data.
/// It provides a simple key-value interface where keys are CIDs and values are raw block data.
#[derive(Debug, Clone)]
pub struct SledStore {
    /// The underlying Sled database instance
    db: sled::Db,
}

impl SledStore {
    /// Creates a new SledStore at the specified path.
    ///
    /// # Arguments
    ///
    /// * `path` - The filesystem path where the Sled database will be stored.
    ///           The directory will be created if it doesn't exist.
    ///
    /// # Errors
    ///
    /// Returns an error if the database cannot be opened or created at the specified path.
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use ipfs::blockstore::SledStore;
    /// # fn main() -> anyhow::Result<()> {
    /// // Create a new store in the current directory
    /// let store = SledStore::new("./data/ipfs")?;
    /// # Ok(()) }
    /// ```
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let db = sled::open(path).context("failed to open sled database")?;
        Ok(Self { db })
    }

    /// Stores a block of data and returns its CID.
    ///
    /// The data is hashed using SHA2-256 (the default hash function for IPFS) and
    /// stored with a CID v1 in raw binary format (codec 0x55).
    ///
    /// # Arguments
    ///
    /// * `data` - The binary data to store.
    ///
    /// # Returns
    ///
    /// Returns the CID (Content Identifier) of the stored data.
    ///
    /// # Errors
    ///
    /// Returns an error if the data cannot be stored in the database.
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use ipfs::blockstore::SledStore;
    /// # fn main() -> anyhow::Result<()> {
    /// let store = SledStore::new("./data/ipfs")?;
    /// let cid = store.put(b"hello world")?;
    /// println!("Stored data with CID: {}", cid);
    /// # Ok(()) }
    /// ```
    pub fn put(&self, data: &[u8]) -> Result<Cid> {
        // Create a multihash using SHA2-256 (default for IPFS)
        let hash = Code::Sha2_256.digest(data);

        // Create a CID v1 with raw binary format (0x55)
        // Note: Cid::new_v1 is infallible, so we don't need to handle Result
        let cid = Cid::new_v1(0x55, hash);

        // Store the data with the CID as the key
        self.db
            .insert(cid.to_bytes(), data)
            .context("failed to insert data into sled")?;

        // Ensure the data is flushed to disk
        self.db.flush().context("failed to flush sled db")?;

        Ok(cid)
    }

    /// Retrieves a block of data by its CID.
    ///
    /// # Arguments
    ///
    /// * `cid` - The Content Identifier of the data to retrieve.
    ///
    /// # Returns
    ///
    /// Returns `Some(Vec<u8>)` if the data was found, or `None` if no data exists
    /// for the given CID.
    ///
    /// # Errors
    ///
    /// Returns an error if there was a problem accessing the database.
    ///
    /// # Example
    ///
    /// ```no_run
    /// # use ipfs::blockstore::SledStore;
    /// # use cid::Cid;
    /// # use std::str::FromStr;
    /// # fn main() -> anyhow::Result<()> {
    /// # let store = SledStore::new("./data/ipfs")?;
    /// // Assuming we have a CID from a previous put operation
    /// # let cid = store.put(b"hello world")?;
    /// if let Some(data) = store.get(&cid)? {
    ///     println!("Retrieved data: {:?}", data);
    /// } else {
    ///     println!("No data found for CID: {}", cid);
    /// }
    /// # Ok(()) }
    /// ```
    pub fn get(&self, cid: &Cid) -> Result<Option<Vec<u8>>> {
        match self.db.get(cid.to_bytes())? {
            Some(data) => Ok(Some(data.to_vec())),
            None => Ok(None),
        }
    }
}

// Implement basic block store functionality for SledStore
impl SledStore {
    /// Inserts a block into the store under the given `cid`.
    ///
    /// # Errors
    ///
    /// Returns an error if writing to the underlying database fails.
    pub fn insert(&self, cid: &Cid, data: &[u8]) -> Result<()> {
        self.db
            .insert(cid.to_bytes(), data)
            .context("failed to insert block")?;
        Ok(())
    }

    /// Removes a block identified by `cid` from the store.
    ///
    /// # Errors
    ///
    /// Returns an error if removal from the underlying database fails.
    pub fn remove(&self, cid: &Cid) -> Result<()> {
        self.db
            .remove(cid.to_bytes())
            .context("failed to remove block")?;
        Ok(())
    }

    /// Lists all CIDs currently stored.
    ///
    /// # Returns
    ///
    /// A vector of `Cid` entries present in the store.
    ///
    /// # Errors
    ///
    /// Returns an error if reading or parsing entries fails.
    pub fn list(&self) -> Result<Vec<Cid>> {
        self.db
            .iter()
            .map(|item| {
                let (key, _) = item.context("failed to read database entry")?;
                Cid::try_from(&*key).context("failed to parse CID from database key")
            })
            .collect()
    }

    /// Checks whether a block identified by `cid` exists in the store.
    ///
    /// # Returns
    ///
    /// `true` if the block exists, `false` otherwise.
    ///
    /// # Errors
    ///
    /// Returns an error if the existence check fails.
    pub fn contains(&self, cid: &Cid) -> Result<bool> {
        self.db
            .contains_key(cid.to_bytes())
            .context("failed to check if block exists")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use multihash_codetable::Code;
    use rand::RngCore;
    use tempfile::tempdir;

    fn create_test_store() -> (tempfile::TempDir, SledStore) {
        let dir = tempdir().expect("failed to create temp dir");
        let store = SledStore::new(dir.path()).expect("failed to create store");
        (dir, store)
    }

    #[test]
    fn test_put_and_get() {
        let (_dir, store) = create_test_store();

        // Test with a small piece of data
        let data = b"hello world";
        let cid = store.put(data).expect("failed to put data");

        let retrieved = store
            .get(&cid)
            .expect("failed to get data")
            .expect("data not found");
        assert_eq!(&retrieved, data);
    }

    #[test]
    fn test_put_and_get_large_data() {
        let (_dir, store) = create_test_store();

        // Test with a larger piece of data (1KB)
        let mut data = vec![0u8; 1024];
        rand::thread_rng().fill_bytes(&mut data);

        let cid = store.put(&data).expect("failed to put large data");
        let retrieved = store
            .get(&cid)
            .expect("failed to get large data")
            .expect("data not found");

        assert_eq!(retrieved, data);
    }

    #[test]
    fn test_get_nonexistent() {
        let (_dir, store) = create_test_store();

        // Create a random CID that shouldn't exist in the store
        let random_data = rand::thread_rng().next_u64().to_be_bytes();
        let hash = Code::Sha2_256.digest(&random_data);
        let cid = Cid::new_v1(0x55, hash);

        let result = store.get(&cid).expect("get should not fail");
        assert!(result.is_none());
    }
}
