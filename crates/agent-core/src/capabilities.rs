use std::collections::HashMap;
use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Known capability kinds that the agent runtime can enforce.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum CapabilityKind {
    #[serde(rename = "click")]
    Click,
    #[serde(rename = "scroll")]
    Scroll,
    #[serde(rename = "type")]
    Type,
    #[serde(rename = "navigate")]
    Navigate,
    #[serde(rename = "email:send")]
    EmailSend,
    #[serde(rename = "wallet:spend")]
    WalletSpend,
}

impl CapabilityKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Click => "click",
            Self::Scroll => "scroll",
            Self::Type => "type",
            Self::Navigate => "navigate",
            Self::EmailSend => "email:send",
            Self::WalletSpend => "wallet:spend",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "click" => Some(Self::Click),
            "scroll" => Some(Self::Scroll),
            "type" => Some(Self::Type),
            "navigate" => Some(Self::Navigate),
            "email:send" | "email" => Some(Self::EmailSend),
            "wallet:spend" => Some(Self::WalletSpend),
            _ => None,
        }
    }
}

impl FromStr for CapabilityKind {
    type Err = ();

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::parse(value).ok_or(())
    }
}

impl fmt::Display for CapabilityKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

/// Constraint for a capability grant.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct CapabilityLimit {
    /// Maximum number of invocations allowed per agent run.
    pub max_calls_per_run: Option<u32>,
}

impl CapabilityLimit {
    pub fn unlimited() -> Self {
        Self {
            max_calls_per_run: None,
        }
    }

    pub fn limited(max_calls: u32) -> Self {
        Self {
            max_calls_per_run: Some(max_calls),
        }
    }
}

impl Default for CapabilityLimit {
    fn default() -> Self {
        Self::unlimited()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CapabilityToken {
    limit: CapabilityLimit,
    consumed: u32,
    revoked: bool,
}

impl CapabilityToken {
    fn new(limit: CapabilityLimit) -> Self {
        Self {
            limit,
            consumed: 0,
            revoked: false,
        }
    }

    fn consume(&mut self, kind: &CapabilityKind) -> Result<ConsumeOutcome, CapabilityError> {
        if self.revoked {
            return Err(CapabilityError::Revoked {
                capability: kind.clone(),
            });
        }

        if let Some(max) = self.limit.max_calls_per_run {
            if self.consumed >= max {
                return Err(CapabilityError::Exhausted {
                    capability: kind.clone(),
                });
            }
        }

        self.consumed = self.consumed.saturating_add(1);
        let remaining = self
            .limit
            .max_calls_per_run
            .map(|max| max.saturating_sub(self.consumed));
        Ok(ConsumeOutcome { remaining })
    }

    fn revoke(&mut self) {
        self.revoked = true;
    }

    fn remaining(&self) -> Option<u32> {
        self.limit
            .max_calls_per_run
            .map(|max| max.saturating_sub(self.consumed))
    }
}

/// Result of successfully consuming a capability allowance.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConsumeOutcome {
    pub remaining: Option<u32>,
}

/// Registry that stores capability tokens and tracks consumption.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct CapabilityRegistry {
    grants: HashMap<CapabilityKind, CapabilityToken>,
}

impl CapabilityRegistry {
    pub fn new() -> Self {
        Self {
            grants: HashMap::new(),
        }
    }

    pub fn with_browser_defaults() -> Self {
        let mut registry = Self::new();
        registry.grant(CapabilityKind::Click, CapabilityLimit::unlimited());
        registry.grant(CapabilityKind::Scroll, CapabilityLimit::unlimited());
        registry.grant(CapabilityKind::Type, CapabilityLimit::unlimited());
        registry.grant(CapabilityKind::Navigate, CapabilityLimit::unlimited());
        registry.grant(CapabilityKind::EmailSend, CapabilityLimit::limited(3));
        registry.grant(CapabilityKind::WalletSpend, CapabilityLimit::limited(3));
        registry
    }

    pub fn grant(&mut self, kind: CapabilityKind, limit: CapabilityLimit) {
        self.grants.insert(kind, CapabilityToken::new(limit));
    }

    pub fn revoke(&mut self, kind: CapabilityKind) {
        if let Some(token) = self.grants.get_mut(&kind) {
            token.revoke();
        }
    }

    pub fn consume(&mut self, kind: CapabilityKind) -> Result<ConsumeOutcome, CapabilityError> {
        let Some(token) = self.grants.get_mut(&kind) else {
            return Err(CapabilityError::NotGranted { capability: kind });
        };
        token.consume(&kind)
    }

    pub fn remaining(&self, kind: CapabilityKind) -> Option<u32> {
        self.grants.get(&kind).and_then(|token| token.remaining())
    }

    pub fn snapshot(&self) -> HashMap<CapabilityKind, Option<u32>> {
        self.grants
            .iter()
            .map(|(kind, token)| (kind.clone(), token.remaining()))
            .collect()
    }
}

/// Error raised when attempting to use a capability that is not available.
#[derive(Debug, Error)]
pub enum CapabilityError {
    #[error("capability {capability} not granted")]
    NotGranted { capability: CapabilityKind },
    #[error("capability {capability} has been revoked")]
    Revoked { capability: CapabilityKind },
    #[error("capability {capability} quota exhausted")]
    Exhausted { capability: CapabilityKind },
}
