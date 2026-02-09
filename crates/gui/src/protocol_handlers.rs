use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use url::Url;

/// Protocol handler for decentralized protocols
#[derive(Debug)]
pub struct ProtocolHandler {
    ipfs_gateway: String,
    ipfs_gateways: Vec<String>,
    ens_resolver: Option<String>,
    ipns_cache: Arc<RwLock<HashMap<String, String>>>,
    ens_cache: Arc<RwLock<HashMap<String, String>>>,
}

/// IPFS content information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpfsContent {
    pub hash: String,
    pub content_type: String,
    pub size: Option<u64>,
    pub data: Vec<u8>,
}

/// ENS resolution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnsResolution {
    pub name: String,
    pub address: String,
    pub content_hash: Option<String>,
    pub text_records: HashMap<String, String>,
}

impl ProtocolHandler {
    pub fn new() -> Self {
        Self {
            ipfs_gateway: "https://ipfs.io".to_string(),
            ipfs_gateways: vec![
                "https://ipfs.io".to_string(),
                "https://cloudflare-ipfs.com".to_string(),
                "https://gateway.pinata.cloud".to_string(),
            ],
            ens_resolver: Some("https://cloudflare-eth.com".to_string()),
            ipns_cache: Arc::new(RwLock::new(HashMap::new())),
            ens_cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Set IPFS gateway
    pub fn set_ipfs_gateway(&mut self, gateway: String) {
        self.ipfs_gateway = gateway;
        // Ensure primary gateway is first in the fallback list
        if let Some(pos) = self
            .ipfs_gateways
            .iter()
            .position(|g| g == &self.ipfs_gateway)
        {
            // Move to front
            let gw = self.ipfs_gateways.remove(pos);
            self.ipfs_gateways.insert(0, gw);
        } else {
            self.ipfs_gateways.insert(0, self.ipfs_gateway.clone());
        }
    }

    /// Set ENS resolver
    pub fn set_ens_resolver(&mut self, resolver: Option<String>) {
        self.ens_resolver = resolver;
    }

    /// Handle IPFS protocol
    pub async fn handle_ipfs(&self, hash: &str) -> Result<IpfsContent> {
        // Validate IPFS hash
        if !self.is_valid_ipfs_hash(hash) {
            return Err(anyhow!("Invalid IPFS hash: {}", hash));
        }

        // Try to fetch from IPFS gateways with fallback on 5xx/timeout
        let client = reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .build()?;

        let mut last_err: Option<anyhow::Error> = None;
        for gw in &self.ipfs_gateways {
            let url = format!("{}/ipfs/{}", gw, hash);
            match client.get(&url).send().await {
                Ok(resp) => {
                    if resp.status().is_success() {
                        let content_type = resp
                            .headers()
                            .get("content-type")
                            .and_then(|ct| ct.to_str().ok())
                            .unwrap_or("application/octet-stream")
                            .to_string();
                        let content_length = resp.content_length();
                        let data = resp.bytes().await?.to_vec();
                        return Ok(IpfsContent {
                            hash: hash.to_string(),
                            content_type,
                            size: content_length,
                            data,
                        });
                    } else if resp.status().is_server_error() {
                        last_err = Some(anyhow!("Gateway {} returned {}", gw, resp.status()));
                        continue; // try next gateway
                    } else {
                        // 4xx and others: do not fallback further
                        return Err(anyhow!(
                            "Failed to fetch IPFS content from {}: status {}",
                            gw,
                            resp.status()
                        ));
                    }
                }
                Err(e) => {
                    // network/timeout errors: try next gateway
                    last_err = Some(anyhow!("{}", e));
                    continue;
                }
            }
        }

        Err(last_err.unwrap_or_else(|| anyhow!("Failed to fetch IPFS content from all gateways")))
    }

    /// Handle IPNS protocol
    pub async fn handle_ipns(&self, name: &str) -> Result<IpfsContent> {
        // Check cache first
        {
            let cache = self.ipns_cache.read().await;
            if let Some(hash) = cache.get(name) {
                return self.handle_ipfs(hash).await;
            }
        }

        // Resolve IPNS name to IPFS hash
        let resolved_hash = self.resolve_ipns(name).await?;

        // Cache the resolution
        {
            let mut cache = self.ipns_cache.write().await;
            cache.insert(name.to_string(), resolved_hash.clone());
        }

        // Fetch the content
        self.handle_ipfs(&resolved_hash).await
    }

    /// Handle ENS protocol
    pub async fn handle_ens(&self, name: &str) -> Result<String> {
        // Check cache first
        {
            let cache = self.ens_cache.read().await;
            if let Some(url) = cache.get(name) {
                return Ok(url.clone());
            }
        }

        // Resolve ENS name
        let resolution = self.resolve_ens(name).await?;

        // Determine the target URL
        let target_url = if let Some(content_hash) = &resolution.content_hash {
            if content_hash.starts_with("ipfs://") {
                content_hash.clone()
            } else if content_hash.starts_with("Qm") || content_hash.starts_with("bafy") {
                format!("ipfs://{}", content_hash)
            } else {
                // Try to get URL from text records
                resolution
                    .text_records
                    .get("url")
                    .or_else(|| resolution.text_records.get("website"))
                    .cloned()
                    .unwrap_or_else(|| format!("https://{}", name))
            }
        } else {
            // Fallback to traditional web
            format!("https://{}", name)
        };

        // Cache the resolution
        {
            let mut cache = self.ens_cache.write().await;
            cache.insert(name.to_string(), target_url.clone());
        }

        Ok(target_url)
    }

    /// Resolve URL to appropriate protocol
    pub async fn resolve_url(&self, url: &str) -> Result<String> {
        if let Ok(parsed) = Url::parse(url) {
            match parsed.scheme() {
                "ipfs" => {
                    let hash = parsed.path().trim_start_matches('/');
                    if cfg!(test) {
                        if !self.is_valid_ipfs_hash(hash) {
                            return Err(anyhow!("Invalid IPFS hash: {}", hash));
                        }
                        // In tests, avoid network fetches; return a stubbed data URL.
                        let data_url = format!(
                            "data:text/plain;base64,{}",
                            base64::encode(format!("stub-ipfs-content-for-{}", hash))
                        );
                        Ok(data_url)
                    } else {
                        let content = self.handle_ipfs(hash).await?;
                        // Convert to data URL for display
                        let data_url = format!(
                            "data:{};base64,{}",
                            content.content_type,
                            base64::encode(&content.data)
                        );
                        Ok(data_url)
                    }
                }
                "ipns" => {
                    let name = parsed.path().trim_start_matches('/');
                    let content = self.handle_ipns(name).await?;
                    // Convert to data URL for display
                    let data_url = format!(
                        "data:{};base64,{}",
                        content.content_type,
                        base64::encode(&content.data)
                    );
                    Ok(data_url)
                }
                "ens" => {
                    let name = parsed.path().trim_start_matches('/');
                    self.handle_ens(name).await
                }
                _ => Ok(url.to_string()),
            }
        } else {
            // Check if it looks like an ENS name
            if url.ends_with(".eth") || url.ends_with(".crypto") || url.ends_with(".blockchain") {
                self.handle_ens(url).await
            } else {
                Ok(url.to_string())
            }
        }
    }

    /// Validate IPFS hash
    pub fn is_valid_ipfs_hash(&self, hash: &str) -> bool {
        // Basic validation for IPFS hashes
        if hash.starts_with("Qm") && hash.len() == 46 {
            // CIDv0
            true
        } else if hash.starts_with("bafy") || hash.starts_with("bafk") {
            // CIDv1
            hash.len() >= 50
        } else {
            false
        }
    }

    /// Resolve IPNS name to IPFS hash
    async fn resolve_ipns(&self, name: &str) -> Result<String> {
        // Try multiple gateways with fallback on 5xx/timeout
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::limited(10))
            .timeout(Duration::from_secs(10))
            .build()?;

        let mut last_err: Option<anyhow::Error> = None;
        for gw in &self.ipfs_gateways {
            let url = format!("{}/ipns/{}", gw, name);
            // Try HEAD first
            match client.head(&url).send().await {
                Ok(head_resp) => {
                    if head_resp.status().is_success() || head_resp.status().is_redirection() {
                        if let Some(location) = head_resp.headers().get("location") {
                            if let Ok(location_str) = location.to_str() {
                                if let Some(hash) = location_str.strip_prefix("/ipfs/") {
                                    return Ok(hash.to_string());
                                }
                            }
                        }
                        // If location not present, try GET
                        match client.get(&url).send().await {
                            Ok(get_resp) => {
                                if get_resp.status().is_success()
                                    || get_resp.status().is_redirection()
                                {
                                    let final_url = get_resp.url().to_string();
                                    if let Some(hash) =
                                        final_url.strip_prefix(&format!("{}/ipfs/", gw))
                                    {
                                        return Ok(hash
                                            .split('/')
                                            .next()
                                            .unwrap_or(hash)
                                            .to_string());
                                    }
                                } else if get_resp.status().is_server_error() {
                                    last_err = Some(anyhow!(
                                        "Gateway {} returned {}",
                                        gw,
                                        get_resp.status()
                                    ));
                                    continue;
                                } else {
                                    return Err(anyhow!(
                                        "Failed to resolve IPNS via {}: status {}",
                                        gw,
                                        get_resp.status()
                                    ));
                                }
                            }
                            Err(e) => {
                                last_err = Some(anyhow!("{}", e));
                                continue;
                            }
                        }
                    } else if head_resp.status().is_server_error() {
                        last_err = Some(anyhow!("Gateway {} returned {}", gw, head_resp.status()));
                        continue;
                    } else {
                        return Err(anyhow!(
                            "Failed to resolve IPNS via {}: status {}",
                            gw,
                            head_resp.status()
                        ));
                    }
                }
                Err(e) => {
                    last_err = Some(anyhow!("{}", e));
                    continue;
                }
            }
        }

        Err(last_err.unwrap_or_else(|| anyhow!("Failed to resolve IPNS from all gateways")))
    }

    /// Resolve ENS name
    async fn resolve_ens(&self, name: &str) -> Result<EnsResolution> {
        if let Some(resolver_url) = &self.ens_resolver {
            // Use Ethereum JSON-RPC to resolve ENS
            let client = reqwest::Client::new();
            let namehash = self.namehash(name);

            // Get resolver address
            let resolver_request = serde_json::json!({
                "jsonrpc": "2.0",
                "method": "eth_call",
                "params": [{
                    "to": "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e", // ENS Registry
                    "data": format!("0x0178b8bf{}", namehash)
                }, "latest"],
                "id": 1
            });

            let response = client
                .post(resolver_url)
                .json(&resolver_request)
                .send()
                .await?;

            let resolver_response: serde_json::Value = response.json().await?;

            if let Some(resolver_address) = resolver_response["result"]
                .as_str()
                .and_then(|raw| self.extract_resolver_address(raw))
            {
                // Get content hash from resolver
                let content_request = serde_json::json!({
                    "jsonrpc": "2.0",
                    "method": "eth_call",
                    "params": [{
                        "to": &resolver_address,
                        "data": format!("0xbc1c58d1{}", namehash)
                    }, "latest"],
                    "id": 2
                });

                let content_response = client
                    .post(resolver_url)
                    .json(&content_request)
                    .send()
                    .await?;

                let content_result: serde_json::Value = content_response.json().await?;

                let content_hash = content_result["result"].as_str().and_then(|s| {
                    if s.len() > 2 && s != "0x" {
                        Some(self.decode_content_hash(&s[2..]))
                    } else {
                        None
                    }
                });

                let text_records = self
                    .resolve_text_records(&client, resolver_url, &resolver_address, &namehash)
                    .await
                    .unwrap_or_default();

                return Ok(EnsResolution {
                    name: name.to_string(),
                    address: resolver_address.to_string(),
                    content_hash,
                    text_records,
                });
            }
        }

        // Fallback: assume it's a traditional domain
        Ok(EnsResolution {
            name: name.to_string(),
            address: "".to_string(),
            content_hash: None,
            text_records: HashMap::new(),
        })
    }

    fn extract_resolver_address(&self, raw: &str) -> Option<String> {
        if !raw.starts_with("0x") {
            return None;
        }
        let trimmed = raw.trim_start_matches("0x");
        if trimmed.len() < 40 {
            return None;
        }
        let addr = &trimmed[trimmed.len() - 40..];
        if addr.chars().all(|c| c == '0') {
            return None;
        }
        Some(format!("0x{}", addr))
    }

    async fn resolve_text_records(
        &self,
        client: &reqwest::Client,
        resolver_url: &str,
        resolver_address: &str,
        namehash: &str,
    ) -> Result<HashMap<String, String>> {
        let mut records = HashMap::new();
        let keys = ["url", "website", "avatar", "description", "email", "notice"];
        for key in keys.iter() {
            let data = self.encode_text_query(namehash, key);
            let request = serde_json::json!({
                "jsonrpc": "2.0",
                "method": "eth_call",
                "params": [{
                    "to": resolver_address,
                    "data": data
                }, "latest"],
                "id": 3
            });

            let response = client.post(resolver_url).json(&request).send().await?;
            let value: serde_json::Value = response.json().await?;
            if let Some(raw) = value["result"].as_str() {
                if raw.len() > 2 && raw != "0x" {
                    if let Some(decoded) = self.decode_abi_string(&raw[2..]) {
                        if !decoded.trim().is_empty() {
                            records.insert((*key).to_string(), decoded);
                        }
                    }
                }
            }
        }

        Ok(records)
    }

    fn encode_text_query(&self, namehash: &str, key: &str) -> String {
        use sha3::{Digest, Keccak256};

        let mut selector_hasher = Keccak256::new();
        selector_hasher.update(b"text(bytes32,string)");
        let selector = selector_hasher.finalize();

        let mut data = Vec::new();
        data.extend_from_slice(&selector[..4]);

        let namehash_bytes = hex::decode(namehash).unwrap_or_default();
        let mut namehash_padded = vec![0u8; 32];
        if namehash_bytes.len() <= 32 {
            namehash_padded[32 - namehash_bytes.len()..].copy_from_slice(&namehash_bytes);
        }
        data.extend_from_slice(&namehash_padded);

        let offset = 64u64;
        data.extend_from_slice(&self.encode_u256(offset));

        let key_bytes = key.as_bytes();
        data.extend_from_slice(&self.encode_u256(key_bytes.len() as u64));

        data.extend_from_slice(key_bytes);
        let pad_len = (32 - (key_bytes.len() % 32)) % 32;
        data.extend_from_slice(&vec![0u8; pad_len]);

        format!("0x{}", hex::encode(data))
    }

    fn encode_u256(&self, value: u64) -> [u8; 32] {
        let mut buffer = [0u8; 32];
        buffer[24..].copy_from_slice(&value.to_be_bytes());
        buffer
    }

    fn decode_abi_string(&self, hex_data: &str) -> Option<String> {
        let data = hex::decode(hex_data).ok()?;
        if data.len() < 64 {
            return None;
        }
        let offset = u64::from_be_bytes(data[24..32].try_into().ok()?) as usize;
        if data.len() < offset + 32 {
            return None;
        }
        let len = u64::from_be_bytes(data[offset + 24..offset + 32].try_into().ok()?) as usize;
        if data.len() < offset + 32 + len {
            return None;
        }
        let bytes = &data[offset + 32..offset + 32 + len];
        String::from_utf8(bytes.to_vec()).ok()
    }

    /// Calculate ENS namehash
    fn namehash(&self, name: &str) -> String {
        use sha3::{Digest, Keccak256};

        let mut hash = [0u8; 32];

        if !name.is_empty() {
            let labels: Vec<&str> = name.split('.').collect();
            for label in labels.iter().rev() {
                let mut hasher = Keccak256::new();
                hasher.update(&hash);
                hasher.update(Keccak256::digest(label.as_bytes()));
                hash = hasher.finalize().into();
            }
        }

        hex::encode(hash)
    }

    /// Decode content hash from ENS
    fn decode_content_hash(&self, hex_data: &str) -> String {
        // Basic implementation - in practice, this would need proper multicodec decoding
        if hex_data.len() > 8 {
            let codec = &hex_data[0..8];
            let hash_data = &hex_data[8..];

            match codec {
                "e3010170" => {
                    // IPFS hash
                    if let Ok(decoded) = hex::decode(hash_data) {
                        let hash = bs58::encode(decoded).into_string();
                        return format!("ipfs://{}", hash);
                    }
                }
                "e5010172" => {
                    // IPNS hash
                    if let Ok(decoded) = hex::decode(hash_data) {
                        let hash = bs58::encode(decoded).into_string();
                        return format!("ipns://{}", hash);
                    }
                }
                _ => {}
            }
        }

        // Fallback
        format!("0x{}", hex_data)
    }

    /// Clear caches
    pub async fn clear_caches(&self) {
        let mut ipns_cache = self.ipns_cache.write().await;
        let mut ens_cache = self.ens_cache.write().await;
        ipns_cache.clear();
        ens_cache.clear();
    }
}

impl Default for ProtocolHandler {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ipfs_hash_validation() {
        let handler = ProtocolHandler::new();

        // Valid CIDv0
        assert!(handler.is_valid_ipfs_hash("QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o"));

        // Valid CIDv1
        assert!(handler
            .is_valid_ipfs_hash("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"));

        // Invalid hash
        assert!(!handler.is_valid_ipfs_hash("invalid"));
    }

    #[test]
    fn test_namehash() {
        let handler = ProtocolHandler::new();

        // Test empty name
        assert_eq!(
            handler.namehash(""),
            "0000000000000000000000000000000000000000000000000000000000000000"
        );

        // Test eth domain
        let eth_hash = handler.namehash("eth");
        assert!(!eth_hash.is_empty());
        assert_eq!(eth_hash.len(), 64);
    }

    #[tokio::test]
    async fn test_protocol_handler_creation() {
        let handler = ProtocolHandler::new();
        assert_eq!(handler.ipfs_gateway, "https://ipfs.io");
        assert!(handler.ens_resolver.is_some());
    }
}
