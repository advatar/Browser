use std::collections::VecDeque;
use std::process::Stdio;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::mcp_profiles::McpConfigService;
use agent_core::CapabilityKind;
use ai_agent::{McpTool, McpToolDescription, McpToolError, McpToolResult};
use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use futures_util::{SinkExt, StreamExt};
use indexmap::IndexMap;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::net::TcpStream;
use tokio::process::{Child, ChildStdin, ChildStdout, Command};
use tokio::sync::Mutex;
use tokio::time::timeout;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::header::{HeaderName, HeaderValue};
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};
use tracing::warn;

const TOOL_CACHE_TTL: Duration = Duration::from_secs(120);
const MAX_LOG_ENTRIES: usize = 20;

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|dur| dur.as_millis() as u64)
        .unwrap_or_default()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum McpConfigValue {
    Plain(String),
    Secret(McpSecretValue),
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct McpSecretValue {
    #[serde(default = "secret_flag_true")]
    pub is_secret: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub secret_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
    #[serde(default, skip_serializing)]
    pub value: Option<String>,
}

fn secret_flag_true() -> bool {
    true
}

#[derive(Debug, Clone)]
pub struct McpResolvedServerConfig {
    pub id: String,
    pub name: Option<String>,
    pub endpoint: String,
    pub enabled: bool,
    pub headers: IndexMap<String, String>,
    pub timeout_ms: Option<u64>,
    pub default_capability: Option<String>,
    pub transport: McpTransportKind,
    pub program: Option<String>,
    pub args: Vec<String>,
    pub env: IndexMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpServerConfig {
    pub id: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub endpoint: String,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default)]
    pub headers: IndexMap<String, McpConfigValue>,
    #[serde(default)]
    pub timeout_ms: Option<u64>,
    #[serde(default)]
    pub default_capability: Option<String>,
    #[serde(default = "default_transport")]
    pub transport: McpTransportKind,
    #[serde(default)]
    pub program: Option<String>,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: IndexMap<String, McpConfigValue>,
}

fn default_enabled() -> bool {
    true
}

fn default_transport() -> McpTransportKind {
    McpTransportKind::Http
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum McpTransportKind {
    Http,
    Websocket,
    Stdio,
}

impl Default for McpTransportKind {
    fn default() -> Self {
        Self::Http
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum McpServerState {
    Disabled,
    Idle,
    Connecting,
    Ready,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpRuntimeStatus {
    pub state: McpServerState,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_error: Option<String>,
    pub last_updated_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_latency_ms: Option<u64>,
    #[serde(default)]
    pub success_count: u64,
    #[serde(default)]
    pub error_count: u64,
    #[serde(default)]
    pub recent_logs: Vec<McpLogEntry>,
}

impl McpRuntimeStatus {
    pub fn new(state: McpServerState) -> Self {
        Self {
            state,
            last_error: None,
            last_updated_ms: now_millis(),
            last_latency_ms: None,
            success_count: 0,
            error_count: 0,
            recent_logs: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum McpLogLevel {
    Info,
    Warn,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct McpLogEntry {
    pub timestamp_ms: u64,
    pub level: McpLogLevel,
    pub message: String,
}

#[derive(Clone)]
pub struct McpServerRegistry {
    clients: Arc<RwLock<Vec<Arc<McpServerClient>>>>,
    config_service: Arc<McpConfigService>,
}

impl McpServerRegistry {
    pub fn empty(config_service: Arc<McpConfigService>) -> Self {
        Self {
            clients: Arc::new(RwLock::new(Vec::new())),
            config_service,
        }
    }

    pub fn from_config_service(config_service: Arc<McpConfigService>) -> Result<Self> {
        let resolved = config_service.load_active_resolved_servers()?;
        let clients = Self::build_clients(resolved);
        Ok(Self {
            clients: Arc::new(RwLock::new(clients)),
            config_service,
        })
    }

    pub fn is_empty(&self) -> bool {
        self.clients
            .read()
            .expect("mcp clients poisoned")
            .is_empty()
    }

    pub async fn remote_tools(&self) -> Vec<(Arc<dyn McpTool>, Option<CapabilityKind>)> {
        let clients = {
            let guard = self.clients.read().expect("mcp clients poisoned");
            guard.clone()
        };

        let mut tools = Vec::new();
        for client in clients {
            match client.list_tools().await {
                Ok(descriptions) => {
                    for description in descriptions {
                        tools.push((
                            Arc::new(RemoteMcpTool::new(client.clone(), description))
                                as Arc<dyn McpTool>,
                            client.capability(),
                        ));
                    }
                }
                Err(err) => {
                    warn!(
                        target: "mcp_client",
                        server_id = client.id(),
                        error = %err,
                        "failed to fetch MCP tool descriptions"
                    );
                }
            }
        }
        tools
    }

    pub async fn reload_active(&self) -> Result<()> {
        let resolved = self.config_service.load_active_resolved_servers()?;
        let clients = Self::build_clients(resolved);
        let mut guard = self.clients.write().expect("mcp clients poisoned");
        *guard = clients;
        Ok(())
    }

    pub async fn status_snapshot(&self) -> Vec<(String, McpRuntimeStatus)> {
        let clients = {
            let guard = self.clients.read().expect("mcp clients poisoned");
            guard.clone()
        };

        let mut statuses = Vec::with_capacity(clients.len());
        for client in clients {
            statuses.push((client.id().to_string(), client.runtime_status().await));
        }
        statuses
    }

    pub async fn probe_resolved_config(
        &self,
        config: McpResolvedServerConfig,
    ) -> Result<McpRuntimeStatus> {
        if !config.enabled {
            return Ok(McpRuntimeStatus::new(McpServerState::Disabled));
        }

        if let Some(existing) = {
            let guard = self.clients.read().expect("mcp clients poisoned");
            guard
                .iter()
                .find(|client| client.id() == config.id)
                .cloned()
        } {
            let _ = existing.list_tools().await;
            return Ok(existing.runtime_status().await);
        }

        let client = Arc::new(McpServerClient::new(config)?);
        let _ = client.list_tools().await;
        Ok(client.runtime_status().await)
    }

    fn build_clients(configs: Vec<McpResolvedServerConfig>) -> Vec<Arc<McpServerClient>> {
        let mut clients = Vec::new();
        for config in configs.into_iter().filter(|cfg| cfg.enabled) {
            match McpServerClient::new(config) {
                Ok(client) => clients.push(Arc::new(client)),
                Err(err) => warn!(
                    target: "mcp_client",
                    error = %err,
                    "failed to initialise MCP server client"
                ),
            }
        }
        clients
    }
}

struct McpServerClient {
    id: String,
    name: Option<String>,
    default_capability: Option<CapabilityKind>,
    request_timeout: Duration,
    transport: McpTransport,
    request_id: AtomicU64,
    state: Mutex<McpClientState>,
    init_lock: Mutex<()>,
}

#[derive(Debug, Clone)]
struct ToolCache {
    tools: Vec<McpToolDescription>,
    fetched_at: Instant,
}

struct McpClientState {
    initialised: bool,
    cache_dirty: bool,
    cache: Option<ToolCache>,
    status: McpRuntimeStatus,
    logs: VecDeque<McpLogEntry>,
}

impl McpClientState {
    fn new() -> Self {
        Self {
            initialised: false,
            cache_dirty: false,
            cache: None,
            status: McpRuntimeStatus::new(McpServerState::Idle),
            logs: VecDeque::with_capacity(MAX_LOG_ENTRIES),
        }
    }

    fn push_log(&mut self, level: McpLogLevel, message: String) {
        if self.logs.len() == MAX_LOG_ENTRIES {
            self.logs.pop_front();
        }
        self.logs.push_back(McpLogEntry {
            timestamp_ms: now_millis(),
            level,
            message,
        });
        self.refresh_recent_logs();
    }

    fn refresh_recent_logs(&mut self) {
        self.status.recent_logs = self
            .logs
            .iter()
            .rev()
            .take(MAX_LOG_ENTRIES)
            .cloned()
            .collect();
    }
}

enum McpTransport {
    Http(HttpTransport),
    Websocket(WebSocketTransport),
    Stdio(StdioTransport),
}

struct HttpTransport {
    client: Client,
    endpoint: String,
    headers: IndexMap<String, String>,
}

struct WebSocketTransport {
    endpoint: String,
    headers: IndexMap<String, String>,
    state: Mutex<Option<WebSocketStream<MaybeTlsStream<TcpStream>>>>,
}

struct StdioTransport {
    program: String,
    args: Vec<String>,
    env: IndexMap<String, String>,
    state: Mutex<Option<StdioProcess>>,
}

struct StdioProcess {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

impl Drop for StdioProcess {
    fn drop(&mut self) {
        let _ = self.child.start_kill();
    }
}

impl McpServerClient {
    fn new(config: McpResolvedServerConfig) -> Result<Self> {
        let timeout = Duration::from_millis(config.timeout_ms.unwrap_or(20_000));
        let capability = config
            .default_capability
            .as_deref()
            .and_then(CapabilityKind::from_str);
        let transport = match config.transport {
            McpTransportKind::Http => {
                let endpoint = ensure_endpoint(&config, "http")?;
                let client = Client::builder()
                    .timeout(timeout)
                    .build()
                    .context("building HTTP client for MCP server")?;
                McpTransport::Http(HttpTransport {
                    client,
                    endpoint,
                    headers: config.headers.clone(),
                })
            }
            McpTransportKind::Websocket => {
                let endpoint = ensure_endpoint(&config, "websocket")?;
                McpTransport::Websocket(WebSocketTransport {
                    endpoint,
                    headers: config.headers.clone(),
                    state: Mutex::new(None),
                })
            }
            McpTransportKind::Stdio => {
                let program = config
                    .program
                    .or_else(|| {
                        if config.endpoint.is_empty() {
                            None
                        } else {
                            Some(config.endpoint.clone())
                        }
                    })
                    .ok_or_else(|| {
                        anyhow!(
                            "MCP transport=stdio for server {} requires `program` or `endpoint`",
                            config.id
                        )
                    })?;
                McpTransport::Stdio(StdioTransport {
                    program,
                    args: config.args.clone(),
                    env: config.env.clone(),
                    state: Mutex::new(None),
                })
            }
        };

        Ok(Self {
            id: config.id,
            name: config.name,
            default_capability: capability,
            request_timeout: timeout,
            transport,
            request_id: AtomicU64::new(1),
            state: Mutex::new(McpClientState::new()),
            init_lock: Mutex::new(()),
        })
    }

    fn id(&self) -> &str {
        &self.id
    }

    fn capability(&self) -> Option<CapabilityKind> {
        self.default_capability.clone()
    }

    async fn runtime_status(&self) -> McpRuntimeStatus {
        self.state.lock().await.status.clone()
    }

    async fn list_tools(&self) -> Result<Vec<McpToolDescription>> {
        self.ensure_initialised().await?;

        if let Some(cached) = self.cached_tools().await {
            return Ok(cached);
        }

        let result = self
            .send_request("tools/list", json!({}))
            .await
            .context("requesting MCP tool list")?;
        let response: ToolListResponse =
            serde_json::from_value(result).context("decoding MCP tool list response")?;
        let tools: Vec<McpToolDescription> = response
            .tools
            .into_iter()
            .map(|tool| {
                let mut description =
                    McpToolDescription::new(tool.name, tool.description, tool.input_schema);
                if !tool.metadata.is_empty() {
                    description.metadata = tool.metadata;
                }
                description
            })
            .collect();
        self.update_tool_cache(&tools).await;
        Ok(tools)
    }

    async fn call_tool(&self, name: &str, args: Value) -> Result<McpToolResult, McpToolError> {
        self.ensure_initialised()
            .await
            .map_err(|err| McpToolError::Invocation(err.to_string()))?;
        let payload = json!({
            "name": name,
            "arguments": args
        });
        let result = self
            .send_request("tools/call", payload)
            .await
            .map_err(|err| McpToolError::Invocation(err.to_string()))?;
        let response: ToolCallResponse = serde_json::from_value(result).map_err(|err| {
            McpToolError::Invocation(format!("invalid tool call response: {err}"))
        })?;
        Ok(McpToolResult {
            content: response.content,
            metadata: response.metadata.unwrap_or_default(),
        })
    }

    async fn ensure_initialised(&self) -> Result<()> {
        {
            let state = self.state.lock().await;
            if state.initialised {
                return Ok(());
            }
        }

        let _guard = self.init_lock.lock().await;
        {
            let state = self.state.lock().await;
            if state.initialised {
                return Ok(());
            }
        }

        self.update_status(McpServerState::Connecting, None).await;
        let params = json!({
            "clientInfo": {
                "name": "Advatar Browser",
                "version": env!("CARGO_PKG_VERSION"),
            },
            "capabilities": {
                "tools": { "listChanged": true }
            }
        });
        self.send_request("initialize", params)
            .await
            .context("initialising MCP connection")?;

        let mut state = self.state.lock().await;
        state.initialised = true;
        state.cache_dirty = true;
        state.status = McpRuntimeStatus::new(McpServerState::Ready);
        Ok(())
    }

    async fn cached_tools(&self) -> Option<Vec<McpToolDescription>> {
        let state = self.state.lock().await;
        if state.cache_dirty {
            return None;
        }
        state
            .cache
            .as_ref()
            .filter(|cache| cache.fetched_at.elapsed() < TOOL_CACHE_TTL)
            .map(|cache| cache.tools.clone())
    }

    async fn update_tool_cache(&self, tools: &[McpToolDescription]) {
        let mut state = self.state.lock().await;
        state.cache = Some(ToolCache {
            tools: tools.to_vec(),
            fetched_at: Instant::now(),
        });
        state.cache_dirty = false;
    }

    async fn mark_cache_dirty(&self) {
        let mut state = self.state.lock().await;
        state.cache_dirty = true;
    }

    async fn record_success(&self, method: &str, latency_ms: u64) {
        let mut state = self.state.lock().await;
        state.status.state = McpServerState::Ready;
        state.status.last_error = None;
        state.status.last_updated_ms = now_millis();
        state.status.last_latency_ms = Some(latency_ms);
        state.status.success_count = state.status.success_count.saturating_add(1);
        state.push_log(
            McpLogLevel::Info,
            format!("{method} succeeded in {latency_ms} ms"),
        );
    }

    async fn record_error(&self, method: &str, error: &str) {
        let mut state = self.state.lock().await;
        state.status.state = McpServerState::Error;
        state.status.last_error = Some(error.to_string());
        state.status.last_updated_ms = now_millis();
        state.status.error_count = state.status.error_count.saturating_add(1);
        state.push_log(
            McpLogLevel::Error,
            format!("{method} failed: {}", error.trim()),
        );
    }

    async fn update_status(&self, status: McpServerState, error: Option<String>) {
        let mut state_guard = self.state.lock().await;
        state_guard.status.state = status;
        state_guard.status.last_error = error.clone();
        state_guard.status.last_updated_ms = now_millis();
        if let Some(message) = error {
            state_guard.push_log(McpLogLevel::Warn, format!("Status change: {message}"));
        }
    }

    async fn send_request(&self, method: &str, params: Value) -> Result<Value> {
        let id = self.request_id.fetch_add(1, Ordering::SeqCst);
        let body = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        });

        let start = Instant::now();
        let result = match &self.transport {
            McpTransport::Http(transport) => self.send_via_http(transport, &body).await,
            McpTransport::Websocket(transport) => {
                self.send_via_websocket(transport, body.clone(), id).await
            }
            McpTransport::Stdio(transport) => {
                self.send_via_stdio(transport, body.clone(), id).await
            }
        };

        match result {
            Ok(payload) => match Self::extract_result(payload, &self.id) {
                Ok(result) => {
                    let latency_ms = start.elapsed().as_millis() as u64;
                    self.record_success(method, latency_ms).await;
                    Ok(result)
                }
                Err(err) => {
                    let msg = err.to_string();
                    self.record_error(method, &msg).await;
                    Err(err)
                }
            },
            Err(err) => {
                let msg = err.to_string();
                self.record_error(method, &msg).await;
                Err(err)
            }
        }
    }

    async fn send_via_http(&self, transport: &HttpTransport, body: &Value) -> Result<Value> {
        let mut request = transport.client.post(&transport.endpoint).json(body);
        for (key, value) in &transport.headers {
            request = request.header(key, value);
        }

        let response = request
            .send()
            .await
            .with_context(|| format!("request to MCP server {} failed", self.id))?;
        let status = response.status();
        let payload: Value = response
            .json()
            .await
            .with_context(|| format!("invalid MCP response from {}", self.id))?;

        if !status.is_success() {
            return Err(anyhow!(
                "MCP server {} returned HTTP {}: {}",
                self.id,
                status,
                payload
            ));
        }

        Ok(payload)
    }

    async fn send_via_websocket(
        &self,
        transport: &WebSocketTransport,
        body: Value,
        request_id: u64,
    ) -> Result<Value> {
        let mut stream = {
            let mut state = transport.state.lock().await;
            if let Some(stream) = state.take() {
                stream
            } else {
                transport
                    .connect()
                    .await
                    .with_context(|| format!("connecting to MCP websocket {}", self.id))?
            }
        };

        let send_result = stream
            .send(Message::Text(serde_json::to_string(&body)?))
            .await;
        if let Err(err) = send_result {
            return Err(anyhow!("failed to send websocket request: {err}"));
        }

        let response = self.await_websocket_response(&mut stream, request_id).await;

        match response {
            Ok(value) => {
                let mut state = transport.state.lock().await;
                *state = Some(stream);
                Ok(value)
            }
            Err(err) => {
                let _ = stream.close(None).await;
                Err(err)
            }
        }
    }

    async fn await_websocket_response(
        &self,
        stream: &mut WebSocketStream<MaybeTlsStream<TcpStream>>,
        request_id: u64,
    ) -> Result<Value> {
        loop {
            let next = timeout(self.request_timeout, stream.next())
                .await
                .map_err(|_| anyhow!("MCP server {} timed out waiting for response", self.id))?;

            match next {
                Some(Ok(Message::Text(text))) => {
                    let value: Value =
                        serde_json::from_str(&text).context("decoding websocket JSON payload")?;
                    if Self::matches_request(&value, request_id) {
                        return Ok(value);
                    }
                    self.handle_notification(&value).await;
                }
                Some(Ok(Message::Binary(data))) => {
                    let value: Value = serde_json::from_slice(&data)
                        .context("decoding websocket binary payload")?;
                    if Self::matches_request(&value, request_id) {
                        return Ok(value);
                    }
                    self.handle_notification(&value).await;
                }
                Some(Ok(Message::Ping(payload))) => {
                    stream.send(Message::Pong(payload)).await.ok();
                }
                Some(Ok(Message::Pong(_))) => {}
                Some(Ok(Message::Frame(_))) => {
                    // Reserved for extensions we don't currently use
                }
                Some(Ok(Message::Close(frame))) => {
                    return Err(anyhow!(
                        "MCP websocket {} closed: {:?}",
                        self.id,
                        frame.map(|f| f.reason.into_owned())
                    ));
                }
                Some(Err(err)) => {
                    return Err(anyhow!("MCP websocket {} error: {err}", self.id));
                }
                None => {
                    return Err(anyhow!("MCP websocket {} closed unexpectedly", self.id));
                }
            }
        }
    }

    async fn send_via_stdio(
        &self,
        transport: &StdioTransport,
        body: Value,
        request_id: u64,
    ) -> Result<Value> {
        let mut guard = transport.state.lock().await;
        if guard.is_none() {
            *guard = Some(
                transport
                    .spawn()
                    .await
                    .with_context(|| format!("starting MCP stdio server {}", self.id))?,
            );
        }

        let process = guard
            .as_mut()
            .ok_or_else(|| anyhow!("missing MCP stdio process for {}", self.id))?;
        process.send(&body).await?;

        loop {
            match process.read_message(self.request_timeout).await {
                Ok(value) => {
                    if Self::matches_request(&value, request_id) {
                        return Ok(value);
                    }
                    self.handle_notification(&value).await;
                }
                Err(err) => {
                    guard.take();
                    return Err(err);
                }
            }
        }
    }

    async fn handle_notification(&self, payload: &Value) {
        if let Some(method) = payload.get("method").and_then(|m| m.as_str()) {
            if method.eq_ignore_ascii_case("tools/listChanged") {
                self.mark_cache_dirty().await;
            }
        }
    }

    fn matches_request(payload: &Value, request_id: u64) -> bool {
        match payload.get("id") {
            Some(Value::Number(num)) => num.as_u64() == Some(request_id),
            Some(Value::String(text)) => text.parse::<u64>().map_or(false, |id| id == request_id),
            _ => false,
        }
    }

    fn extract_result(payload: Value, server_id: &str) -> Result<Value> {
        if let Some(error) = payload.get("error") {
            return Err(anyhow!(
                "MCP server {} returned error: {}",
                server_id,
                error
            ));
        }

        if let Some(result) = payload.get("result") {
            return Ok(result.clone());
        }

        Ok(payload)
    }
}

impl WebSocketTransport {
    async fn connect(&self) -> Result<WebSocketStream<MaybeTlsStream<TcpStream>>> {
        let mut request = self
            .endpoint
            .clone()
            .into_client_request()
            .context("constructing websocket request")?;
        for (key, value) in &self.headers {
            let header_name = HeaderName::from_bytes(key.as_bytes())
                .with_context(|| format!("invalid websocket header name `{key}` for MCP server"))?;
            let header_value = HeaderValue::from_str(value)
                .with_context(|| format!("invalid websocket header value for `{key}`"))?;
            request.headers_mut().insert(header_name, header_value);
        }

        let (stream, _) = connect_async(request).await?;
        Ok(stream)
    }
}

impl StdioTransport {
    async fn spawn(&self) -> Result<StdioProcess> {
        let mut command = Command::new(&self.program);
        if !self.args.is_empty() {
            command.args(&self.args);
        }
        if !self.env.is_empty() {
            command.envs(self.env.clone());
        }
        command.stdin(Stdio::piped()).stdout(Stdio::piped());

        let mut child = command
            .spawn()
            .with_context(|| format!("spawning MCP stdio program {}", self.program))?;
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| anyhow!("failed to capture stdin for MCP stdio server"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| anyhow!("failed to capture stdout for MCP stdio server"))?;
        Ok(StdioProcess {
            child,
            stdin,
            stdout: BufReader::new(stdout),
        })
    }
}

impl StdioProcess {
    async fn send(&mut self, body: &Value) -> Result<()> {
        let payload = serde_json::to_vec(body)?;
        let header = format!("Content-Length: {}\r\n\r\n", payload.len());
        self.stdin
            .write_all(header.as_bytes())
            .await
            .context("writing MCP Content-Length header")?;
        self.stdin
            .write_all(&payload)
            .await
            .context("writing MCP payload")?;
        self.stdin.flush().await.context("flushing MCP stdin")?;
        Ok(())
    }

    async fn read_message(&mut self, timeout_dur: Duration) -> Result<Value> {
        let mut content_length: Option<usize> = None;
        loop {
            let mut line = String::new();
            let read = timeout(timeout_dur, self.stdout.read_line(&mut line))
                .await
                .map_err(|_| anyhow!("timed out waiting for MCP stdio headers"))??;
            if read == 0 {
                return Err(anyhow!("MCP stdio server closed stdout"));
            }

            let trimmed = line.trim();
            if trimmed.is_empty() {
                break;
            }

            if let Some(value) = trimmed.strip_prefix("Content-Length:") {
                content_length = value.trim().parse::<usize>().ok();
            }
        }

        let length = content_length.ok_or_else(|| anyhow!("missing Content-Length header"))?;
        let mut buffer = vec![0u8; length];
        timeout(timeout_dur, self.stdout.read_exact(&mut buffer))
            .await
            .map_err(|_| anyhow!("timed out waiting for MCP stdio body"))??;
        let value: Value =
            serde_json::from_slice(&buffer).context("decoding MCP stdio JSON payload")?;
        Ok(value)
    }
}

#[derive(Debug, Deserialize)]
struct ToolListResponse {
    #[serde(default)]
    tools: Vec<RemoteToolDescriptor>,
}

#[derive(Debug, Deserialize)]
struct RemoteToolDescriptor {
    name: String,
    #[serde(default)]
    description: String,
    #[serde(default, alias = "inputSchema")]
    input_schema: Value,
    #[serde(default)]
    metadata: IndexMap<String, Value>,
}

#[derive(Debug, Deserialize)]
struct ToolCallResponse {
    #[serde(default)]
    content: Value,
    #[serde(default)]
    metadata: Option<IndexMap<String, Value>>,
}

#[derive(Clone)]
struct RemoteMcpTool {
    description: McpToolDescription,
    client: Arc<McpServerClient>,
}

impl RemoteMcpTool {
    fn new(client: Arc<McpServerClient>, description: McpToolDescription) -> Self {
        Self {
            description,
            client,
        }
    }
}

#[async_trait]
impl McpTool for RemoteMcpTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        self.client.call_tool(&self.description.name, args).await
    }
}

fn ensure_endpoint(config: &McpResolvedServerConfig, label: &str) -> Result<String> {
    if config.endpoint.trim().is_empty() {
        return Err(anyhow!(
            "MCP transport={} for server {} requires an endpoint",
            label,
            config.id
        ));
    }
    Ok(config.endpoint.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn probe_returns_disabled_for_inactive_server() {
        let registry = McpServerRegistry::empty(Arc::new(McpConfigService::load().unwrap()));
        let status = registry
            .probe_resolved_config(McpResolvedServerConfig {
                id: "disabled-test".into(),
                name: None,
                endpoint: "".into(),
                enabled: false,
                headers: IndexMap::new(),
                timeout_ms: Some(1_000),
                default_capability: None,
                transport: McpTransportKind::Http,
                program: None,
                args: vec![],
                env: IndexMap::new(),
            })
            .await
            .expect("should return status");
        assert_eq!(status.state, McpServerState::Disabled);
    }

    #[tokio::test]
    async fn probe_errors_when_endpoint_missing_for_enabled_http() {
        let registry = McpServerRegistry::empty(Arc::new(McpConfigService::load().unwrap()));
        let result = registry
            .probe_resolved_config(McpResolvedServerConfig {
                id: "invalid-http".into(),
                name: None,
                endpoint: "".into(),
                enabled: true,
                headers: IndexMap::new(),
                timeout_ms: Some(1_000),
                default_capability: None,
                transport: McpTransportKind::Http,
                program: None,
                args: vec![],
                env: IndexMap::new(),
            })
            .await;
        assert!(result.is_err(), "expected error for missing endpoint");
    }
}
