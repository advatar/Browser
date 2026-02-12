use crate::wallet_store::WalletStore;
use afm_node::{AfmNodeConfig, AfmNodeController, AfmNodeHandle};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::Mutex as AsyncMutex;

use crate::agent::{AgentManager, ApprovalBroker, McpServerRegistry};
use crate::agent_apps::AgentAppRegistry;
use crate::browser_engine::BrowserEngine;
use crate::mcp_profiles::McpConfigService;
use crate::protocol_handlers::ProtocolHandler;
use crate::security::SecurityManager;
use crate::telemetry::TelemetryManager;

#[derive(Clone, Copy, Debug, Default)]
pub struct ContentWebviewBounds {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl ContentWebviewBounds {
    pub fn is_visible(&self) -> bool {
        self.width > 1.0 && self.height > 1.0
    }
}

pub struct AppState {
    pub current_url: Mutex<String>,
    pub content_tab_webviews: Mutex<HashMap<String, String>>,
    pub active_content_tab: Mutex<Option<String>>,
    pub content_bounds: Mutex<Option<ContentWebviewBounds>>,
    pub browser_engine: Arc<BrowserEngine>,
    pub protocol_handler: Arc<Mutex<ProtocolHandler>>,
    pub security_manager: Arc<Mutex<SecurityManager>>,
    pub telemetry_manager: Arc<Mutex<TelemetryManager>>,
    pub wallet_store: Arc<Mutex<WalletStore>>,
    pub agent_manager: Arc<AsyncMutex<Option<AgentManager>>>,
    pub approval_broker: Arc<ApprovalBroker>,
    pub afm_node_controller: Arc<AsyncMutex<Option<AfmNodeController>>>,
    pub afm_node_handle: Arc<Mutex<Option<AfmNodeHandle>>>,
    pub afm_node_config: Arc<Mutex<AfmNodeConfig>>,
    pub mcp_registry: Arc<McpServerRegistry>,
    pub mcp_config: Arc<McpConfigService>,
    pub agent_apps: Arc<AgentAppRegistry>,
}
