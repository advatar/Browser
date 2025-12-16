use crate::agent::{McpConfigValue, McpResolvedServerConfig, McpServerConfig, McpTransportKind};
use anyhow::{anyhow, Context, Result};
use indexmap::IndexMap;
use keyring::Entry;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use uuid::Uuid;

const PROFILE_DIR: &str = "configs/mcp_profiles";
const LEGACY_MANIFEST: &str = "configs/mcp_servers.json";
const PROFILE_INDEX_FILE: &str = "profiles.json";
const EXPORT_VERSION: u8 = 1;
const KEYRING_SERVICE: &str = "advatar-browser-mcp";

fn now_millis() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|ts| ts.as_millis() as u64)
        .unwrap_or_default()
}

#[derive(Clone)]
pub struct McpSecretStore {
    service: String,
}

impl McpSecretStore {
    pub fn new() -> Self {
        Self {
            service: KEYRING_SERVICE.to_string(),
        }
    }

    fn entry(&self, secret_id: &str) -> Result<Entry> {
        Entry::new(&self.service, secret_id)
            .map_err(|err| anyhow!("failed to access keyring entry `{}`: {}", secret_id, err))
    }

    pub fn read(&self, secret_id: &str) -> Result<String> {
        self.entry(secret_id)?
            .get_password()
            .map_err(|err| anyhow!("failed to read secret `{}`: {}", secret_id, err))
    }

    pub fn store(&self, secret_id: Option<String>, value: &str) -> Result<String> {
        let id = secret_id.unwrap_or_else(|| Uuid::new_v4().to_string());
        self.entry(&id)?
            .set_password(value)
            .map_err(|err| anyhow!("failed to persist secret `{}`: {}", id, err))?;
        Ok(id)
    }

    pub fn remove(&self, secret_id: &str) -> Result<()> {
        match self.entry(secret_id)?.delete_password() {
            Ok(_) => Ok(()),
            Err(keyring::Error::NoEntry) => Ok(()),
            Err(err) => Err(anyhow!("failed to delete secret `{}`: {}", secret_id, err)),
        }
    }

    pub fn preview(value: &str) -> String {
        const PREVIEW_LEN: usize = 4;
        let trimmed = value.trim();
        if trimmed.is_empty() {
            return String::new();
        }
        let chars: Vec<char> = trimmed.chars().collect();
        if chars.len() <= PREVIEW_LEN {
            trimmed.to_string()
        } else {
            let suffix: String = chars[chars.len() - PREVIEW_LEN..].iter().collect();
            format!("••••{}", suffix)
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpProfileRecord {
    pub id: String,
    pub label: String,
    pub created_at: u64,
    pub updated_at: u64,
}

impl McpProfileRecord {
    fn new(id: String, label: String) -> Self {
        let ts = now_millis();
        Self {
            id,
            label,
            created_at: ts,
            updated_at: ts,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct McpProfileIndex {
    pub active_profile: String,
    pub profiles: Vec<McpProfileRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpProfileSummary {
    pub id: String,
    pub label: String,
    pub created_at: u64,
    pub updated_at: u64,
    pub server_count: usize,
    pub is_active: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpProfileState {
    pub active_profile_id: String,
    pub profiles: Vec<McpProfileSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpProfileBundle {
    pub version: u8,
    pub label: String,
    pub created_at: u64,
    pub servers: Vec<McpServerConfig>,
}

pub struct McpConfigService {
    base_dir: PathBuf,
    index_path: PathBuf,
    state: Mutex<McpProfileIndex>,
    secret_store: Arc<McpSecretStore>,
}

impl McpConfigService {
    pub fn load() -> Result<Self> {
        let base_dir = PathBuf::from(PROFILE_DIR);
        if !base_dir.exists() {
            fs::create_dir_all(&base_dir)
                .with_context(|| format!("creating MCP profile dir at {}", base_dir.display()))?;
        }
        let index_path = base_dir.join(PROFILE_INDEX_FILE);
        let secret_store = Arc::new(McpSecretStore::new());
        let index = if index_path.exists() {
            let raw = fs::read_to_string(&index_path).with_context(|| {
                format!("reading MCP profile index at {}", index_path.display())
            })?;
            serde_json::from_str::<McpProfileIndex>(&raw)
                .with_context(|| format!("parsing MCP profile index at {}", index_path.display()))?
        } else {
            Self::bootstrap_index(&base_dir, &index_path)?
        };
        Ok(Self {
            base_dir,
            index_path,
            state: Mutex::new(index),
            secret_store,
        })
    }

    pub fn reset() -> Result<Self> {
        let base_dir = PathBuf::from(PROFILE_DIR);
        if base_dir.exists() {
            let backup_name = format!("{}_bak_{}", PROFILE_DIR, now_millis());
            let backup_path = PathBuf::from(backup_name);
            fs::rename(&base_dir, &backup_path).with_context(|| {
                format!(
                    "backing up corrupted profile dir to {}",
                    backup_path.display()
                )
            })?;
        }
        Self::load()
    }

    fn bootstrap_index(base_dir: &Path, index_path: &Path) -> Result<McpProfileIndex> {
        let record = McpProfileRecord::new("default".to_string(), "Default".to_string());
        let manifest_path = base_dir.join(format!("{}.json", record.id));
        let servers = Self::read_legacy_manifest().unwrap_or_default();
        Self::write_manifest(&manifest_path, &servers)?;
        let index = McpProfileIndex {
            active_profile: record.id.clone(),
            profiles: vec![record],
        };
        let raw = serde_json::to_string_pretty(&index).context("serialising MCP profile index")?;
        fs::write(index_path, raw)
            .with_context(|| format!("writing MCP profile index to {}", index_path.display()))?;
        Ok(index)
    }

    fn read_legacy_manifest() -> Result<Vec<McpServerConfig>> {
        let path = PathBuf::from(LEGACY_MANIFEST);
        if !path.exists() {
            return Ok(Vec::new());
        }
        let raw = fs::read_to_string(&path)
            .with_context(|| format!("reading legacy MCP manifest at {}", path.display()))?;
        #[derive(Deserialize)]
        struct Manifest {
            servers: Vec<McpServerConfig>,
        }
        let manifest: Manifest = serde_json::from_str(&raw)
            .with_context(|| format!("parsing legacy MCP manifest at {}", path.display()))?;
        Ok(manifest.servers)
    }

    fn manifest_path(&self, profile_id: &str) -> PathBuf {
        self.base_dir.join(format!("{}.json", profile_id))
    }

    fn read_manifest(&self, profile_id: &str) -> Result<Vec<McpServerConfig>> {
        let path = self.manifest_path(profile_id);
        if !path.exists() {
            return Ok(Vec::new());
        }
        let raw = fs::read_to_string(&path)
            .with_context(|| format!("reading MCP manifest {}", path.display()))?;
        #[derive(Deserialize)]
        struct Manifest {
            servers: Vec<McpServerConfig>,
        }
        let manifest: Manifest = serde_json::from_str(&raw)
            .with_context(|| format!("parsing MCP manifest {}", path.display()))?;
        Ok(manifest.servers)
    }

    fn write_manifest(path: &Path, configs: &[McpServerConfig]) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).with_context(|| {
                format!("ensuring MCP manifest dir exists at {}", parent.display())
            })?;
        }
        #[derive(Serialize)]
        struct Manifest<'a> {
            servers: &'a [McpServerConfig],
        }
        let manifest = Manifest { servers: configs };
        let raw = serde_json::to_string_pretty(&manifest).context("serialising MCP manifest")?;
        fs::write(path, raw).with_context(|| format!("writing MCP manifest {}", path.display()))?;
        Ok(())
    }

    fn write_profile_manifest(&self, profile_id: &str, configs: &[McpServerConfig]) -> Result<()> {
        let path = self.manifest_path(profile_id);
        Self::write_manifest(&path, configs)
    }

    fn ensure_profile_exists(&self, profile_id: &str) -> Result<()> {
        if !self
            .state
            .lock()
            .map_err(|_| anyhow!("profile index poisoned"))?
            .profiles
            .iter()
            .any(|p| p.id == profile_id)
        {
            return Err(anyhow!("profile `{}` not found", profile_id));
        }
        Ok(())
    }

    pub fn profile_state(&self) -> Result<McpProfileState> {
        let index = self
            .state
            .lock()
            .map_err(|_| anyhow!("profile index poisoned"))?
            .clone();
        let mut summaries = Vec::with_capacity(index.profiles.len());
        for record in index.profiles.iter() {
            let count = self.read_manifest(&record.id)?.len();
            summaries.push(McpProfileSummary {
                id: record.id.clone(),
                label: record.label.clone(),
                created_at: record.created_at,
                updated_at: record.updated_at,
                server_count: count,
                is_active: index.active_profile == record.id,
            });
        }
        Ok(McpProfileState {
            active_profile_id: index.active_profile,
            profiles: summaries,
        })
    }

    pub fn active_profile_id(&self) -> Result<String> {
        Ok(self
            .state
            .lock()
            .map_err(|_| anyhow!("profile index poisoned"))?
            .active_profile
            .clone())
    }

    pub fn load_active_servers(&self) -> Result<(String, Vec<McpServerConfig>)> {
        let profile_id = self.active_profile_id()?;
        let configs = self.read_manifest(&profile_id)?;
        Ok((profile_id, configs))
    }

    pub fn save_active_servers(
        &self,
        mut servers: Vec<McpServerConfig>,
    ) -> Result<(String, Vec<McpServerConfig>)> {
        let profile_id = self.active_profile_id()?;
        self.validate_servers(&servers)?;
        let previous = self.read_manifest(&profile_id)?;
        self.apply_secret_updates(&profile_id, &previous, &mut servers)?;
        self.write_profile_manifest(&profile_id, &servers)?;
        self.touch_profile(&profile_id)?;
        Ok((profile_id, servers))
    }

    pub fn load_active_resolved_servers(&self) -> Result<Vec<McpResolvedServerConfig>> {
        let (profile_id, configs) = self.load_active_servers()?;
        configs
            .iter()
            .map(|cfg| self.resolve_server(&profile_id, cfg))
            .collect()
    }

    fn resolve_server(
        &self,
        profile_id: &str,
        config: &McpServerConfig,
    ) -> Result<McpResolvedServerConfig> {
        Ok(McpResolvedServerConfig {
            id: config.id.clone(),
            name: config.name.clone(),
            endpoint: config.endpoint.clone(),
            enabled: config.enabled,
            headers: self.resolve_map(profile_id, &config.id, "header", &config.headers)?,
            timeout_ms: config.timeout_ms,
            default_capability: config.default_capability.clone(),
            transport: config.transport,
            program: config.program.clone(),
            args: config.args.clone(),
            env: self.resolve_map(profile_id, &config.id, "env", &config.env)?,
        })
    }

    pub fn resolve_inline_server(
        &self,
        config: &McpServerConfig,
    ) -> Result<McpResolvedServerConfig> {
        self.validate_servers(std::slice::from_ref(config))?;
        Ok(McpResolvedServerConfig {
            id: config.id.clone(),
            name: config.name.clone(),
            endpoint: config.endpoint.clone(),
            enabled: config.enabled,
            headers: Self::resolve_inline_map(
                &self.secret_store,
                config,
                "header",
                &config.headers,
            )?,
            timeout_ms: config.timeout_ms,
            default_capability: config.default_capability.clone(),
            transport: config.transport,
            program: config
                .program
                .clone()
                .or_else(|| (!config.endpoint.trim().is_empty()).then(|| config.endpoint.clone())),
            args: config.args.clone(),
            env: Self::resolve_inline_map(&self.secret_store, config, "env", &config.env)?,
        })
    }

    fn validate_servers(&self, servers: &[McpServerConfig]) -> Result<()> {
        let mut ids = HashSet::new();
        for (idx, server) in servers.iter().enumerate() {
            let id = server.id.trim();
            let label = server.name.as_deref().unwrap_or(id).to_string();
            if id.is_empty() {
                return Err(anyhow!(
                    "MCP server at position {} is missing an id",
                    idx + 1
                ));
            }
            if !ids.insert(id.to_string()) {
                return Err(anyhow!("duplicate MCP server id `{}`", id));
            }

            if server.enabled {
                let transport_label = match server.transport {
                    McpTransportKind::Http => "http",
                    McpTransportKind::Websocket => "websocket",
                    McpTransportKind::Stdio => "stdio",
                };
                match server.transport {
                    McpTransportKind::Http | McpTransportKind::Websocket => {
                        if server.endpoint.trim().is_empty() {
                            return Err(anyhow!(
                                "MCP server `{}` requires an endpoint for {} transport",
                                label,
                                transport_label
                            ));
                        }
                    }
                    McpTransportKind::Stdio => {
                        let program = server.program.as_deref().unwrap_or("").trim();
                        if program.is_empty() && server.endpoint.trim().is_empty() {
                            return Err(anyhow!(
                                "MCP server `{}` requires `program` or `endpoint` for stdio transport",
                                label
                            ));
                        }
                    }
                }
            }

            Self::validate_secret_map(&server.headers, &server.id, "headers")?;
            Self::validate_secret_map(&server.env, &server.id, "env")?;
        }
        Ok(())
    }

    fn validate_secret_map(
        map: &IndexMap<String, McpConfigValue>,
        server_id: &str,
        scope: &str,
    ) -> Result<()> {
        for (key, value) in map {
            if key.trim().is_empty() {
                return Err(anyhow!(
                    "MCP server `{}` has an empty key in {}",
                    server_id,
                    scope
                ));
            }
            if let McpConfigValue::Secret(secret) = value {
                let has_id = secret
                    .secret_id
                    .as_deref()
                    .map(|val| !val.trim().is_empty())
                    .unwrap_or(false);
                let has_value = secret
                    .value
                    .as_deref()
                    .map(|val| !val.trim().is_empty())
                    .unwrap_or(false);
                if !has_id && !has_value {
                    return Err(anyhow!(
                        "secret `{}` on server `{}` is missing a value",
                        key,
                        server_id
                    ));
                }
            }
        }
        Ok(())
    }

    fn resolve_map(
        &self,
        profile_id: &str,
        server_id: &str,
        _scope: &str,
        map: &IndexMap<String, McpConfigValue>,
    ) -> Result<IndexMap<String, String>> {
        let mut resolved = IndexMap::new();
        for (key, value) in map.iter() {
            let resolved_value = match value {
                McpConfigValue::Plain(val) => val.clone(),
                McpConfigValue::Secret(secret) => {
                    let secret_id = secret.secret_id.as_deref().ok_or_else(|| {
                        anyhow!(
                            "secret `{}` for server {} profile {} missing secret_id",
                            key,
                            server_id,
                            profile_id
                        )
                    })?;
                    self.secret_store.read(secret_id)?
                }
            };
            resolved.insert(key.clone(), resolved_value);
        }
        Ok(resolved)
    }

    fn resolve_inline_map(
        store: &Arc<McpSecretStore>,
        config: &McpServerConfig,
        _scope: &str,
        map: &IndexMap<String, McpConfigValue>,
    ) -> Result<IndexMap<String, String>> {
        let mut resolved = IndexMap::new();
        for (key, value) in map.iter() {
            let resolved_value = match value {
                McpConfigValue::Plain(val) => val.clone(),
                McpConfigValue::Secret(secret) => {
                    if let Some(new_value) = secret.value.as_ref() {
                        new_value.clone()
                    } else if let Some(secret_id) = secret.secret_id.as_deref() {
                        store.read(secret_id)?
                    } else {
                        return Err(anyhow!(
                            "secret `{}` for server {} missing value",
                            key,
                            config.id
                        ));
                    }
                }
            };
            resolved.insert(key.clone(), resolved_value);
        }
        Ok(resolved)
    }

    fn apply_secret_updates(
        &self,
        profile_id: &str,
        previous: &[McpServerConfig],
        next: &mut [McpServerConfig],
    ) -> Result<()> {
        let mut prev_map = HashMap::new();
        for server in previous {
            prev_map.insert(server.id.clone(), server);
        }

        for server in next.iter_mut() {
            let prev = prev_map.get(&server.id);
            self.synchronise_secret_map(
                profile_id,
                &server.id,
                "header",
                prev.map(|cfg| &cfg.headers),
                &mut server.headers,
            )?;
            self.synchronise_secret_map(
                profile_id,
                &server.id,
                "env",
                prev.map(|cfg| &cfg.env),
                &mut server.env,
            )?;
        }

        for prev in previous {
            if next.iter().any(|cfg| cfg.id == prev.id) {
                continue;
            }
            self.revoke_all_secrets(prev)?;
        }
        Ok(())
    }

    fn revoke_all_secrets(&self, config: &McpServerConfig) -> Result<()> {
        self.drop_map_secrets(&config.headers)?;
        self.drop_map_secrets(&config.env)
    }

    fn drop_map_secrets(&self, map: &IndexMap<String, McpConfigValue>) -> Result<()> {
        for value in map.values() {
            if let McpConfigValue::Secret(secret) = value {
                if let Some(id) = &secret.secret_id {
                    let _ = self.secret_store.remove(id);
                }
            }
        }
        Ok(())
    }

    fn synchronise_secret_map(
        &self,
        profile_id: &str,
        server_id: &str,
        _scope: &str,
        previous: Option<&IndexMap<String, McpConfigValue>>,
        current: &mut IndexMap<String, McpConfigValue>,
    ) -> Result<()> {
        let empty = IndexMap::new();
        let prev_map = previous.unwrap_or(&empty);
        for (key, value) in current.iter_mut() {
            match value {
                McpConfigValue::Plain(_) => {
                    if let Some(McpConfigValue::Secret(secret)) = prev_map.get(key) {
                        if let Some(id) = &secret.secret_id {
                            let _ = self.secret_store.remove(id);
                        }
                    }
                }
                McpConfigValue::Secret(secret) => {
                    secret.is_secret = true;
                    if let Some(new_value) = secret.value.clone() {
                        let id = self
                            .secret_store
                            .store(secret.secret_id.clone(), &new_value)?;
                        secret.secret_id = Some(id);
                        secret.preview = Some(McpSecretStore::preview(&new_value));
                        secret.value = None;
                    } else if secret.secret_id.is_none() {
                        return Err(anyhow!(
                            "secret `{}` on server {} profile {} missing value",
                            key,
                            server_id,
                            profile_id
                        ));
                    }
                }
            }
        }

        for (key, prev_value) in prev_map.iter() {
            if current.contains_key(key) {
                continue;
            }
            if let McpConfigValue::Secret(secret) = prev_value {
                if let Some(id) = &secret.secret_id {
                    let _ = self.secret_store.remove(id);
                }
            }
        }
        Ok(())
    }

    fn touch_profile(&self, profile_id: &str) -> Result<()> {
        let mut guard = self
            .state
            .lock()
            .map_err(|_| anyhow!("profile index poisoned"))?;
        if let Some(profile) = guard.profiles.iter_mut().find(|p| p.id == profile_id) {
            profile.updated_at = now_millis();
        }
        self.persist_index(&guard)
    }

    fn persist_index(&self, index: &McpProfileIndex) -> Result<()> {
        let raw = serde_json::to_string_pretty(index).context("serialising MCP profile index")?;
        fs::write(&self.index_path, raw)
            .with_context(|| format!("writing MCP profile index to {}", self.index_path.display()))
    }

    pub fn set_active_profile(&self, profile_id: &str) -> Result<()> {
        self.ensure_profile_exists(profile_id)?;
        let mut guard = self
            .state
            .lock()
            .map_err(|_| anyhow!("profile index poisoned"))?;
        guard.active_profile = profile_id.to_string();
        self.persist_index(&guard)
    }

    pub fn create_profile(&self, label: &str, make_active: bool) -> Result<McpProfileRecord> {
        let mut guard = self
            .state
            .lock()
            .map_err(|_| anyhow!("profile index poisoned"))?;
        let id = self.generate_profile_id(label, &guard);
        let record = McpProfileRecord::new(id, label.trim().to_string());
        self.write_profile_manifest(&record.id, &[])?;
        guard.profiles.push(record.clone());
        if make_active {
            guard.active_profile = record.id.clone();
        }
        self.persist_index(&guard)?;
        Ok(record)
    }

    fn generate_profile_id(&self, label: &str, index: &McpProfileIndex) -> String {
        let cleaned = label
            .chars()
            .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '-' || *ch == '_')
            .collect::<String>()
            .to_lowercase();
        let base = if cleaned.is_empty() {
            let raw = Uuid::new_v4().simple().to_string();
            format!("profile-{}", &raw[..8])
        } else {
            cleaned
        };
        let mut candidate = base.clone();
        let mut counter = 1;
        while index.profiles.iter().any(|p| p.id == candidate) {
            candidate = format!("{}-{}", base, counter);
            counter += 1;
        }
        candidate
    }

    pub fn export_profile(&self, profile_id: &str, target: &Path) -> Result<()> {
        self.ensure_profile_exists(profile_id)?;
        let configs = self.read_manifest(profile_id)?;
        let index = self
            .state
            .lock()
            .map_err(|_| anyhow!("profile index poisoned"))?;
        let label = index
            .profiles
            .iter()
            .find(|p| p.id == profile_id)
            .map(|p| p.label.clone())
            .unwrap_or_else(|| profile_id.to_string());
        drop(index);
        let mut scrubbed = configs.clone();
        for server in scrubbed.iter_mut() {
            Self::scrub_map(&mut server.headers);
            Self::scrub_map(&mut server.env);
        }
        let bundle = McpProfileBundle {
            version: EXPORT_VERSION,
            label,
            created_at: now_millis(),
            servers: scrubbed,
        };
        let raw = serde_json::to_string_pretty(&bundle).context("serialising MCP export bundle")?;
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("creating export dir at {}", parent.display()))?;
        }
        fs::write(target, raw)
            .with_context(|| format!("writing MCP export to {}", target.display()))
    }

    pub fn import_profile_from_path(
        &self,
        bundle_path: &Path,
        label_override: Option<&str>,
        make_active: bool,
    ) -> Result<McpProfileRecord> {
        let raw = fs::read_to_string(bundle_path)
            .with_context(|| format!("reading MCP bundle at {}", bundle_path.display()))?;
        let mut bundle: McpProfileBundle = serde_json::from_str(&raw)
            .with_context(|| format!("parsing MCP bundle at {}", bundle_path.display()))?;
        if bundle.version != EXPORT_VERSION {
            return Err(anyhow!("unsupported MCP bundle version {}", bundle.version));
        }
        let label = label_override
            .map(|s| s.to_string())
            .unwrap_or(bundle.label);
        let record = self.create_profile(&label, make_active)?;
        for server in bundle.servers.iter_mut() {
            Self::scrub_map(&mut server.headers);
            Self::scrub_map(&mut server.env);
        }
        self.write_profile_manifest(&record.id, &bundle.servers)?;
        self.touch_profile(&record.id)?;
        Ok(record)
    }

    fn scrub_map(map: &mut IndexMap<String, McpConfigValue>) {
        for value in map.values_mut() {
            if let McpConfigValue::Secret(secret) = value {
                secret.secret_id = None;
                secret.preview = None;
                secret.value = None;
            }
        }
    }

    pub fn secret_store(&self) -> Arc<McpSecretStore> {
        self.secret_store.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::McpSecretValue;
    use indexmap::indexmap;

    fn test_service() -> McpConfigService {
        McpConfigService {
            base_dir: PathBuf::from("/tmp"),
            index_path: PathBuf::from("/tmp/index.json"),
            state: Mutex::new(McpProfileIndex {
                active_profile: "default".to_string(),
                profiles: vec![],
            }),
            secret_store: Arc::new(McpSecretStore::new()),
        }
    }

    fn base_server(id: &str) -> McpServerConfig {
        McpServerConfig {
            id: id.to_string(),
            name: None,
            endpoint: "http://127.0.0.1:1234/mcp".to_string(),
            enabled: true,
            headers: IndexMap::new(),
            timeout_ms: Some(5_000),
            default_capability: None,
            transport: McpTransportKind::Http,
            program: None,
            args: Vec::new(),
            env: IndexMap::new(),
        }
    }

    #[test]
    fn validate_rejects_duplicate_ids() {
        let service = test_service();
        let servers = vec![base_server("dup"), base_server("dup")];
        let err = service.validate_servers(&servers).expect_err("should fail");
        assert!(
            err.to_string().contains("duplicate MCP server id"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn validate_requires_endpoint_for_http() {
        let service = test_service();
        let mut server = base_server("missing-endpoint");
        server.endpoint.clear();
        let err = service
            .validate_servers(&[server])
            .expect_err("should fail");
        assert!(
            err.to_string().contains("requires an endpoint"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn validate_requires_program_for_stdio_when_no_endpoint() {
        let service = test_service();
        let server = McpServerConfig {
            transport: McpTransportKind::Stdio,
            endpoint: String::new(),
            program: None,
            ..base_server("stdio-missing")
        };
        let err = service
            .validate_servers(&[server])
            .expect_err("should fail");
        assert!(
            err.to_string().contains("requires `program` or `endpoint`"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn validate_secrets_require_values() {
        let service = test_service();
        let mut server = base_server("secret-missing");
        server.headers = indexmap! {
            "Authorization".to_string() => McpConfigValue::Secret(McpSecretValue{
                is_secret: true,
                secret_id: None,
                preview: None,
                value: None,
            })
        };
        let err = service
            .validate_servers(&[server])
            .expect_err("should fail");
        assert!(
            err.to_string().contains("missing a value"),
            "unexpected error: {err}"
        );
    }

    #[test]
    fn resolve_inline_uses_endpoint_as_stdio_program() {
        let service = test_service();
        let server = McpServerConfig {
            transport: McpTransportKind::Stdio,
            endpoint: "/usr/local/bin/mcp-stdio".to_string(),
            program: None,
            enabled: true,
            ..base_server("stdio-inline")
        };
        let resolved = service
            .resolve_inline_server(&server)
            .expect("should resolve inline server");
        assert_eq!(
            resolved.program.as_deref(),
            Some("/usr/local/bin/mcp-stdio")
        );
        assert_eq!(resolved.transport, McpTransportKind::Stdio);
    }
}
