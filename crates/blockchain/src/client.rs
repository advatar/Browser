use anyhow::{Result, anyhow};
use sp_core::{
    Encode,
    crypto::{Pair, Ss58Codec},
    sr25519::Pair as Sr25519Pair,
};
use sp_runtime::{
    OpaqueExtrinsic,
    generic::BlockId,
    traits::{Block as BlockT, Header as HeaderT, NumberFor},
};
use std::sync::Arc;
use substrate_subxt::{
    Client, ClientBuilder, DefaultConfig, DefaultExtra, PairSigner, PolkadotExtrinsicParams,
};

/// Configuration for the Substrate client
#[derive(Debug, Clone)]
pub struct SubstrateConfig {
    /// WebSocket URL of the Substrate node
    pub node_url: String,
    /// Optional custom types for the chain
    pub custom_types: Option<serde_json::Value>,
    /// Maximum number of concurrent requests
    pub max_concurrent_requests: usize,
    /// Request timeout in seconds
    pub request_timeout_secs: u64,
}

impl Default for SubstrateConfig {
    fn default() -> Self {
        Self {
            node_url: "ws://127.0.0.1:9944".into(),
            custom_types: None,
            max_concurrent_requests: 5,
            request_timeout_secs: 30,
        }
    }
}

/// A client for interacting with a Substrate-based blockchain
pub struct SubstrateClient<C = Client<DefaultConfig>>
where
    C: Send + Sync + 'static,
{
    /// The underlying Substrate client
    client: Arc<C>,
    /// The configuration used to create this client
    config: SubstrateConfig,
}

impl<C> SubstrateClient<C>
where
    C: Send + Sync + 'static,
{
    /// Create a new Substrate client with the given configuration
    pub async fn new(config: SubstrateConfig) -> Result<Self> {
        let client = ClientBuilder::new()
            .set_url(&config.node_url)
            .build()
            .await
            .map_err(|e| anyhow!("Failed to create Substrate client: {}", e))?;

        Ok(Self {
            client: Arc::new(client),
            config,
        })
    }

    /// Get a reference to the underlying client
    pub fn inner(&self) -> &C {
        &self.client
    }

    /// Get a clone of the client's Arc
    pub fn clone_inner(&self) -> Arc<C> {
        self.client.clone()
    }
}

/// A type alias for the default Substrate client
type DefaultSubstrateClient = SubstrateClient<Client<DefaultConfig>>;

/// A client for interacting with a Substrate-based blockchain with default configuration
pub type Client = DefaultSubstrateClient;

/// A signer that can be used to sign transactions
pub type SubstrateSigner = PairSigner<DefaultConfig, Sr25519Pair>;

/// Create a new signer from a seed phrase
pub fn create_signer(seed: &str) -> Result<SubstrateSigner> {
    let pair = Sr25519Pair::from_string(seed, None)
        .map_err(|e| anyhow::anyhow!("Failed to create keypair from seed: {}", e))?;

    Ok(PairSigner::new(pair))
}

#[cfg(test)]
mod tests {
    use super::*;
    use sp_keyring::AccountKeyring;
    use std::time::Duration;

    // Helper function to get a test config
    fn test_config() -> SubstrateConfig {
        SubstrateConfig {
            node_url: "ws://127.0.0.1:9944".into(),
            ..Default::default()
        }
    }

    #[tokio::test]
    #[ignore = "requires a running Substrate node"]
    async fn test_client_connection() -> Result<()> {
        let config = test_config();
        let client = SubstrateClient::new(config).await?;

        // Test that we can get the genesis hash
        let _genesis_hash = client
            .client
            .rpc()
            .genesis_hash()
            .await
            .map_err(|e| anyhow::anyhow!("Failed to get genesis hash: {}", e))?;

        Ok(())
    }

    #[test]
    fn test_create_signer() -> Result<()> {
        // Test with Alice's seed
        let alice = AccountKeyring::Alice.to_seed();
        let signer = create_signer(&alice)?;

        // Check that the signer has the expected address
        let expected_address = AccountKeyring::Alice.to_account_id();
        assert_eq!(signer.account_id(), &expected_address);

        Ok(())
    }
}
