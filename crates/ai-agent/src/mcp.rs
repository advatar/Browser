use anyhow::Result;
use async_trait::async_trait;
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpToolDescription {
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub input_schema: Value,
    #[serde(default)]
    pub metadata: IndexMap<String, Value>,
}

impl McpToolDescription {
    pub fn new(
        name: impl Into<String>,
        description: impl Into<String>,
        input_schema: Value,
    ) -> Self {
        Self {
            name: name.into(),
            description: description.into(),
            input_schema,
            metadata: IndexMap::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpToolResult {
    pub content: Value,
    #[serde(default)]
    pub metadata: IndexMap<String, Value>,
}

#[derive(Debug, Error)]
pub enum McpToolError {
    #[error("tool invocation failed: {0}")]
    Invocation(String),
    #[error("tool rejected input: {0}")]
    InvalidInput(String),
}

pub type McpToolResultT = Result<McpToolResult, McpToolError>;

#[async_trait]
pub trait McpTool: Send + Sync {
    fn description(&self) -> &McpToolDescription;
    async fn invoke(&self, args: Value) -> McpToolResultT;
}
