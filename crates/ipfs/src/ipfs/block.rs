//! Block data structure for IPFS.

use cid::Cid;
use std::fmt;

/// A block of data with an associated CID.
#[derive(Clone, PartialEq, Eq)]
pub struct Block {
    cid: Cid,
    data: Vec<u8>,
}

impl Block {
    /// Create a new block with the given data.
    /// The CID will be automatically generated using SHA-256.
    pub fn new(data: Vec<u8>) -> Self {
        use cid::multihash::{Code, MultihashDigest};
        
        let hash = Code::Sha2_256.digest(&data);
        let cid = Cid::new_v1(cid::Codec::Raw, hash);
        
        Self { cid, data }
    }
    
    /// Create a block with a specific CID and data.
    /// 
    /// # Safety
    /// The caller must ensure that the CID actually corresponds to the hash of the data.
    /// Using incorrect CIDs can lead to data corruption.
    pub fn with_cid(cid: Cid, data: Vec<u8>) -> Self {
        Self { cid, data }
    }
    
    /// Get a reference to the block's CID.
    pub fn cid(&self) -> &Cid {
        &self.cid
    }
    
    /// Get a reference to the block's data.
    pub fn data(&self) -> &[u8] {
        &self.data
    }
    
    /// Consume the block and return its data.
    pub fn into_data(self) -> Vec<u8> {
        self.data
    }
    
    /// Get the size of the block's data in bytes.
    pub fn size(&self) -> usize {
        self.data.len()
    }
}

impl fmt::Debug for Block {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Block")
            .field("cid", &self.cid)
            .field("size", &self.size())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_block_creation() {
        let data = b"hello world".to_vec();
        let block = Block::new(data.clone());
        
        assert_eq!(block.data(), data.as_slice());
        assert_eq!(block.size(), data.len());
        assert_eq!(block.into_data(), data);
    }
    
    #[test]
    fn test_block_with_cid() {
        let cid = Cid::try_from("bafkreigh2akiscaildcqabsyg3dfr6chu3fgpregiymsck7e7aqa4s52zy").unwrap();
        let data = b"hello world".to_vec();
        let block = Block::with_cid(cid.clone(), data.clone());
        
        assert_eq!(block.cid(), &cid);
        assert_eq!(block.data(), data.as_slice());
    }
}
