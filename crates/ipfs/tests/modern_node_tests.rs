use anyhow::Result;
use ipfs::{Block, BlockStore, Config, Node};
use tokio::time::{sleep, Duration};

#[tokio::test]
async fn test_listen_addrs() -> Result<()> {
    let config = Config::default();
    let node = Node::new(config).await?;

    // Give the underlying node a brief moment to start listeners
    sleep(Duration::from_millis(200)).await;

    let addrs = node.listen_addrs().await?;
    // It's acceptable for this to be empty depending on transport/config
    // The important part is that the call succeeds and returns a Vec
    assert!(addrs.iter().all(|a| !a.to_string().is_empty()));

    Ok(())
}

#[tokio::test]
async fn test_blockstore_put_get() -> Result<()> {
    let config = Config::default();
    let mut node = Node::new(config).await?;

    let data = b"modern api block data".to_vec();
    let block = Block::new(data.clone());
    let cid = block.cid().clone();

    // Initially should not have the block
    assert!(!node.has_block(&cid).await?);

    // Put and then get the block
    node.put_block(block).await?;
    assert!(node.has_block(&cid).await?);

    let maybe_block = node.get_block(&cid).await?;
    assert!(maybe_block.is_some());
    let retrieved = maybe_block.unwrap();
    assert_eq!(retrieved.data(), data.as_slice());

    Ok(())
}
