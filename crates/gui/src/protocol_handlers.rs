use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use url::Url;

/// Protocol handler for decentralized protocols
#[derive(Debug)]
pub struct ProtocolHandler {
    ipfs_gateway: String,
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
            ens_resolver: Some("https://cloudflare-eth.com".to_string()),
            ipns_cache: Arc::new(RwLock::new(HashMap::new())),
            ens_cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Set IPFS gateway
    pub fn set_ipfs_gateway(&mut self, gateway: String) {
        self.ipfs_gateway = gateway;
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

        // Try to fetch from IPFS gateway
        let url = format!("{}/ipfs/{}", self.ipfs_gateway, hash);
        
        match reqwest::get(&url).await {
            Ok(response) => {
                let content_type = response
                    .headers()
                    .get("content-type")
                    .and_then(|ct| ct.to_str().ok())
                    .unwrap_or("application/octet-stream")
                    .to_string();
                
                let content_length = response.content_length();
                let data = response.bytes().await?.to_vec();
                
                Ok(IpfsContent {
                    hash: hash.to_string(),
                    content_type,
                    size: content_length,
                    data,
                })
            }
            Err(e) => Err(anyhow!("Failed to fetch IPFS content: {}", e)),
        }
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
                resolution.text_records
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
                    let content = self.handle_ipfs(hash).await?;
                    // Convert to data URL for display
                    let data_url = format!(
                        "data:{};base64,{}",
                        content.content_type,
                        base64::encode(&content.data)
                    );
                    Ok(data_url)
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
    fn is_valid_ipfs_hash(&self, hash: &str) -> bool {
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
        // Use IPFS gateway to resolve IPNS
        let url = format!("{}/ipns/{}", self.ipfs_gateway, name);
        
        match reqwest::Client::new()
            .head(&url)
            .send()
            .await
        {
            Ok(response) => {
                // Try to get the resolved hash from headers
                if let Some(location) = response.headers().get("location") {
                    if let Ok(location_str) = location.to_str() {
                        if let Some(hash) = location_str.strip_prefix("/ipfs/") {
                            return Ok(hash.to_string());
                        }
                    }
                }
                
                // Fallback: make a GET request and extract from redirect
                let get_response = reqwest::get(&url).await?;
                let final_url = get_response.url().to_string();
                
                if let Some(hash) = final_url.strip_prefix(&format!("{}/ipfs/", self.ipfs_gateway)) {
                    Ok(hash.split('/').next().unwrap_or(hash).to_string())
                } else {
                    Err(anyhow!("Could not resolve IPNS name: {}", name))
                }
            }
            Err(e) => Err(anyhow!("Failed to resolve IPNS: {}", e)),
        }
    }

    /// Resolve ENS name
    async fn resolve_ens(&self, name: &str) -> Result<EnsResolution> {
        if let Some(resolver_url) = &self.ens_resolver {
            // Use Ethereum JSON-RPC to resolve ENS
            let client = reqwest::Client::new();
            
            // Get resolver address
            let resolver_request = serde_json::json!({
                "jsonrpc": "2.0",
                "method": "eth_call",
                "params": [{
                    "to": "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e", // ENS Registry
                    "data": format!("0x0178b8bf{}", self.namehash(name))
                }, "latest"],
                "id": 1
            });
            
            let response = client
                .post(resolver_url)
                .json(&resolver_request)
                .send()
                .await?;
            
            let resolver_response: serde_json::Value = response.json().await?;
            
            if let Some(resolver_address) = resolver_response["result"].as_str() {
                if resolver_address != "0x0000000000000000000000000000000000000000000000000000000000000000" {
                    // Get content hash from resolver
                    let content_request = serde_json::json!({
                        "jsonrpc": "2.0",
                        "method": "eth_call",
                        "params": [{
                            "to": &resolver_address[2..42], // Remove 0x prefix and take first 20 bytes
                            "data": format!("0xbc1c58d1{}", self.namehash(name))
                        }, "latest"],
                        "id": 2
                    });
                    
                    let content_response = client
                        .post(resolver_url)
                        .json(&content_request)
                        .send()
                        .await?;
                    
                    let content_result: serde_json::Value = content_response.json().await?;
                    
                    let content_hash = content_result["result"]
                        .as_str()
                        .and_then(|s| {
                            if s.len() > 2 && s != "0x" {
                                Some(self.decode_content_hash(&s[2..]))
                            } else {
                                None
                            }
                        });
                    
                    return Ok(EnsResolution {
                        name: name.to_string(),
                        address: resolver_address.to_string(),
                        content_hash,
                        text_records: HashMap::new(), // TODO: Implement text record resolution
                    });
                }
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
        assert!(handler.is_valid_ipfs_hash("bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi"));
        
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
