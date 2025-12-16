use crate::language_model::{LanguageModelClient, LanguageModelResponse};
use anyhow::{anyhow, Result};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FoundationModelOptions {
    pub temperature: f32,
    pub max_tokens: Option<u32>,
    pub system_prompt: Option<String>,
}

impl Default for FoundationModelOptions {
    fn default() -> Self {
        Self {
            temperature: 0.6,
            max_tokens: Some(512),
            system_prompt: None,
        }
    }
}

pub enum PlatformModelClient {
    #[cfg(target_os = "macos")]
    Mac(MacFoundationClient),
    Unsupported,
}

impl PlatformModelClient {
    pub fn detect() -> Result<Self> {
        #[cfg(target_os = "macos")]
        {
            return Ok(PlatformModelClient::Mac(MacFoundationClient::new()?));
        }

        #[cfg(not(target_os = "macos"))]
        {
            Ok(PlatformModelClient::Unsupported)
        }
    }
}

pub struct FoundationModelClient {
    inner: PlatformModelClient,
}

impl FoundationModelClient {
    pub fn detect() -> Result<Self> {
        let inner = PlatformModelClient::detect()?;
        Ok(Self { inner })
    }

    pub fn is_available(&self) -> bool {
        !matches!(self.inner, PlatformModelClient::Unsupported)
    }
}

#[async_trait]
impl LanguageModelClient for FoundationModelClient {
    async fn complete(
        &self,
        prompt: &str,
        options: &FoundationModelOptions,
    ) -> Result<LanguageModelResponse> {
        match &self.inner {
            #[cfg(target_os = "macos")]
            PlatformModelClient::Mac(client) => client.complete(prompt, options).await,
            PlatformModelClient::Unsupported => Err(anyhow!(
                "No compatible foundation model runtime available on this platform"
            )),
        }
    }
}

#[cfg(target_os = "macos")]
mod foundation_macos;
#[cfg(target_os = "macos")]
pub use foundation_macos::MacFoundationClient;
