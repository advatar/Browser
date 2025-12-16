use crate::error::{Result, UpdaterError};
use async_trait::async_trait;
use cid::Cid;
use reqwest::{Client, Url};

/// Abstraction over fetching content from IPFS.
#[async_trait]
pub trait IpfsFetcher: Send + Sync {
    /// Fetch the bytes for the given CID (and optional UnixFS path) from IPFS.
    async fn fetch_bytes(&self, cid: &Cid, path: Option<&str>) -> Result<Vec<u8>>;
}

/// Builder for [`IpfsGatewayClient`].
#[derive(Default)]
pub struct IpfsGatewayClientBuilder {
    base: Option<Url>,
    client: Option<Client>,
}

impl IpfsGatewayClientBuilder {
    /// Set the base gateway URL (e.g. `https://w3s.link/` or `http://127.0.0.1:8080/`).
    pub fn base_url(mut self, url: Url) -> Self {
        self.base = Some(url);
        self
    }

    /// Provide a custom reqwest client instance.
    pub fn client(mut self, client: Client) -> Self {
        self.client = Some(client);
        self
    }

    /// Build the client.
    pub fn build(self) -> Result<IpfsGatewayClient> {
        let base = self
            .base
            .unwrap_or_else(|| Url::parse("https://ipfs.io/").expect("default IPFS gateway URL"));
        let client = self.client.unwrap_or_else(Client::new);

        Ok(IpfsGatewayClient { base, client })
    }
}

/// Simple IPFS gateway-based fetcher.
#[derive(Clone)]
pub struct IpfsGatewayClient {
    base: Url,
    client: Client,
}

impl IpfsGatewayClient {
    /// Create a new builder.
    pub fn builder() -> IpfsGatewayClientBuilder {
        IpfsGatewayClientBuilder::default()
    }

    fn content_url(&self, cid: &Cid, path: Option<&str>) -> Result<Url> {
        let mut slug = format!("ipfs/{cid}");
        if let Some(path) = path {
            let sanitized = path.trim_start_matches('/');
            if !sanitized.is_empty() {
                slug.push('/');
                slug.push_str(sanitized);
            }
        }

        self.base
            .join(&slug)
            .map_err(|err| UpdaterError::validation(format!("invalid gateway URL: {err}")))
    }
}

#[async_trait]
impl IpfsFetcher for IpfsGatewayClient {
    async fn fetch_bytes(&self, cid: &Cid, path: Option<&str>) -> Result<Vec<u8>> {
        let url = self.content_url(cid, path)?;
        let response = self.client.get(url).send().await?.error_for_status()?;
        let bytes = response.bytes().await?;
        Ok(bytes.to_vec())
    }
}
