use anyhow::{anyhow, Result};
use blockchain::{KeyPair, KeyType, Wallet};
use hex;
use keyring::Entry;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

/// Identifies who owns a wallet profile.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", content = "id")]
pub enum WalletOwner {
    User,
    Agent(String),
}

impl WalletOwner {
    fn label(&self) -> String {
        match self {
            WalletOwner::User => "User".to_string(),
            WalletOwner::Agent(id) => format!("Agent {}", id),
        }
    }

    fn key(&self) -> String {
        match self {
            WalletOwner::User => "user".to_string(),
            WalletOwner::Agent(id) => format!("agent:{id}"),
        }
    }
}

/// Simple spend policy used to protect a wallet.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WalletPolicy {
    /// Maximum amount allowed per transaction (smallest unit for the chain).
    pub max_per_tx: Option<u128>,
    /// Maximum cumulative spend allowed per 24h window.
    pub daily_limit: Option<u128>,
    /// Whether user approval is required even when limits are not exceeded.
    pub require_approval: bool,
    /// Allowed chains (case-insensitive). If empty, all chains are allowed.
    pub allowed_chains: Vec<String>,
}

impl Default for WalletPolicy {
    fn default() -> Self {
        Self {
            max_per_tx: None,
            daily_limit: None,
            require_approval: true,
            allowed_chains: Vec::new(),
        }
    }
}

/// Snapshot of a wallet profile exposed to the UI/agent runtime.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletSnapshot {
    pub id: String,
    pub owner: WalletOwner,
    pub label: String,
    pub address: Option<String>,
    pub policy: WalletPolicy,
    pub is_initialized: bool,
    pub remaining_daily: Option<u128>,
}

/// Result of a spend policy check.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpendDecision {
    pub permitted: bool,
    pub reason: Option<String>,
    pub address: Option<String>,
    pub policy: WalletPolicy,
    pub remaining_daily: Option<u128>,
    pub requires_approval: bool,
}

struct WalletProfile {
    id: String,
    owner: WalletOwner,
    label: String,
    wallet: Wallet,
    policy: WalletPolicy,
    daily_spent: u128,
    last_reset: SystemTime,
    seed: [u8; 32],
}

impl WalletProfile {
    fn new(owner: WalletOwner, label: String, policy: WalletPolicy) -> Result<Self> {
        let seed = generate_seed()?;
        let mut profile = Self::from_seed(owner, label, policy, &seed)?;
        // Persist the seed to keyring for later restores.
        // Disabled in tests (and optionally at runtime) because it can prompt/hang and isn't hermetic.
        if keyring_enabled() {
            let entry = keyring_entry(&profile.id)?;
            entry.set_password(&hex::encode(seed))?;
        }
        profile.ensure_default_key()?;
        Ok(profile)
    }

    fn from_seed(owner: WalletOwner, label: String, policy: WalletPolicy, seed: &[u8]) -> Result<Self> {
        let mut profile = Self {
            id: owner.key(),
            owner,
            label,
            wallet: Wallet::new(),
            policy,
            daily_spent: 0,
            last_reset: SystemTime::now(),
            seed: {
                let mut buf = [0u8; 32];
                let copy_len = seed.len().min(32);
                buf[..copy_len].copy_from_slice(&seed[..copy_len]);
                buf
            },
        };
        profile.ensure_default_key()?;
        Ok(profile)
    }

    fn ensure_default_key(&mut self) -> Result<()> {
        if self.wallet.default_key().is_some() {
            return Ok(());
        }

        let pair = KeyPair::from_seed(&self.seed, KeyType::Ecdsa)
            .map_err(|e| anyhow!("failed to create key: {}", e))?;

        self.wallet
            .add_key("default", pair)
            .map_err(|e| anyhow!("{}", e))?;
        self.wallet
            .set_default_key("default")
            .map_err(|e| anyhow!("{}", e))?;
        Ok(())
    }

    fn regenerate_default_key(&mut self) -> Result<()> {
        self.wallet = Wallet::new();
        self.seed = generate_seed()?;
        let pair = KeyPair::from_seed(&self.seed, KeyType::Ecdsa)
            .map_err(|e| anyhow!("failed to create key: {}", e))?;
        self.wallet
            .add_key("default", pair)
            .map_err(|e| anyhow!("{}", e))?;
        self.wallet
            .set_default_key("default")
            .map_err(|e| anyhow!("{}", e))?;
        // Update keyring with the new seed (disabled in tests; see comment in `new`).
        if keyring_enabled() {
            let entry = keyring_entry(&self.id)?;
            entry.set_password(&hex::encode(self.seed))?;
        }
        Ok(())
    }

    fn clear_wallet(&mut self) {
        self.wallet = Wallet::new();
    }

    fn reset_window_if_needed(&mut self) {
        match self.last_reset.elapsed() {
            Ok(elapsed) => {
                if elapsed >= Duration::from_secs(24 * 60 * 60) {
                    self.daily_spent = 0;
                    self.last_reset = SystemTime::now();
                }
            }
            Err(_) => {
                self.daily_spent = 0;
                self.last_reset = SystemTime::now();
            }
        }
    }

    fn address(&self) -> Option<String> {
        self.wallet.default_key().map(|pair| pair.to_ss58())
    }

    fn remaining_daily(&self) -> Option<u128> {
        self.policy
            .daily_limit
            .map(|limit| limit.saturating_sub(self.daily_spent))
    }

    fn snapshot(&self) -> WalletSnapshot {
        WalletSnapshot {
            id: self.id.clone(),
            owner: self.owner.clone(),
            label: self.label.clone(),
            address: self.address(),
            policy: self.policy.clone(),
            is_initialized: self.wallet.default_key().is_some(),
            remaining_daily: self.remaining_daily(),
        }
    }

    fn evaluate_spend(&mut self, amount: u128, chain: &str) -> SpendDecision {
        self.reset_window_if_needed();

        let mut permitted = true;
        let mut reason = None;

        if !self.policy.allowed_chains.is_empty()
            && !self
                .policy
                .allowed_chains
                .iter()
                .any(|c| c.eq_ignore_ascii_case(chain))
        {
            permitted = false;
            reason = Some(format!(
                "chain '{}' not allowed by policy",
                chain.to_string()
            ));
        }

        if permitted {
            if let Some(max) = self.policy.max_per_tx {
                if amount > max {
                    permitted = false;
                    reason = Some(format!(
                        "amount {} exceeds per-tx limit of {}",
                        amount, max
                    ));
                }
            }
        }

        if permitted {
            if let Some(limit) = self.policy.daily_limit {
                if self.daily_spent.saturating_add(amount) > limit {
                    permitted = false;
                    reason = Some(format!(
                        "daily limit exceeded: attempted {} with {} already spent",
                        amount, self.daily_spent
                    ));
                }
            }
        }

        if permitted {
            self.daily_spent = self.daily_spent.saturating_add(amount);
        }

        SpendDecision {
            permitted,
            reason,
            address: self.address(),
            policy: self.policy.clone(),
            remaining_daily: self.remaining_daily(),
            requires_approval: self.policy.require_approval,
        }
    }

    fn set_policy(&mut self, policy: WalletPolicy) {
        self.policy = policy;
        self.reset_window_if_needed();
    }
}

/// In-memory wallet store that tracks user and agent wallets with policies.
pub struct WalletStore {
    profiles: HashMap<String, WalletProfile>,
    default_user: String,
    storage_path: PathBuf,
}

impl WalletStore {
    pub fn new() -> Result<Self> {
        let storage_path = default_storage_path()?;
        Self::new_with_storage_path(storage_path)
    }

    pub fn new_with_storage_path(storage_path: PathBuf) -> Result<Self> {
        let mut store = Self {
            profiles: HashMap::new(),
            default_user: "user".to_string(),
            storage_path,
        };

        store.load_or_init()?;
        Ok(store)
    }

    pub fn ensure_user_profile(&mut self) -> Result<WalletSnapshot> {
        let key = self.default_user.clone();
        if !self.profiles.contains_key(&key) {
            let profile = WalletProfile::new(WalletOwner::User, "User Wallet".to_string(), WalletPolicy::default())?;
            self.profiles.insert(key.clone(), profile);
            self.persist()?;
        }
        Ok(self
            .profiles
            .get(&key)
            .expect("user wallet profile should exist")
            .snapshot())
    }

    pub fn ensure_agent_profile(&mut self, agent_id: &str) -> Result<WalletSnapshot> {
        let owner = WalletOwner::Agent(agent_id.to_string());
        let key = owner.key();
        if !self.profiles.contains_key(&key) {
            let profile = WalletProfile::new(owner.clone(), owner.label(), WalletPolicy::default())?;
            self.profiles.insert(key.clone(), profile);
            self.persist()?;
        }

        Ok(self
            .profiles
            .get(&key)
            .expect("agent wallet profile should exist")
            .snapshot())
    }

    pub fn regenerate_wallet(&mut self, owner: WalletOwner) -> Result<WalletSnapshot> {
        let key = owner.key();
        let snapshot = {
            let profile = self
                .profiles
                .get_mut(&key)
                .ok_or_else(|| anyhow!("wallet profile not found: {}", key))?;
            profile.regenerate_default_key()?;
            profile.snapshot()
        };
        self.persist()?;
        Ok(snapshot)
    }

    pub fn disconnect_wallet(&mut self, owner: WalletOwner) -> Result<()> {
        let key = owner.key();
        {
            let profile = self
                .profiles
                .get_mut(&key)
                .ok_or_else(|| anyhow!("wallet profile not found: {}", key))?;
            profile.clear_wallet();
        }
        self.persist()?;
        Ok(())
    }

    pub fn snapshot(&self, owner: &WalletOwner) -> Option<WalletSnapshot> {
        self.profiles.get(&owner.key()).map(|p| p.snapshot())
    }

    pub fn snapshot_by_id(&self, id: &str) -> Option<WalletSnapshot> {
        self.profiles.get(id).map(|p| p.snapshot())
    }

    pub fn set_policy(&mut self, owner: WalletOwner, policy: WalletPolicy) -> Result<WalletSnapshot> {
        let key = owner.key();
        let snapshot = {
            let profile = self
                .profiles
                .get_mut(&key)
                .ok_or_else(|| anyhow!("wallet profile not found: {}", key))?;
            profile.set_policy(policy);
            profile.snapshot()
        };
        self.persist()?;
        Ok(snapshot)
    }

    pub fn evaluate_spend(&mut self, owner: &WalletOwner, amount: u128, chain: &str) -> Result<SpendDecision> {
        let key = owner.key();
        let decision = {
            let profile = self
                .profiles
                .get_mut(&key)
                .ok_or_else(|| anyhow!("wallet profile not found: {}", key))?;
            profile.ensure_default_key()?;
            profile.evaluate_spend(amount, chain)
        };
        self.persist()?;
        Ok(decision)
    }

    pub fn sign_payload(&mut self, owner: &WalletOwner, payload: &[u8]) -> Result<(String, Vec<u8>)> {
        let key = owner.key();
        let (address, signature) = {
            let profile = self
                .profiles
                .get_mut(&key)
                .ok_or_else(|| anyhow!("wallet profile not found: {}", key))?;
            profile.ensure_default_key()?;
            let pair = profile
                .wallet
                .default_key()
                .ok_or_else(|| anyhow!("default key missing"))?;
            let signature = pair.sign(payload);
            let address = pair.to_ss58();
            (address, signature)
        };
        Ok((address, signature))
    }

    pub fn seed_for_owner(&mut self, owner: &WalletOwner) -> Result<([u8; 32], String)> {
        let key = owner.key();
        let (seed, addr) = {
            let profile = self
                .profiles
                .get_mut(&key)
                .ok_or_else(|| anyhow!("wallet profile not found: {}", key))?;
            profile.ensure_default_key()?;
            let addr = profile
                .wallet
                .default_key()
                .map(|p| p.to_ss58())
                .unwrap_or_default();
            (profile.seed, addr)
        };
        Ok((seed, addr))
    }

    fn persist(&self) -> Result<()> {
        let stored: Vec<StoredProfile> = self
            .profiles
            .values()
            .map(|p| StoredProfile {
                id: p.id.clone(),
                owner: p.owner.clone(),
                label: p.label.clone(),
                policy: p.policy.clone(),
            })
            .collect();

        if let Some(parent) = self.storage_path.parent() {
            fs::create_dir_all(parent)?;
        }

        let mut file = fs::File::create(&self.storage_path)?;
        let payload = serde_json::to_string_pretty(&stored)?;
        file.write_all(payload.as_bytes())?;

        // Persist seeds into keyring (disabled in tests; can prompt/hang and isn't hermetic).
        if keyring_enabled() {
            for profile in self.profiles.values() {
                let entry = keyring_entry(&profile.id)?;
                entry.set_password(&hex::encode(profile.seed))?;
            }
        }

        Ok(())
    }

    fn load_or_init(&mut self) -> Result<()> {
        if self.storage_path.exists() {
            let data = fs::read_to_string(&self.storage_path)?;
            let stored: Vec<StoredProfile> = serde_json::from_str(&data)?;
            for profile in stored {
                let seed = if keyring_enabled() {
                    match keyring_entry(&profile.id)?.get_password() {
                        Ok(secret) => hex::decode(secret)
                            .unwrap_or_else(|_| generate_seed().unwrap_or([0u8; 32]).to_vec()),
                        Err(_) => generate_seed()?.to_vec(),
                    }
                } else {
                    generate_seed()?.to_vec()
                };
                let mut wallet_profile = WalletProfile::from_seed(
                    profile.owner.clone(),
                    profile.label.clone(),
                    profile.policy.clone(),
                    &seed,
                )?;
                // ensure id stays consistent
                wallet_profile.id = profile.id.clone();
                self.profiles.insert(profile.id.clone(), wallet_profile);
            }
        }

        if !self.profiles.contains_key(&self.default_user) {
            let profile = WalletProfile::new(WalletOwner::User, "User Wallet".to_string(), WalletPolicy::default())?;
            self.profiles.insert(self.default_user.clone(), profile);
            self.persist()?;
        }

        Ok(())
    }
}

impl Default for WalletStore {
    fn default() -> Self {
        Self::new().unwrap_or_else(|_| Self {
            profiles: HashMap::new(),
            default_user: "user".to_string(),
            storage_path: default_storage_path().unwrap_or_else(|_| PathBuf::from("wallets.json")),
        })
    }
}

fn default_storage_path() -> Result<PathBuf> {
    let base = std::env::var_os("HOME")
        .map(PathBuf::from)
        .ok_or_else(|| anyhow!("HOME not set"))?;
    let mut path = base;
    path.push(".advatar");
    path.push("wallets.json");
    Ok(path)
}

fn keyring_entry(id: &str) -> Result<Entry> {
    Entry::new("advatar-browser-wallet", id).map_err(|e| anyhow!("keyring error: {}", e))
}

fn keyring_enabled() -> bool {
    if cfg!(test) {
        return false;
    }
    std::env::var_os("ADVATAR_DISABLE_KEYRING").is_none()
}

fn generate_seed() -> Result<[u8; 32]> {
    let mut seed = [0u8; 32];
    let mut rng = rand::rngs::OsRng;
    rng.fill_bytes(&mut seed);
    Ok(seed)
}

#[derive(Debug, Serialize, Deserialize)]
struct StoredProfile {
    id: String,
    owner: WalletOwner,
    label: String,
    policy: WalletPolicy,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_storage_path(suffix: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!(
            "advatar-wallet-store-test-{}-{}.json",
            std::process::id(),
            suffix
        ));
        path
    }

    #[test]
    fn creates_user_wallet_with_default_key() {
        let path = test_storage_path("user");
        let _ = fs::remove_file(&path);
        let store = WalletStore::new_with_storage_path(path.clone()).expect("wallet store should initialize");
        let snapshot = store.snapshot(&WalletOwner::User).expect("user snapshot");
        assert!(snapshot.is_initialized);
        assert!(snapshot.address.is_some());
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn enforces_policy_limits() {
        let path = test_storage_path("limits");
        let _ = fs::remove_file(&path);
        let mut store = WalletStore::new_with_storage_path(path.clone()).expect("wallet store should initialize");
        let agent = WalletOwner::Agent("alpha".to_string());
        store.ensure_agent_profile("alpha").unwrap();

        let policy = WalletPolicy {
            max_per_tx: Some(50),
            daily_limit: Some(100),
            require_approval: true,
            allowed_chains: vec!["eth".to_string()],
        };
        store.set_policy(agent.clone(), policy).unwrap();

        // First spend within limits
        let decision = store.evaluate_spend(&agent, 40, "eth").unwrap();
        assert!(decision.permitted);
        assert_eq!(decision.remaining_daily, Some(60));

        // Per-tx limit breach
        let decision = store.evaluate_spend(&agent, 60, "eth").unwrap();
        assert!(!decision.permitted);
        assert!(decision.reason.unwrap().contains("per-tx"));

        // Daily limit breach (accumulate multiple spends, each within per-tx)
        let decision = store.evaluate_spend(&agent, 50, "eth").unwrap();
        assert!(decision.permitted);
        assert_eq!(decision.remaining_daily, Some(10));

        let decision = store.evaluate_spend(&agent, 20, "eth").unwrap();
        assert!(!decision.permitted);
        assert!(decision.reason.unwrap().contains("daily limit"));

        // Chain allowlist breach
        let decision = store.evaluate_spend(&agent, 10, "btc").unwrap();
        assert!(!decision.permitted);
        assert!(decision.reason.unwrap().contains("chain"));

        let _ = fs::remove_file(&path);
    }
}
