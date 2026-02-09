//! IPFS repository management.

use crate::ipfs::{Block, Error, Result};
use cid::Cid;
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::RwLock,
};

/// In-memory block store implementation.
#[derive(Debug, Default)]
struct InMemoryBlockStore {
    blocks: RwLock<HashMap<Cid, Vec<u8>>>,
}

impl InMemoryBlockStore {
    fn new() -> Self {
        Self {
            blocks: RwLock::new(HashMap::new()),
        }
    }

    fn get(&self, cid: &Cid) -> Result<Option<Vec<u8>>> {
        let blocks = self
            .blocks
            .read()
            .map_err(|_| Error::Other("lock poisoned".into()))?;
        Ok(blocks.get(cid).cloned())
    }

    fn put(&self, cid: Cid, data: Vec<u8>) -> Result<()> {
        let mut blocks = self
            .blocks
            .write()
            .map_err(|_| Error::Other("lock poisoned".into()))?;
        blocks.insert(cid, data);
        Ok(())
    }

    fn has(&self, cid: &Cid) -> Result<bool> {
        let blocks = self
            .blocks
            .read()
            .map_err(|_| Error::Other("lock poisoned".into()))?;
        Ok(blocks.contains_key(cid))
    }
}

/// IPFS repository implementation.
pub struct Repo {
    /// Path to the repository
    path: PathBuf,
    /// In-memory block store
    block_store: InMemoryBlockStore,
}

impl Repo {
    /// Create a new repository at the given path.
    pub fn new<P: AsRef<Path>>(path: P) -> Result<Self> {
        let path = path.as_ref().to_path_buf();

        // Create repository directory if it doesn't exist
        if !path.exists() {
            std::fs::create_dir_all(&path)?;
        }
        // Ensure blocks directory exists
        let blocks_dir = path.join("blocks");
        if !blocks_dir.exists() {
            std::fs::create_dir_all(&blocks_dir)?;
        }

        Ok(Self {
            path,
            block_store: InMemoryBlockStore::new(),
        })
    }

    fn blocks_dir(&self) -> PathBuf {
        self.path.join("blocks")
    }

    fn block_path(&self, cid: &Cid) -> PathBuf {
        self.blocks_dir().join(cid.to_string())
    }

    /// Get a block from the repository.
    pub fn get_block(&self, cid: &Cid) -> Result<Option<Block>> {
        // First try memory store
        if let Some(data) = self.block_store.get(cid)? {
            return Ok(Some(Block::with_cid(cid.clone(), data)));
        }

        // Fall back to disk storage
        let path = self.block_path(cid);
        if !path.exists() {
            return Ok(None);
        }

        let data = std::fs::read(&path)?;
        self.block_store.put(cid.clone(), data.clone())?;
        Ok(Some(Block::with_cid(cid.clone(), data)))
    }

    /// Put a block into the repository.
    pub fn put_block(&self, block: Block) -> Result<()> {
        let cid = block.cid().clone();
        let data = block.into_data();
        self.block_store.put(cid.clone(), data.clone())?;

        let path = self.block_path(&cid);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        // Write atomically to avoid partial data on crash
        let tmp_path = path.with_extension("tmp");
        std::fs::write(&tmp_path, &data)?;
        std::fs::rename(&tmp_path, &path)?;
        Ok(())
    }

    /// Check if a block exists in the repository.
    pub fn has_block(&self, cid: &Cid) -> Result<bool> {
        // Check memory store first
        if self.block_store.has(cid)? {
            return Ok(true);
        }

        // Check disk storage
        Ok(self.block_path(cid).exists())
    }

    /// Get the path to the repository.
    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_repo_creation() -> Result<()> {
        let temp_dir = tempdir()?;
        let repo = Repo::new(temp_dir.path())?;
        assert!(repo.path().exists());
        Ok(())
    }

    #[test]
    fn test_block_storage() -> Result<()> {
        let temp_dir = tempdir()?;
        let repo = Repo::new(temp_dir.path())?;

        // Create a test block
        let data = b"test data".to_vec();
        let block = Block::new(data.clone());
        let cid = block.cid().clone();

        // Test block storage and retrieval
        assert!(!repo.has_block(&cid)?);
        repo.put_block(block)?;
        assert!(repo.has_block(&cid)?);

        if let Some(retrieved_block) = repo.get_block(&cid)? {
            assert_eq!(retrieved_block.data(), data.as_slice());
        } else {
            panic!("Block not found in repository");
        }

        // Verify persistence across repository instances
        let repo_reopen = Repo::new(temp_dir.path())?;
        assert!(repo_reopen.has_block(&cid)?);
        if let Some(retrieved_block) = repo_reopen.get_block(&cid)? {
            assert_eq!(retrieved_block.data(), data.as_slice());
        } else {
            panic!("Block not found after reopening repository");
        }

        Ok(())
    }
}
