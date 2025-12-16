use crate::foundation::FoundationModelOptions;
use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct LanguageModelUsage {
    pub prompt_tokens: Option<u32>,
    pub completion_tokens: Option<u32>,
    pub total_tokens: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LanguageModelResponse {
    pub text: String,
    pub usage: LanguageModelUsage,
}

impl LanguageModelResponse {
    pub fn new(text: String) -> Self {
        Self {
            text,
            usage: LanguageModelUsage::default(),
        }
    }
}

#[async_trait]
pub trait LanguageModelClient: Send + Sync {
    async fn complete(
        &self,
        prompt: &str,
        options: &FoundationModelOptions,
    ) -> Result<LanguageModelResponse>;
}
