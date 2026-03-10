use anyhow::{anyhow, Context, Result};
use rust_ipfs::config::BOOTSTRAP_NODES;
use rust_ipfs::unixfs::Entry as UnixfsEntry;
use rust_ipfs::{Ipfs, IpfsPath, StorageType, UninitializedIpfsDefault};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::time::Duration;
use tokio::sync::{OnceCell, RwLock};
use url::Url;

const DEFAULT_IPFS_GATEWAY: &str = "builtin://ipfs";
const LOCAL_IPFS_TIMEOUT: Duration = Duration::from_secs(20);

#[derive(Clone)]
pub struct ProtocolHandler {
    ipfs_gateway: String,
    ens_resolver: Option<String>,
    ens_cache: std::sync::Arc<RwLock<HashMap<String, String>>>,
    local_ipfs: std::sync::Arc<OnceCell<LocalIpfsNode>>,
}

#[derive(Clone)]
struct LocalIpfsNode {
    ipfs: Ipfs,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IpfsContent {
    pub hash: String,
    pub content_type: String,
    pub size: Option<u64>,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnsResolution {
    pub name: String,
    pub address: String,
    pub content_hash: Option<String>,
    pub text_records: HashMap<String, String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DecentralizedScheme {
    Ipfs,
    Ipns,
}

impl DecentralizedScheme {
    fn as_str(self) -> &'static str {
        match self {
            Self::Ipfs => "ipfs",
            Self::Ipns => "ipns",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct DecentralizedUrl {
    scheme: DecentralizedScheme,
    root: String,
    path: String,
}

impl DecentralizedUrl {
    fn parse(url: &str, fallback_scheme: DecentralizedScheme) -> Result<Self> {
        let parsed =
            Url::parse(url).with_context(|| format!("invalid decentralized URL: {url}"))?;
        let scheme = match parsed.scheme() {
            "ipfs" => DecentralizedScheme::Ipfs,
            "ipns" => DecentralizedScheme::Ipns,
            "http" | "https" => fallback_scheme,
            other => return Err(anyhow!("unsupported decentralized scheme: {other}")),
        };

        let localhost_alias = format!("{}.localhost", scheme.as_str());
        let host = parsed.host_str().unwrap_or_default();
        let mut segments = parsed
            .path_segments()
            .map(|it| it.filter(|segment| !segment.is_empty()).collect::<Vec<_>>())
            .unwrap_or_default();

        let root = if !host.is_empty() && host != "localhost" && host != localhost_alias {
            host.to_string()
        } else {
            if matches!(segments.first(), Some(prefix) if *prefix == "ipfs" || *prefix == "ipns") {
                segments.remove(0);
            }
            (!segments.is_empty())
                .then_some(())
                .ok_or_else(|| anyhow!("missing decentralized content root"))?;
            segments.remove(0).to_string()
        };

        let path = segments.join("/");

        Ok(Self { scheme, root, path })
    }

    fn validate(&self, handler: &ProtocolHandler) -> Result<()> {
        if self.root.trim().is_empty() {
            return Err(anyhow!("missing decentralized content root"));
        }
        if self.scheme == DecentralizedScheme::Ipfs && !handler.is_valid_ipfs_hash(&self.root) {
            return Err(anyhow!("Invalid IPFS hash: {}", self.root));
        }
        Ok(())
    }

    fn ipfs_path(&self) -> String {
        let mut path = format!("/{}/{}", self.scheme.as_str(), self.root);
        if !self.path.is_empty() {
            path.push('/');
            path.push_str(&self.path);
        }
        path
    }

    fn index_path(&self) -> String {
        let mut path = self.ipfs_path();
        if !path.ends_with('/') {
            path.push('/');
        }
        path.push_str("index.html");
        path
    }

    fn display_url(&self) -> String {
        let mut url = format!("{}://{}", self.scheme.as_str(), self.root);
        if !self.path.is_empty() {
            url.push('/');
            url.push_str(&self.path);
        }
        url
    }

    fn display_directory_url(&self) -> String {
        let mut url = self.display_url();
        if !url.ends_with('/') {
            url.push('/');
        }
        url
    }

    fn href_for(&self, child: &str) -> String {
        let mut url = self.display_directory_url();
        url.push_str(child.trim_start_matches('/'));
        url
    }
}

impl ProtocolHandler {
    pub fn new() -> Self {
        Self {
            ipfs_gateway: DEFAULT_IPFS_GATEWAY.to_string(),
            ens_resolver: Some("https://cloudflare-eth.com".to_string()),
            ens_cache: std::sync::Arc::new(RwLock::new(HashMap::new())),
            local_ipfs: std::sync::Arc::new(OnceCell::new()),
        }
    }

    pub fn set_ipfs_gateway(&mut self, gateway: String) {
        self.ipfs_gateway = gateway;
    }

    pub fn set_ens_resolver(&mut self, resolver: Option<String>) {
        self.ens_resolver = resolver;
    }

    pub async fn handle_ipfs(&self, hash: &str) -> Result<IpfsContent> {
        let resource = DecentralizedUrl {
            scheme: DecentralizedScheme::Ipfs,
            root: hash
                .trim_start_matches("ipfs://")
                .trim_matches('/')
                .to_string(),
            path: String::new(),
        };
        resource.validate(self)?;
        self.load_decentralized_content(&resource).await
    }

    pub async fn handle_ipns(&self, name: &str) -> Result<IpfsContent> {
        let resource = DecentralizedUrl {
            scheme: DecentralizedScheme::Ipns,
            root: name
                .trim_start_matches("ipns://")
                .trim_matches('/')
                .to_string(),
            path: String::new(),
        };
        resource.validate(self)?;
        self.load_decentralized_content(&resource).await
    }

    pub async fn load_custom_protocol_url(
        &self,
        url: &str,
        fallback_scheme: &str,
    ) -> Result<IpfsContent> {
        let fallback_scheme = match fallback_scheme {
            "ipfs" => DecentralizedScheme::Ipfs,
            "ipns" => DecentralizedScheme::Ipns,
            other => return Err(anyhow!("unsupported decentralized protocol: {other}")),
        };
        let resource = DecentralizedUrl::parse(url, fallback_scheme)?;
        resource.validate(self)?;
        self.load_decentralized_content(&resource).await
    }

    pub async fn handle_ens(&self, name: &str) -> Result<String> {
        {
            let cache = self.ens_cache.read().await;
            if let Some(url) = cache.get(name) {
                return Ok(url.clone());
            }
        }

        let resolution = self.resolve_ens(name).await?;

        let target_url = if let Some(content_hash) = &resolution.content_hash {
            if content_hash.starts_with("ipfs://") || content_hash.starts_with("ipns://") {
                content_hash.clone()
            } else if content_hash.starts_with("Qm") || content_hash.starts_with("bafy") {
                format!("ipfs://{}", content_hash)
            } else {
                resolution
                    .text_records
                    .get("url")
                    .or_else(|| resolution.text_records.get("website"))
                    .cloned()
                    .unwrap_or_else(|| format!("https://{}", name))
            }
        } else {
            format!("https://{}", name)
        };

        {
            let mut cache = self.ens_cache.write().await;
            cache.insert(name.to_string(), target_url.clone());
        }

        Ok(target_url)
    }

    pub async fn resolve_url(&self, url: &str) -> Result<String> {
        if let Ok(parsed) = Url::parse(url) {
            match parsed.scheme() {
                "ipfs" => {
                    let resource = DecentralizedUrl::parse(url, DecentralizedScheme::Ipfs)?;
                    resource.validate(self)?;
                    Ok(resource.display_url())
                }
                "ipns" => {
                    let resource = DecentralizedUrl::parse(url, DecentralizedScheme::Ipns)?;
                    resource.validate(self)?;
                    Ok(resource.display_url())
                }
                "ens" => {
                    let name = parsed
                        .host_str()
                        .filter(|host| !host.is_empty())
                        .map(str::to_string)
                        .unwrap_or_else(|| parsed.path().trim_start_matches('/').to_string());
                    self.handle_ens(&name).await
                }
                _ => Ok(url.to_string()),
            }
        } else if url.ends_with(".eth") || url.ends_with(".crypto") || url.ends_with(".blockchain")
        {
            self.handle_ens(url).await
        } else {
            Ok(url.to_string())
        }
    }

    pub fn is_valid_ipfs_hash(&self, hash: &str) -> bool {
        if hash.starts_with("Qm") && hash.len() == 46 {
            true
        } else if hash.starts_with("bafy") || hash.starts_with("bafk") {
            hash.len() >= 50
        } else {
            false
        }
    }

    async fn load_decentralized_content(&self, resource: &DecentralizedUrl) -> Result<IpfsContent> {
        let node = self.local_ipfs().await?;
        let requested_path = resource.ipfs_path();

        if let Ok(bytes) = self.read_unixfs_file(node, &requested_path).await {
            return Ok(IpfsContent {
                hash: resource.display_url(),
                content_type: guess_content_type(resource.path.as_str(), &bytes),
                size: Some(bytes.len() as u64),
                data: bytes,
            });
        }

        if let Ok(bytes) = self.read_unixfs_file(node, &resource.index_path()).await {
            return Ok(IpfsContent {
                hash: resource.display_url(),
                content_type: "text/html; charset=utf-8".to_string(),
                size: Some(bytes.len() as u64),
                data: bytes,
            });
        }

        let listing = self.render_directory_listing(node, resource).await?;
        Ok(IpfsContent {
            hash: resource.display_url(),
            content_type: "text/html; charset=utf-8".to_string(),
            size: Some(listing.len() as u64),
            data: listing.into_bytes(),
        })
    }

    async fn local_ipfs(&self) -> Result<&LocalIpfsNode> {
        self.local_ipfs
            .get_or_try_init(|| async { LocalIpfsNode::start().await })
            .await
    }

    async fn read_unixfs_file(&self, node: &LocalIpfsNode, path: &str) -> Result<Vec<u8>> {
        let path = path
            .parse::<IpfsPath>()
            .with_context(|| format!("invalid IPFS path: {path}"))?;
        let bytes = node
            .ipfs
            .cat_unixfs(path)
            .timeout(LOCAL_IPFS_TIMEOUT)
            .await
            .context("failed to read UnixFS content")?;
        Ok(bytes.to_vec())
    }

    async fn render_directory_listing(
        &self,
        node: &LocalIpfsNode,
        resource: &DecentralizedUrl,
    ) -> Result<String> {
        let path = resource
            .ipfs_path()
            .parse::<IpfsPath>()
            .with_context(|| format!("invalid IPFS path: {}", resource.ipfs_path()))?;
        let entries = node
            .ipfs
            .ls_unixfs(path)
            .timeout(LOCAL_IPFS_TIMEOUT)
            .await
            .context("failed to list UnixFS directory")?;

        let mut items = Vec::new();
        for entry in entries {
            match entry {
                UnixfsEntry::RootDirectory { .. } => {}
                UnixfsEntry::Directory { path, .. } => {
                    let href = resource.href_for(&path);
                    items.push(format!(
                        "<li><a href=\"{}\">{}/</a></li>",
                        escape_html(&href),
                        escape_html(&path)
                    ));
                }
                UnixfsEntry::File { file, size, .. } => {
                    let href = resource.href_for(&file);
                    items.push(format!(
                        "<li><a href=\"{}\">{}</a> <span>{} bytes</span></li>",
                        escape_html(&href),
                        escape_html(&file),
                        size
                    ));
                }
                UnixfsEntry::Error { error } => {
                    return Err(error).context("failed to render directory listing")
                }
            }
        }

        if items.is_empty() {
            items.push("<li>This IPFS directory is empty.</li>".to_string());
        }

        Ok(format!(
            "<!doctype html><html><head><meta charset=\"utf-8\"><title>{title}</title><style>\
             body{{font-family:ui-monospace,Menlo,Monaco,monospace;background:#f6f3ea;color:#17120f;padding:24px;}}\
             h1{{font-size:18px;margin:0 0 8px;}}\
             p{{margin:0 0 16px;color:#5b5147;}}\
             ul{{list-style:none;padding:0;margin:0;display:grid;gap:10px;}}\
             li{{padding:10px 12px;border:1px solid #d6cdbf;border-radius:10px;background:#fffdf7;display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap;}}\
             a{{color:#6b2d00;text-decoration:none;word-break:break-all;}}\
             span{{color:#6f6358;font-size:12px;}}</style></head><body>\
             <h1>{title}</h1><p>Served by the embedded IPFS node.</p><ul>{items}</ul></body></html>",
            title = escape_html(&resource.display_directory_url()),
            items = items.join("")
        ))
    }

    async fn resolve_ens(&self, name: &str) -> Result<EnsResolution> {
        if let Some(resolver_url) = &self.ens_resolver {
            let client = reqwest::Client::new();
            let namehash = self.namehash(name);

            let resolver_request = serde_json::json!({
                "jsonrpc": "2.0",
                "method": "eth_call",
                "params": [{
                    "to": "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e",
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
        for key in &keys {
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

    fn namehash(&self, name: &str) -> String {
        use sha3::{Digest, Keccak256};

        let mut hash = [0u8; 32];

        if !name.is_empty() {
            let labels: Vec<&str> = name.split('.').collect();
            for label in labels.iter().rev() {
                let mut hasher = Keccak256::new();
                hasher.update(hash);
                hasher.update(Keccak256::digest(label.as_bytes()));
                hash = hasher.finalize().into();
            }
        }

        hex::encode(hash)
    }

    fn decode_content_hash(&self, hex_data: &str) -> String {
        if hex_data.len() > 8 {
            let codec = &hex_data[0..8];
            let hash_data = &hex_data[8..];

            match codec {
                "e3010170" => {
                    if let Ok(decoded) = hex::decode(hash_data) {
                        let hash = bs58::encode(decoded).into_string();
                        return format!("ipfs://{}", hash);
                    }
                }
                "e5010172" => {
                    if let Ok(decoded) = hex::decode(hash_data) {
                        let hash = bs58::encode(decoded).into_string();
                        return format!("ipns://{}", hash);
                    }
                }
                _ => {}
            }
        }

        format!("0x{}", hex_data)
    }

    pub async fn clear_caches(&self) {
        let mut ens_cache = self.ens_cache.write().await;
        ens_cache.clear();
    }
}

impl Default for ProtocolHandler {
    fn default() -> Self {
        Self::new()
    }
}

impl LocalIpfsNode {
    async fn start() -> Result<Self> {
        let repo_path = local_ipfs_repo_path()?;
        std::fs::create_dir_all(&repo_path)
            .with_context(|| format!("failed to create IPFS repo at {}", repo_path.display()))?;

        let mut builder = UninitializedIpfsDefault::new()
            .set_storage_type(StorageType::Disk(repo_path))
            .with_default()
            .set_default_listener();
        #[cfg(not(target_arch = "wasm32"))]
        {
            builder = builder.with_mdns();
        }
        for addr in BOOTSTRAP_NODES {
            if let Ok(addr) = addr.parse() {
                builder = builder.add_bootstrap(addr);
            }
        }

        let ipfs = builder
            .start()
            .await
            .context("failed to start embedded IPFS node")?;
        if let Err(err) = ipfs.bootstrap().await {
            log::warn!("embedded IPFS bootstrap failed: {err}");
        }
        Ok(Self { ipfs })
    }
}

fn local_ipfs_repo_path() -> Result<PathBuf> {
    let base = std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(PathBuf::from)
        .or_else(|| std::env::current_dir().ok())
        .ok_or_else(|| anyhow!("Unable to resolve IPFS repository directory"))?;

    Ok(base.join(".advatar").join("ipfs"))
}

fn guess_content_type(path: &str, data: &[u8]) -> String {
    match path
        .rsplit('.')
        .next()
        .unwrap_or_default()
        .to_ascii_lowercase()
        .as_str()
    {
        "html" | "htm" => "text/html; charset=utf-8".to_string(),
        "css" => "text/css; charset=utf-8".to_string(),
        "js" | "mjs" => "text/javascript; charset=utf-8".to_string(),
        "json" => "application/json".to_string(),
        "svg" => "image/svg+xml".to_string(),
        "png" => "image/png".to_string(),
        "jpg" | "jpeg" => "image/jpeg".to_string(),
        "gif" => "image/gif".to_string(),
        "webp" => "image/webp".to_string(),
        "avif" => "image/avif".to_string(),
        "ico" => "image/x-icon".to_string(),
        "wasm" => "application/wasm".to_string(),
        "txt" => "text/plain; charset=utf-8".to_string(),
        "pdf" => "application/pdf".to_string(),
        "mp4" => "video/mp4".to_string(),
        "webm" => "video/webm".to_string(),
        "mp3" => "audio/mpeg".to_string(),
        "ogg" => "audio/ogg".to_string(),
        "wav" => "audio/wav".to_string(),
        _ => sniff_content_type(data),
    }
}

fn sniff_content_type(data: &[u8]) -> String {
    let lower = String::from_utf8_lossy(&data[..data.len().min(256)]).to_ascii_lowercase();
    if lower.contains("<!doctype html") || lower.contains("<html") {
        "text/html; charset=utf-8".to_string()
    } else if std::str::from_utf8(data).is_ok() {
        "text/plain; charset=utf-8".to_string()
    } else {
        "application/octet-stream".to_string()
    }
}

fn escape_html(raw: &str) -> String {
    raw.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

#[cfg(test)]
mod tests {
    use super::*;

    const TEST_CID: &str = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";

    #[test]
    fn test_ipfs_hash_validation() {
        let handler = ProtocolHandler::new();
        assert!(handler.is_valid_ipfs_hash("QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o"));
        assert!(handler.is_valid_ipfs_hash(TEST_CID));
        assert!(!handler.is_valid_ipfs_hash("invalid"));
    }

    #[test]
    fn test_namehash() {
        let handler = ProtocolHandler::new();
        assert_eq!(
            handler.namehash(""),
            "0000000000000000000000000000000000000000000000000000000000000000"
        );

        let eth_hash = handler.namehash("eth");
        assert!(!eth_hash.is_empty());
        assert_eq!(eth_hash.len(), 64);
    }

    #[test]
    fn test_decentralized_url_parses_native_ipfs_host() {
        let parsed = DecentralizedUrl::parse(
            &format!("ipfs://{TEST_CID}/site/index.html"),
            DecentralizedScheme::Ipfs,
        )
        .unwrap();

        assert_eq!(parsed.root, TEST_CID);
        assert_eq!(parsed.path, "site/index.html");
        assert_eq!(
            parsed.ipfs_path(),
            format!("/ipfs/{TEST_CID}/site/index.html")
        );
    }

    #[test]
    fn test_decentralized_url_parses_localhost_variant() {
        let parsed = DecentralizedUrl::parse(
            &format!("ipfs://localhost/ipfs/{TEST_CID}/assets/app.js"),
            DecentralizedScheme::Ipfs,
        )
        .unwrap();

        assert_eq!(parsed.root, TEST_CID);
        assert_eq!(parsed.path, "assets/app.js");
    }

    #[tokio::test]
    async fn test_resolve_url_preserves_ipfs_scheme() {
        let handler = ProtocolHandler::new();
        let resolved = handler
            .resolve_url(&format!("ipfs://{TEST_CID}/index.html"))
            .await
            .unwrap();
        assert_eq!(resolved, format!("ipfs://{TEST_CID}/index.html"));
    }

    #[tokio::test]
    async fn test_protocol_handler_creation() {
        let handler = ProtocolHandler::new();
        assert_eq!(handler.ipfs_gateway, DEFAULT_IPFS_GATEWAY);
        assert!(handler.ens_resolver.is_some());
    }

    #[test]
    fn test_guess_content_type_prefers_html() {
        assert_eq!(
            guess_content_type("index.html", b"<!doctype html><html></html>"),
            "text/html; charset=utf-8"
        );
    }
}
