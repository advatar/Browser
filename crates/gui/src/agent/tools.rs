use std::sync::{Arc, Mutex as StdMutex};

use ai_agent::{McpTool, McpToolDescription, McpToolError, McpToolResult};
use async_trait::async_trait;
use hex;
use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};
use sha3::{Digest, Keccak256};
use std::fs::{create_dir_all, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use tauri::{AppHandle, Manager, Wry};

use crate::agent::iproov::{CartMandate, IproovServices};
use crate::app_state::AppState;
use crate::browser_engine::BrowserEngine;
use crate::wallet_store::{WalletOwner, WalletStore};

const CONTENT_WEBVIEW_LABEL: &str = "content";

fn build_description(name: &str, description: &str, schema: Value) -> McpToolDescription {
    McpToolDescription::new(name.to_string(), description.to_string(), schema)
}

pub fn build_url_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "url": { "type": "string", "description": "Absolute or relative URL to load" },
            "new_tab": { "type": "boolean", "description": "Open in a new tab instead of the active one" }
        },
        "required": ["url"],
        "additionalProperties": false
    })
}

pub fn build_dom_query_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "selector": { "type": "string", "description": "CSS selector to match in the active page" },
            "limit": { "type": "integer", "minimum": 1, "description": "Maximum number of matches to return" }
        },
        "required": ["selector"],
        "additionalProperties": false
    })
}

pub fn build_tabs_schema() -> Value {
    json!({
        "type": "object",
        "properties": {},
        "additionalProperties": false
    })
}

pub fn build_wallet_schema() -> Value {
    json!({
        "type": "object",
        "properties": {},
        "additionalProperties": false
    })
}

pub fn build_wallet_spend_schema() -> Value {
    json!({
        "type": "object",
        "required": ["to", "amount", "chain"],
        "properties": {
            "to": { "type": "string", "description": "Recipient address" },
            "amount": { "type": "number", "minimum": 0, "description": "Amount to spend (smallest unit for the chain)" },
            "chain": { "type": "string", "description": "Chain identifier (e.g., eth, polygon, substrate)" },
            "memo": { "type": "string", "description": "Optional memo for the approval prompt" },
            "gas_price": { "type": "number", "minimum": 0, "description": "Override gas price (wei)" },
            "gas_limit": { "type": "integer", "minimum": 21000, "description": "Override gas limit" },
            "nonce": { "type": "integer", "minimum": 0, "description": "Override transaction nonce" }
        },
        "additionalProperties": false
    })
}

#[derive(Clone)]
pub struct NavigateTool {
    app_handle: AppHandle<Wry>,
    description: McpToolDescription,
}

impl NavigateTool {
    pub fn new(app_handle: AppHandle<Wry>) -> Self {
        Self {
            app_handle,
            description: build_description(
                "browser.navigate",
                "Navigate the content webview to the provided URL",
                build_url_schema(),
            ),
        }
    }

    fn resolve_webview(&self) -> Result<tauri::webview::Webview<Wry>, McpToolError> {
        self.app_handle
            .get_webview(CONTENT_WEBVIEW_LABEL)
            .ok_or_else(|| McpToolError::Invocation("Content webview is not available".into()))
    }
}

#[derive(Debug, Deserialize)]
struct NavigateArgs {
    url: String,
    #[serde(default)]
    new_tab: bool,
}

#[async_trait]
impl McpTool for NavigateTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: NavigateArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;

        if params.url.trim().is_empty() {
            return Err(McpToolError::InvalidInput("url must not be empty".into()));
        }

        let webview = self.resolve_webview()?;

        // Update the shared state for current URL
        if let Some(state) = self.app_handle.try_state::<AppState>() {
            if let Ok(mut current_url) = state.current_url.lock() {
                *current_url = params.url.clone();
            }
        }

        if params.url.trim_start().to_ascii_lowercase().starts_with("about:") {
            return Ok(McpToolResult {
                content: json!({
                    "status": "internal",
                    "url": params.url,
                    "new_tab": params.new_tab
                }),
                metadata: Default::default(),
            });
        }

        let target = url::Url::parse(params.url.trim())
            .or_else(|_| url::Url::parse(&format!("https://{}", params.url.trim())))
            .map_err(|e| McpToolError::InvalidInput(format!("invalid url: {e}")))?;

        webview
            .navigate(target)
            .map_err(|e| McpToolError::Invocation(format!("navigation failed: {e}")))?;

        Ok(McpToolResult {
            content: json!({
                "status": "navigated",
                "url": params.url,
                "new_tab": params.new_tab
            }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct DomQueryTool {
    app_handle: AppHandle<Wry>,
    description: McpToolDescription,
}

impl DomQueryTool {
    pub fn new(app_handle: AppHandle<Wry>) -> Self {
        Self {
            app_handle,
            description: build_description(
                "browser.dom_query",
                "Query the active document using a CSS selector (not available for isolated native content webviews)",
                build_dom_query_schema(),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct DomQueryArgs {
    selector: String,
    #[serde(default)]
    limit: Option<usize>,
}

#[async_trait]
impl McpTool for DomQueryTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: DomQueryArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        if params.selector.trim().is_empty() {
            return Err(McpToolError::InvalidInput(
                "selector must not be empty".into(),
            ));
        }

        // Web content is rendered in an isolated native child webview (no iframe and no IPC
        // capabilities). That prevents us from safely extracting DOM data via JS + IPC.
        //
        // If we need this in the future, implement a dedicated DOM snapshot bridge with a tight
        // allowlist and origin isolation.
        Err(McpToolError::Invocation(
            "DOM querying is not available for isolated native content webviews".into(),
        ))
    }
}

#[derive(Clone)]
pub struct TabsTool {
    browser_engine: Arc<BrowserEngine>,
    description: McpToolDescription,
}

impl TabsTool {
    pub fn new(browser_engine: Arc<BrowserEngine>) -> Self {
        Self {
            browser_engine,
            description: build_description(
                "browser.tabs",
                "List the open tabs and their metadata",
                build_tabs_schema(),
            ),
        }
    }
}

#[async_trait]
impl McpTool for TabsTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, _args: Value) -> Result<McpToolResult, McpToolError> {
        let tabs = self
            .browser_engine
            .get_tabs()
            .map_err(|e| McpToolError::Invocation(format!("failed to fetch tabs: {e}")))?;
        Ok(McpToolResult {
            content: json!({
                "tabs": tabs,
            }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct WalletInfoTool {
    store: Arc<StdMutex<WalletStore>>,
    owner: WalletOwner,
    description: McpToolDescription,
}

impl WalletInfoTool {
    pub fn new(store: Arc<StdMutex<WalletStore>>, owner: WalletOwner) -> Self {
        Self {
            store,
            owner,
            description: build_description(
                "wallet.info",
                "Inspect the assigned wallet keys and policy for this agent",
                build_wallet_schema(),
            ),
        }
    }
}

#[async_trait]
impl McpTool for WalletInfoTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, _args: Value) -> Result<McpToolResult, McpToolError> {
        let snapshot = {
            let mut store = self
                .store
                .lock()
                .map_err(|_| McpToolError::Invocation("wallet store mutex poisoned".into()))?;

            match &self.owner {
                WalletOwner::User => {
                    let _ = store
                        .ensure_user_profile()
                        .map_err(|e| McpToolError::Invocation(format!("{}", e)))?;
                }
                WalletOwner::Agent(id) => {
                    let _ = store
                        .ensure_agent_profile(id)
                        .map_err(|e| McpToolError::Invocation(format!("{}", e)))?;
                }
            }

            store
                .snapshot(&self.owner)
                .ok_or_else(|| McpToolError::Invocation("wallet snapshot unavailable".into()))?
        };

        let owner_label = match &snapshot.owner {
            WalletOwner::User => "user".to_string(),
            WalletOwner::Agent(id) => format!("agent:{}", id),
        };

        Ok(McpToolResult {
            content: json!({
                "owner": owner_label,
                "label": snapshot.label,
                "address": snapshot.address,
                "policy": snapshot.policy,
                "is_initialized": snapshot.is_initialized,
                "remaining_daily": snapshot.remaining_daily,
            }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct WalletSpendTool {
    store: Arc<StdMutex<WalletStore>>,
    owner: WalletOwner,
    description: McpToolDescription,
}

impl WalletSpendTool {
    pub fn new(store: Arc<StdMutex<WalletStore>>, owner: WalletOwner) -> Self {
        Self {
            store,
            owner,
            description: build_description(
                "wallet.spend",
                "Request to spend from the assigned wallet respecting policy",
                build_wallet_spend_schema(),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct WalletSpendArgs {
    to: String,
    amount: f64,
    chain: String,
    #[serde(default)]
    memo: Option<String>,
    #[serde(default)]
    gas_price: Option<u64>,
    #[serde(default)]
    gas_limit: Option<u64>,
    #[serde(default)]
    nonce: Option<u64>,
}

#[async_trait]
impl McpTool for WalletSpendTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: WalletSpendArgs = serde_json::from_value(args.clone())
            .map_err(|e| McpToolError::InvalidInput(format!("invalid spend args: {e}")))?;
        if params.amount < 0.0 {
            return Err(McpToolError::InvalidInput(
                "amount must be non-negative".into(),
            ));
        }

        let (decision, signed, seed) = {
            let mut store = self
                .store
                .lock()
                .map_err(|_| McpToolError::Invocation("wallet store mutex poisoned".into()))?;
            let decision = store
                .evaluate_spend(&self.owner, params.amount as u128, &params.chain)
                .map_err(|e| McpToolError::Invocation(format!("{}", e)))?;
            if !decision.permitted {
                return Err(McpToolError::Invocation(
                    decision
                        .reason
                        .unwrap_or_else(|| "spend blocked by policy".into()),
                ));
            }

            let mut hasher = Keccak256::new();
            hasher.update(params.to.as_bytes());
            hasher.update(params.amount.to_le_bytes());
            hasher.update(params.chain.as_bytes());
            if let Some(memo) = &params.memo {
                hasher.update(memo.as_bytes());
            }
            let preimage = hasher.finalize();

            let (address, signature) = store
                .sign_payload(&self.owner, &preimage)
                .map_err(|e| McpToolError::Invocation(format!("{}", e)))?;
            let (seed, _) = store
                .seed_for_owner(&self.owner)
                .map_err(|e| McpToolError::Invocation(format!("{}", e)))?;
            (decision, (address, signature), seed)
        };

        let tx_hash = {
            let mut hasher = Keccak256::new();
            hasher.update(&signed.1);
            hex::encode(hasher.finalize())
        };

        let intent = BroadcastIntent {
            chain: params.chain.clone(),
            to: params.to.clone(),
            amount: params.amount,
            from: signed.0.clone(),
            signature: hex::encode(&signed.1),
            memo: params.memo.clone(),
            tx_hash: tx_hash.clone(),
            gas_price: params.gas_price,
            gas_limit: params.gas_limit,
            nonce: params.nonce,
        };

        let broadcasted = record_local_broadcast(&intent)
            || broadcast_signed_intent(&intent, &seed, &params.chain).await;
        let network_hash = intent.tx_hash.clone();

        Ok(McpToolResult {
            content: json!({
                "status": "signed",
                "to": params.to,
                "amount": params.amount,
                "chain": params.chain,
                "memo": params.memo,
                "from": signed.0,
                "signature": hex::encode(signed.1),
                "tx_hash": tx_hash,
                "remaining_daily": decision.remaining_daily,
                "policy": decision.policy,
                "requires_approval": decision.requires_approval,
                "broadcasted": broadcasted,
                "network_tx_hash": network_hash,
            }),
            metadata: Default::default(),
        })
    }
}

#[derive(serde::Serialize)]
struct BroadcastIntent {
    chain: String,
    to: String,
    amount: f64,
    from: String,
    signature: String,
    memo: Option<String>,
    tx_hash: String,
    gas_price: Option<u64>,
    gas_limit: Option<u64>,
    nonce: Option<u64>,
}

fn broadcast_log_path() -> Option<PathBuf> {
    let mut base = std::env::var_os("HOME").map(PathBuf::from)?;
    base.push(".advatar");
    base.push("broadcasts.jsonl");
    Some(base)
}

fn record_local_broadcast(intent: &BroadcastIntent) -> bool {
    match broadcast_log_path() {
        Some(path) => {
            if let Some(parent) = path.parent() {
                let _ = create_dir_all(parent);
            }
            if let Ok(mut file) = OpenOptions::new()
                .create(true)
                .append(true)
                .open(path)
            {
                if let Ok(line) = serde_json::to_string(intent) {
                    let _ = writeln!(file, "{}", line);
                    return true;
                }
            }
            false
        }
        None => false,
    }
}

fn broadcast_endpoint() -> Option<String> {
    std::env::var("ADVATAR_BROADCAST_ENDPOINT").ok()
}

async fn broadcast_signed_intent(intent: &BroadcastIntent, seed: &[u8; 32], chain: &str) -> bool {
    if chain.starts_with("eth") {
        return broadcast_eth(intent, seed).await.unwrap_or(false);
    }

    if let Some(url) = broadcast_endpoint() {
        let client = Client::new();
        if let Ok(resp) = client.post(url).json(intent).send().await {
            return resp.status().is_success();
        }
    }

    false
}

async fn broadcast_eth(intent: &BroadcastIntent, seed: &[u8; 32]) -> anyhow::Result<bool> {
    use ethers_core::types::transaction::eip2718::TypedTransaction;
    use ethers_core::types::{Address, Bytes, TransactionRequest, U256};
    use ethers_providers::{Http, Middleware, Provider};
    use ethers_signers::{LocalWallet, Signer};
    use std::str::FromStr;

    let rpc = std::env::var("ADVATAR_ETH_RPC")
        .or_else(|_| std::env::var("ETH_RPC_URL"))
        .map_err(|_| anyhow::anyhow!("ADVATAR_ETH_RPC/ETH_RPC_URL not set"))?;
    let provider = Provider::<Http>::try_from(rpc)?;

    let chain_id = provider.get_chainid().await?.as_u64();
    let to = Address::from_str(&intent.to)?;
    let from = Address::from_str(&intent.from)?;
    let value = U256::from(intent.amount as u128);

    let gas_price = match intent.gas_price {
        Some(gp) => U256::from(gp),
        None => provider.get_gas_price().await?,
    };
    let gas_limit = U256::from(intent.gas_limit.unwrap_or(21_000));

    let nonce = match intent.nonce {
        Some(n) => U256::from(n),
        None => provider.get_transaction_count(from, None).await?,
    };

    let mut tx = TransactionRequest::new()
        .to(to)
        .from(from)
        .value(value)
        .gas(gas_limit)
        .gas_price(gas_price)
        .nonce(nonce);

    let mut typed = TypedTransaction::Legacy(tx);
    typed.set_chain_id(chain_id);

    let signer = LocalWallet::from_bytes(seed)?.with_chain_id(chain_id);
    let sig = signer.sign_transaction(&typed).await?;
    let rlp = typed.rlp_signed(&sig);
    let pending = provider.send_raw_transaction(Bytes::from(rlp)).await?;
    let _ = pending.await; // wait for inclusion; ignore errors
    Ok(true)
}

pub fn build_gateway_create_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "policy": { "type": "string", "default": "agent_identity+pop" },
            "amount": { "type": "number", "description": "Purchase amount in dollars" },
            "amount_cents": { "type": "integer", "description": "Purchase amount in cents" },
            "sku": { "type": "string" },
            "metadata": { "type": "object" }
        },
        "additionalProperties": false
    })
}

pub fn build_gateway_request_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "request_id": { "type": "string" },
            "agent_id": { "type": "string" },
            "audience": { "type": "string", "default": "vendor.example" }
        },
        "required": ["request_id", "agent_id"],
        "additionalProperties": false
    })
}

pub fn build_gateway_await_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "request_id": { "type": "string" }
        },
        "required": ["request_id"],
        "additionalProperties": false
    })
}

pub fn build_gateway_introspect_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "decision_jwt": { "type": "string" }
        },
        "required": ["decision_jwt"],
        "additionalProperties": false
    })
}

pub fn build_cart_id_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "cart_id": { "type": "string" }
        },
        "required": ["cart_id"],
        "additionalProperties": false
    })
}

pub fn build_place_order_schema() -> Value {
    json!({
        "type": "object",
        "properties": {
            "cart_id": { "type": "string" },
            "mandate": { "type": "object" },
            "decision_jwt": { "type": "string" }
        },
        "required": ["cart_id"],
        "additionalProperties": false
    })
}

fn default_policy() -> String {
    "agent_identity+pop".to_string()
}

#[derive(Clone)]
pub struct GatewayCreatePresentationTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl GatewayCreatePresentationTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "gateway.create_presentation",
                "Create an AgentGateway presentation request",
                build_gateway_create_schema(),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct CreatePresentationArgs {
    #[serde(default = "default_policy")]
    policy: String,
    amount_cents: Option<u64>,
    amount: Option<f64>,
    sku: Option<String>,
    #[serde(default)]
    metadata: Option<Value>,
}

#[async_trait]
impl McpTool for GatewayCreatePresentationTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: CreatePresentationArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;

        let amount_cents = params
            .amount_cents
            .or_else(|| params.amount.map(|d| (d * 100.0) as u64))
            .unwrap_or(0);

        let info = self
            .service
            .create_presentation(
                params.policy,
                amount_cents,
                params.sku,
                params.metadata.unwrap_or(Value::Null),
            )
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;

        Ok(McpToolResult {
            content: json!({ "presentation": info }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct GatewayApprovePresentationTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl GatewayApprovePresentationTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "gateway.approve_presentation",
                "Approve a presentation request and return a decision JWT",
                build_gateway_request_schema(),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct ApproveRequestArgs {
    request_id: String,
    agent_id: String,
    #[serde(default = "default_audience")]
    audience: String,
}

fn default_audience() -> String {
    "vendor.example".to_string()
}

#[async_trait]
impl McpTool for GatewayApprovePresentationTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: ApproveRequestArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        let token = self
            .service
            .approve_presentation(&params.request_id, &params.agent_id, &params.audience)
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;
        Ok(McpToolResult {
            content: json!({ "decision": token }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct GatewayAwaitDecisionTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl GatewayAwaitDecisionTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "gateway.await_decision",
                "Fetch the decision for a presentation request",
                build_gateway_await_schema(),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct AwaitArgs {
    request_id: String,
}

#[derive(Debug, Deserialize)]
struct CartArgs {
    cart_id: String,
}

#[async_trait]
impl McpTool for GatewayAwaitDecisionTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: AwaitArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        let decision = self
            .service
            .await_decision(&params.request_id)
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;
        Ok(McpToolResult {
            content: json!({ "decision": decision }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct GatewayIntrospectTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl GatewayIntrospectTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "gateway.introspect_decision",
                "Validate a decision JWT and return its claims",
                build_gateway_introspect_schema(),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct IntrospectArgs {
    decision_jwt: String,
}

#[async_trait]
impl McpTool for GatewayIntrospectTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: IntrospectArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        let info = self
            .service
            .introspect_decision(&params.decision_jwt)
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;
        Ok(McpToolResult {
            content: info,
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct MerchantQuoteCartTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl MerchantQuoteCartTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "merchant.quote_cart",
                "Quote a cart via the merchant A2A interface",
                json!({
                    "type": "object",
                    "properties": {
                        "term": { "type": "string" },
                        "sku": { "type": "string" },
                        "quantity": { "type": "integer", "minimum": 1 }
                    },
                    "additionalProperties": false
                }),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct QuoteArgs {
    term: Option<String>,
    sku: Option<String>,
    quantity: Option<u32>,
}

#[async_trait]
impl McpTool for MerchantQuoteCartTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: QuoteArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        let quote = self
            .service
            .quote_cart(params.term, params.sku, params.quantity)
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;
        Ok(McpToolResult {
            content: json!({ "quote": quote }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct GatewayApproveCartTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl GatewayApproveCartTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "gateway.approve_cart",
                "Approve an AP2 cart and return the cart mandate",
                build_cart_id_schema(),
            ),
        }
    }
}

#[async_trait]
impl McpTool for GatewayApproveCartTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: CartArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        let mandate = self
            .service
            .approve_cart(&params.cart_id)
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;
        Ok(McpToolResult {
            content: json!({ "mandate": mandate }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct GatewayFetchMandateTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl GatewayFetchMandateTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "gateway.fetch_mandate",
                "Fetch the latest cart mandate for an AP2 cart",
                build_cart_id_schema(),
            ),
        }
    }
}

#[async_trait]
impl McpTool for GatewayFetchMandateTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: CartArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        let mandate = self
            .service
            .fetch_mandate(&params.cart_id)
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;
        Ok(McpToolResult {
            content: json!({ "mandate": mandate }),
            metadata: Default::default(),
        })
    }
}

#[derive(Clone)]
pub struct MerchantPlaceOrderTool {
    service: Arc<IproovServices>,
    description: McpToolDescription,
}

impl MerchantPlaceOrderTool {
    pub fn new(service: Arc<IproovServices>) -> Self {
        Self {
            service,
            description: build_description(
                "merchant.place_order",
                "Place an order with the merchant, verifying mandates and decisions",
                build_place_order_schema(),
            ),
        }
    }
}

#[derive(Debug, Deserialize)]
struct PlaceOrderArgs {
    cart_id: String,
    mandate: Option<Value>,
    decision_jwt: Option<String>,
}

#[async_trait]
impl McpTool for MerchantPlaceOrderTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let params: PlaceOrderArgs = serde_json::from_value(args)
            .map_err(|e| McpToolError::InvalidInput(format!("invalid arguments: {e}")))?;
        let mandate = match params.mandate {
            Some(value) => Some(serde_json::from_value::<CartMandate>(value).map_err(|e| {
                McpToolError::InvalidInput(format!("invalid mandate payload: {e}"))
            })?),
            None => None,
        };
        let confirmation = self
            .service
            .place_order(&params.cart_id, mandate, params.decision_jwt)
            .await
            .map_err(|e| McpToolError::Invocation(e.to_string()))?;
        Ok(McpToolResult {
            content: json!({ "confirmation": confirmation }),
            metadata: Default::default(),
        })
    }
}
