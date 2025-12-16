use std::sync::Arc;

use ai_agent::{FoundationModelClient, LanguageModelClient};
use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum Provider {
    #[serde(rename = "apple_foundation")]
    AppleFoundation,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoutingPolicy {
    #[serde(default = "RoutingPolicy::default_prefer_local")]
    pub prefer_local: bool,
    #[serde(default)]
    pub no_egress: bool,
    #[serde(default)]
    pub force_provider: Option<Provider>,
}

impl RoutingPolicy {
    fn default_prefer_local() -> bool {
        true
    }
}

impl Default for RoutingPolicy {
    fn default() -> Self {
        Self {
            prefer_local: true,
            no_egress: false,
            force_provider: None,
        }
    }
}

#[derive(Debug, Error)]
pub enum RouterError {
    #[error("requested provider is unavailable: {0:?}")]
    ProviderUnavailable(Provider),
}

#[derive(Clone)]
pub struct LlmRouter {
    apple_client: Arc<FoundationModelClient>,
}

impl LlmRouter {
    pub fn new() -> Result<Self> {
        let client = FoundationModelClient::detect()?;
        Ok(Self {
            apple_client: Arc::new(client),
        })
    }

    pub fn route(&self, policy: RoutingPolicy) -> Result<Arc<dyn LanguageModelClient>> {
        let provider = policy.force_provider.unwrap_or(Provider::AppleFoundation);

        match provider {
            Provider::AppleFoundation => {
                if policy.no_egress && !self.apple_client.is_available() {
                    return Err(anyhow!(RouterError::ProviderUnavailable(
                        Provider::AppleFoundation
                    )));
                }
                Ok(self.apple_client.clone())
            }
        }
    }

    pub fn is_provider_available(&self, provider: Provider) -> bool {
        match provider {
            Provider::AppleFoundation => self.apple_client.is_available(),
        }
    }

    pub fn local_available(&self) -> bool {
        self.is_provider_available(Provider::AppleFoundation)
    }
}
