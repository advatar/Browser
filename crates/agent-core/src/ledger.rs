use crate::capabilities::CapabilityKind;
use crate::dom::{DomEvent, DomObservation};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sha2::{Digest, Sha256};

/// Entry stored in the agent ledger. Each entry is hashed independently and
/// contributes to the running root hash.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LedgerEntry {
    pub event: DomEvent,
    pub capability: CapabilityKind,
    pub message: String,
    pub hash: String,
}

/// Content-addressed ledger over agent actions.
#[derive(Debug, Default)]
pub struct AgentLedger {
    entries: Vec<LedgerEntry>,
}

impl AgentLedger {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn record(&mut self, capability: CapabilityKind, observation: &DomObservation) {
        let payload = json!({
            "sequence": observation.event.sequence,
            "timestamp_ms": observation.event.timestamp_ms,
            "capability": capability.as_str(),
            "action": observation.event.action,
            "message": observation.message,
        });

        let hash = hash_json(&payload);
        let entry = LedgerEntry {
            event: observation.event.clone(),
            capability,
            message: observation.message.clone(),
            hash,
        };
        self.entries.push(entry);
    }

    pub fn entries(&self) -> &[LedgerEntry] {
        &self.entries
    }

    pub fn root_hash(&self) -> Option<String> {
        compute_root_hash(&self.entries)
    }

    pub fn compute_root_snapshot(entries: &[LedgerEntry]) -> Option<String> {
        compute_root_hash(entries)
    }
}

fn compute_root_hash(entries: &[LedgerEntry]) -> Option<String> {
    if entries.is_empty() {
        return None;
    }

    let mut digest = Sha256::new();
    digest.update(b"agent-ledger-v1");
    for entry in entries {
        digest.update(entry.hash.as_bytes());
    }
    Some(hex::encode(digest.finalize()))
}

fn hash_json(value: &serde_json::Value) -> String {
    let mut sha = Sha256::new();
    let serialized =
        serde_json::to_vec(value).expect("ledger entry serialization should never fail");
    sha.update(serialized);
    hex::encode(sha.finalize())
}
