#![cfg(feature = "substrate")]

//! Test utilities for the blockchain crate

use anyhow::{Context, Result, anyhow};
use std::{
    process::{Child, Command, Stdio},
    sync::Once,
    time::{Duration, Instant},
};
use tokio::time;

/// Global initialization for tests
static INIT: Once = Once::new();

/// Test configuration
pub struct TestConfig {
    /// Whether to start a local node for testing
    pub start_local_node: bool,
    /// URL of the Substrate node
    pub node_url: String,
    /// Path to the Substrate binary
    pub substrate_bin: String,
    /// Test timeout
    pub timeout: Duration,
}

impl Default for TestConfig {
    fn default() -> Self {
        Self {
            start_local_node: true,
            node_url: "ws://127.0.0.1:9944".to_string(),
            substrate_bin: "substrate".to_string(),
            timeout: Duration::from_secs(30),
        }
    }
}

/// A handle to a running Substrate node
pub struct TestNode {
    process: Option<Child>,
    config: TestConfig,
}

impl TestNode {
    /// Create a new test node with the given configuration
    pub fn new(config: TestConfig) -> Self {
        // Initialize logging and other one-time setup
        INIT.call_once(|| {
            // Initialize logging
            let _ = env_logger::builder()
                .is_test(true)
                .filter_level(log::LevelFilter::Info)
                .try_init();
        });

        Self {
            process: None,
            config,
        }
    }

    /// Start the test node
    pub fn start(&mut self) -> Result<()> {
        if !self.config.start_local_node {
            log::info!("Using existing node at {}", self.config.node_url);
            return Ok(());
        }

        log::info!("Starting local Substrate node...");

        // Start the node with dev mode and temporary storage
        let child = Command::new(&self.config.substrate_bin)
            .args([
                "--dev",
                "--tmp",
                "--ws-port",
                &self.config.node_url.split(':').nth(2).unwrap_or("9944"),
                "--rpc-cors",
                "all",
                "--alice",
            ])
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn()
            .context("Failed to start Substrate node")?;

        self.process = Some(child);

        // Wait for the node to be ready
        self.wait_for_rpc()?;

        Ok(())
    }

    /// Wait for the node's RPC server to be ready
    fn wait_for_rpc(&self) -> Result<()> {
        use substrate_subxt::{Client, DefaultNodeRuntime};
        use tokio::runtime::Runtime;

        let start = Instant::now();
        let url = self.config.node_url.clone();
        let timeout = self.config.timeout;

        Runtime::new()?.block_on(async move {
            loop {
                match Client::<DefaultNodeRuntime>::from_url(&url).await {
                    Ok(_) => {
                        log::info!("Connected to Substrate node at {}", url);
                        return Ok(());
                    }
                    Err(e) => {
                        if start.elapsed() > timeout {
                            return Err(anyhow!("Timeout waiting for node RPC: {}", e));
                        }
                        time::sleep(Duration::from_millis(100)).await;
                    }
                }
            }
        })?;

        Ok(())
    }
}

impl Drop for TestNode {
    fn drop(&mut self) {
        if let Some(mut child) = self.process.take() {
            if let Err(e) = child.kill() {
                log::error!("Failed to kill Substrate node: {}", e);
            }
        }
    }
}

/// Test helper to run a test with a local node
pub fn with_test_node<F>(test: F) -> Result<()>
where
    F: FnOnce(&TestConfig) -> Result<()>,
{
    let config = TestConfig::default();
    let mut node = TestNode::new(config.clone());

    if config.start_local_node {
        node.start()?;
        // Give the node some time to initialize
        std::thread::sleep(Duration::from_secs(2));
    }

    test(&config)
}

/// Test helper to run an async test with a local node
pub async fn with_test_node_async<F, Fut>(test: F) -> Result<()>
where
    F: FnOnce(TestConfig) -> Fut,
    Fut: std::future::Future<Output = Result<()>>,
{
    let config = TestConfig::default();
    let mut node = TestNode::new(config.clone());

    if config.start_local_node {
        node.start()?;
        // Give the node some time to initialize
        tokio::time::sleep(Duration::from_secs(2)).await;
    }

    test(config).await
}
