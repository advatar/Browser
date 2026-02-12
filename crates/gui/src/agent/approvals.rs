use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use agent_core::{ApprovalHandler, CapabilityKind};
use anyhow::{anyhow, Result};
use async_trait::async_trait;
use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Emitter, Wry};
use tokio::sync::{oneshot, Mutex as AsyncMutex};
use tokio::time::timeout;
use uuid::Uuid;

#[derive(Debug)]
pub struct ApprovalBroker {
    pending: AsyncMutex<HashMap<String, oneshot::Sender<bool>>>,
}

impl ApprovalBroker {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            pending: AsyncMutex::new(HashMap::new()),
        })
    }

    pub async fn register(&self) -> (String, oneshot::Receiver<bool>) {
        let (tx, rx) = oneshot::channel();
        let id = Uuid::new_v4().to_string();
        let mut pending = self.pending.lock().await;
        pending.insert(id.clone(), tx);
        (id, rx)
    }

    pub async fn resolve(&self, request_id: &str, approved: bool) -> Result<()> {
        let mut pending = self.pending.lock().await;
        let sender = pending
            .remove(request_id)
            .ok_or_else(|| anyhow!("unknown approval request: {}", request_id))?;
        let _ = sender.send(approved);
        Ok(())
    }
}

#[derive(Clone, Serialize)]
pub struct ApprovalEvent<'a> {
    pub id: &'a str,
    pub capability: &'a str,
    pub payload: &'a Value,
}

pub struct GuiApprovalHandler {
    app_handle: AppHandle<Wry>,
    broker: Arc<ApprovalBroker>,
    timeout: Duration,
}

impl GuiApprovalHandler {
    pub fn new(app_handle: AppHandle<Wry>, broker: Arc<ApprovalBroker>) -> Arc<Self> {
        Arc::new(Self {
            app_handle,
            broker,
            timeout: Duration::from_secs(30),
        })
    }
}

#[async_trait]
impl ApprovalHandler for GuiApprovalHandler {
    async fn request_approval(
        &self,
        capability: &CapabilityKind,
        payload: &Value,
    ) -> anyhow::Result<bool> {
        // Allow passive capabilities without prompting.
        let requires_prompt = matches!(
            capability,
            CapabilityKind::Navigate | CapabilityKind::EmailSend | CapabilityKind::WalletSpend
        );
        if !requires_prompt {
            return Ok(true);
        }

        let (request_id, receiver) = self.broker.register().await;
        let event_payload = ApprovalEvent {
            id: &request_id,
            capability: capability.as_str(),
            payload,
        };

        self.app_handle
            .emit("agent://approval-request", event_payload)
            .map_err(|err| anyhow!("failed to emit approval request: {}", err))?;

        match timeout(self.timeout, receiver).await {
            Ok(Ok(approved)) => Ok(approved),
            Ok(Err(_)) => Ok(false),
            Err(_) => {
                // auto deny on timeout
                let _ = self.broker.resolve(&request_id, false).await;
                Ok(false)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::McpServerRegistry;
    use crate::agent_apps::AgentAppRegistry;
    use crate::app_state::AppState;
    use crate::browser_engine::BrowserEngine;
    use crate::mcp_profiles::McpConfigService;
    use crate::protocol_handlers::ProtocolHandler;
    use crate::security::SecurityManager;
    use crate::telemetry::TelemetryManager;
    use crate::wallet_store::WalletStore;
    use afm_node::AfmNodeConfig;
    use anyhow::Result as TestResult;
    use serde_json::Value;
    use std::sync::{Arc, Mutex};
    use tauri::{App, Builder, Listener, Manager};
    use tokio::sync::{oneshot, Mutex as AsyncMutex};

    fn build_app_with_state() -> TestResult<(App<Wry>, Arc<ApprovalBroker>)> {
        std::env::set_var("TAO_EVENT_LOOP_SUPPRESS_THREAD_CHECK", "1");
        let mcp_config = Arc::new(
            McpConfigService::load().unwrap_or_else(|_| McpConfigService::reset().unwrap()),
        );
        let mcp_registry = McpServerRegistry::from_config_service(mcp_config.clone())
            .unwrap_or_else(|_| {
                // Fall back to an empty registry if profiles cannot be loaded in tests.
                McpServerRegistry::empty(mcp_config.clone())
            });
        let state = AppState {
            current_url: Mutex::new(String::new()),
            content_tab_webviews: Mutex::new(std::collections::HashMap::new()),
            active_content_tab: Mutex::new(None),
            content_bounds: Mutex::new(None),
            browser_engine: Arc::new(BrowserEngine::new()),
            protocol_handler: Arc::new(Mutex::new(ProtocolHandler::new())),
            security_manager: Arc::new(Mutex::new(SecurityManager::new())),
            telemetry_manager: Arc::new(Mutex::new(TelemetryManager::new())),
            wallet_store: Arc::new(Mutex::new(WalletStore::new().unwrap_or_default())),
            agent_manager: Arc::new(AsyncMutex::new(None)),
            approval_broker: ApprovalBroker::new(),
            afm_node_controller: Arc::new(AsyncMutex::new(None)),
            afm_node_handle: Arc::new(Mutex::new(None)),
            afm_node_config: Arc::new(Mutex::new(AfmNodeConfig::default())),
            mcp_registry: Arc::new(mcp_registry),
            mcp_config,
            agent_apps: Arc::new(AgentAppRegistry::empty()),
        };
        let broker = state.approval_broker.clone();
        let app = Builder::default()
            .manage(state)
            .build(tauri::generate_context!(test = true))?;
        Ok((app, broker))
    }

    #[tokio::test(flavor = "current_thread")]
    async fn broker_resolve_delivers_outcome() -> TestResult<()> {
        let broker = ApprovalBroker::new();
        let (request_id, receiver) = broker.register().await;
        broker.resolve(&request_id, true).await?;
        assert!(receiver.await.unwrap());
        Ok(())
    }

    #[cfg_attr(target_os = "macos", ignore = "requires main-thread event loop access")]
    #[tokio::test(flavor = "current_thread")]
    async fn handler_allows_passive_capabilities_without_prompt() -> TestResult<()> {
        let (app, broker) = build_app_with_state()?;
        let handler = GuiApprovalHandler::new(app.app_handle().clone(), broker.clone());
        let approved = handler
            .request_approval(&CapabilityKind::Click, &Value::Null)
            .await?;
        assert!(approved);
        Ok(())
    }

    #[cfg_attr(target_os = "macos", ignore = "requires main-thread event loop access")]
    #[tokio::test(flavor = "current_thread")]
    async fn handler_emits_event_and_waits_for_resolution() -> TestResult<()> {
        let (app, broker) = build_app_with_state()?;
        let handler = GuiApprovalHandler::new(app.app_handle().clone(), broker.clone());

        let (sender, receiver) = oneshot::channel::<String>();
        let sender_guard = Arc::new(std::sync::Mutex::new(Some(sender)));
        let listener_guard = sender_guard.clone();

        let app_handle = app.app_handle().clone();
        let event_handle = app_handle.listen_any("agent://approval-request", move |event| {
            if let Ok(value) = serde_json::from_str::<Value>(event.payload()) {
                if let Some(id) = value.get("id").and_then(|val| val.as_str()) {
                    if let Some(sender) = listener_guard.lock().unwrap().take() {
                        let _ = sender.send(id.to_string());
                    }
                }
            }
        });

        let capability = CapabilityKind::Navigate;
        let payload = Value::Null;
        let handler_task = {
            let handler = handler.clone();
            tokio::spawn(async move {
                handler
                    .request_approval(&capability, &payload)
                    .await
                    .expect("approval request should resolve")
            })
        };

        let request_id = receiver.await.expect("approval event to be emitted");
        broker.resolve(&request_id, true).await?;
        let approved = handler_task.await.unwrap();
        assert!(approved);

        app_handle.unlisten(event_handle);
        Ok(())
    }
}
