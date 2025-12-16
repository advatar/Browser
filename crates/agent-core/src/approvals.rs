use async_trait::async_trait;
use serde_json::Value;

use crate::capabilities::CapabilityKind;

/// Trait implemented by host applications to prompt the user before executing
/// high-impact capabilities.
#[async_trait]
pub trait ApprovalHandler: Send + Sync {
    async fn request_approval(
        &self,
        capability: &CapabilityKind,
        payload: &Value,
    ) -> anyhow::Result<bool>;
}
