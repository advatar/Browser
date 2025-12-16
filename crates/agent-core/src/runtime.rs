use std::collections::HashMap;
use std::sync::Arc;

use ai_agent::{
    AgentConfig, AgentOrchestrator, AgentResult, LanguageModelClient, McpTool, McpToolDescription,
    McpToolError, McpToolResult,
};
use anyhow::Result;
use async_trait::async_trait;
use serde::Deserialize;
use serde_json::{json, Value};
use tokio::sync::Mutex;

use crate::approvals::ApprovalHandler;
use crate::capabilities::{CapabilityError, CapabilityKind, CapabilityRegistry};
use crate::dom::{DomAction, DomInstrumentation};
use crate::ledger::AgentLedger;

const DOM_TOOL_NAME: &str = "dom_action";

#[derive(Clone)]
struct SharedState {
    capabilities: Arc<Mutex<CapabilityRegistry>>,
    dom: Arc<Mutex<DomInstrumentation>>,
    ledger: Arc<Mutex<AgentLedger>>,
    approval: Option<Arc<dyn ApprovalHandler>>,
}

impl SharedState {
    fn new(capabilities: CapabilityRegistry, approval: Option<Arc<dyn ApprovalHandler>>) -> Self {
        Self {
            capabilities: Arc::new(Mutex::new(capabilities)),
            dom: Arc::new(Mutex::new(DomInstrumentation::new())),
            ledger: Arc::new(Mutex::new(AgentLedger::new())),
            approval,
        }
    }

    async fn request_approval(
        &self,
        capability: &CapabilityKind,
        payload: &Value,
    ) -> anyhow::Result<bool> {
        match &self.approval {
            Some(handler) => handler.request_approval(capability, payload).await,
            None => Ok(true),
        }
    }
}

pub struct AgentRuntime {
    orchestrator: AgentOrchestrator,
    state: SharedState,
}

impl AgentRuntime {
    pub fn builder(model: Arc<dyn LanguageModelClient>) -> AgentRuntimeBuilder {
        AgentRuntimeBuilder::new(model)
    }

    pub async fn run(&mut self, task: &str) -> Result<AgentRuntimeResult> {
        let result = self.orchestrator.run_task(task).await?;
        let ledger_root = {
            let guard = self.state.ledger.lock().await;
            guard.root_hash()
        };
        Ok(AgentRuntimeResult {
            agent: result,
            ledger_root,
        })
    }

    pub async fn dom_events(&self) -> Vec<crate::dom::DomEvent> {
        let guard = self.state.dom.lock().await;
        guard.events().to_vec()
    }

    pub async fn ledger_entries(&self) -> Vec<crate::ledger::LedgerEntry> {
        let guard = self.state.ledger.lock().await;
        guard.entries().to_vec()
    }

    pub async fn ledger_root_hash(&self) -> Option<String> {
        let guard = self.state.ledger.lock().await;
        guard.root_hash()
    }

    pub async fn capability_snapshot(&self) -> HashMap<String, Option<u32>> {
        let guard = self.state.capabilities.lock().await;
        guard
            .snapshot()
            .into_iter()
            .map(|(kind, remaining)| (kind.as_str().to_string(), remaining))
            .collect()
    }

    pub fn tool_descriptions(&self) -> Vec<McpToolDescription> {
        self.orchestrator.tool_descriptions()
    }

    pub async fn revoke_capability(&self, kind: CapabilityKind) {
        let mut guard = self.state.capabilities.lock().await;
        guard.revoke(kind);
    }

    pub async fn capability_remaining(&self, kind: CapabilityKind) -> Option<u32> {
        let guard = self.state.capabilities.lock().await;
        guard.remaining(kind)
    }
}

pub struct AgentRuntimeBuilder {
    model: Arc<dyn LanguageModelClient>,
    config: AgentConfig,
    capabilities: CapabilityRegistry,
    tools: Vec<(Arc<dyn McpTool>, Option<CapabilityKind>)>,
    approval_handler: Option<Arc<dyn ApprovalHandler>>,
}

impl AgentRuntimeBuilder {
    fn new(model: Arc<dyn LanguageModelClient>) -> Self {
        Self {
            model,
            config: AgentConfig::default(),
            capabilities: CapabilityRegistry::with_browser_defaults(),
            tools: Vec::new(),
            approval_handler: None,
        }
    }

    pub fn with_config(mut self, config: AgentConfig) -> Self {
        self.config = config;
        self
    }

    pub fn with_capabilities(mut self, registry: CapabilityRegistry) -> Self {
        self.capabilities = registry;
        self
    }

    pub fn with_approval_handler(mut self, handler: Arc<dyn ApprovalHandler>) -> Self {
        self.approval_handler = Some(handler);
        self
    }

    pub fn register_tool(
        mut self,
        tool: Arc<dyn McpTool>,
        capability: Option<CapabilityKind>,
    ) -> Self {
        self.tools.push((tool, capability));
        self
    }

    pub fn build(self) -> AgentRuntime {
        let state = SharedState::new(self.capabilities, self.approval_handler.clone());
        let mut orchestrator = AgentOrchestrator::new(self.model, self.config);
        orchestrator.register_tool(Arc::new(DomTool::new(state.clone())));
        for (tool, capability) in self.tools {
            let tool: Arc<dyn McpTool> = match capability {
                Some(capability) => {
                    Arc::new(CapabilityGuardTool::new(tool, capability, state.clone()))
                }
                None => tool,
            };
            orchestrator.register_tool(tool);
        }
        AgentRuntime {
            orchestrator,
            state,
        }
    }
}

#[derive(Debug)]
pub struct AgentRuntimeResult {
    pub agent: AgentResult,
    pub ledger_root: Option<String>,
}

struct CapabilityGuardTool {
    description: McpToolDescription,
    capability: CapabilityKind,
    inner: Arc<dyn McpTool>,
    state: SharedState,
}

impl CapabilityGuardTool {
    fn new(inner: Arc<dyn McpTool>, capability: CapabilityKind, state: SharedState) -> Self {
        let description = inner.description().clone();
        Self {
            description,
            capability,
            inner,
            state,
        }
    }
}

#[async_trait]
impl McpTool for CapabilityGuardTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let approval_payload = args.clone();
        let approved = self
            .state
            .request_approval(&self.capability, &approval_payload)
            .await
            .map_err(|err| McpToolError::Invocation(format!("approval request failed: {}", err)))?;
        if !approved {
            return Err(McpToolError::Invocation(
                "action rejected by user approval flow".into(),
            ));
        }

        {
            let mut capabilities = self.state.capabilities.lock().await;
            capabilities
                .consume(self.capability.clone())
                .map_err(capability_error_to_mcp)?;
        }

        self.inner.invoke(args).await
    }
}

struct DomTool {
    description: McpToolDescription,
    state: SharedState,
}

impl DomTool {
    fn new(state: SharedState) -> Self {
        let description = McpToolDescription::new(
            DOM_TOOL_NAME,
            "Perform DOM-level actions such as click, scroll, type, or navigate.",
            dom_tool_schema(),
        );
        Self { description, state }
    }
}

#[async_trait]
impl McpTool for DomTool {
    fn description(&self) -> &McpToolDescription {
        &self.description
    }

    async fn invoke(&self, args: Value) -> Result<McpToolResult, McpToolError> {
        let payload: DomToolPayload = serde_json::from_value(args).map_err(|err| {
            McpToolError::InvalidInput(format!("invalid DOM tool payload: {}", err))
        })?;

        let action = payload.into_action().map_err(|msg| {
            McpToolError::InvalidInput(format!("invalid DOM action payload: {}", msg))
        })?;
        let capability = map_action_to_capability(&action);
        let approval_payload =
            serde_json::to_value(&action).unwrap_or_else(|_| json!({ "action": "unknown" }));
        let approved = self
            .state
            .request_approval(&capability, &approval_payload)
            .await
            .map_err(|err| McpToolError::Invocation(format!("approval request failed: {}", err)))?;
        if !approved {
            return Err(McpToolError::Invocation(
                "action rejected by user approval flow".into(),
            ));
        }

        let outcome = {
            let mut capabilities = self.state.capabilities.lock().await;
            capabilities
                .consume(capability.clone())
                .map_err(capability_error_to_mcp)?
        };

        let observation = {
            let mut dom = self.state.dom.lock().await;
            dom.execute(action)
        };

        {
            let mut ledger = self.state.ledger.lock().await;
            ledger.record(capability.clone(), &observation);
        }

        let mut content = json!({
            "status": "ok",
            "sequence": observation.event.sequence,
            "capability": capability.as_str(),
            "message": observation.message,
            "timestamp_ms": observation.event.timestamp_ms,
            "event": observation.event,
        });

        if let Some(remaining) = outcome.remaining {
            if let Some(map) = content.as_object_mut() {
                map.insert("remaining".to_string(), json!(remaining));
            }
        }

        Ok(McpToolResult {
            content,
            metadata: Default::default(),
        })
    }
}

#[derive(Debug, Deserialize)]
struct DomToolPayload {
    action: DomActionKind,
    selector: Option<String>,
    text: Option<String>,
    dx: Option<i32>,
    dy: Option<i32>,
    url: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
enum DomActionKind {
    Click,
    Scroll,
    Type,
    Navigate,
}

impl DomToolPayload {
    fn into_action(self) -> Result<DomAction, String> {
        match self.action {
            DomActionKind::Click => {
                let selector = self
                    .selector
                    .ok_or_else(|| "click action requires selector".to_string())?;
                Ok(DomAction::Click { selector })
            }
            DomActionKind::Scroll => {
                let dx = self.dx.unwrap_or(0);
                let dy = self.dy.unwrap_or(0);
                Ok(DomAction::Scroll { dx, dy })
            }
            DomActionKind::Type => {
                let selector = self
                    .selector
                    .ok_or_else(|| "type action requires selector".to_string())?;
                let text = self
                    .text
                    .ok_or_else(|| "type action requires text".to_string())?;
                Ok(DomAction::Type { selector, text })
            }
            DomActionKind::Navigate => {
                let url = self
                    .url
                    .ok_or_else(|| "navigate action requires url".to_string())?;
                Ok(DomAction::Navigate { url })
            }
        }
    }
}

fn dom_tool_schema() -> Value {
    json!({
        "type": "object",
        "required": ["action"],
        "properties": {
            "action": {
                "type": "string",
                "enum": ["click", "scroll", "type", "navigate"]
            },
            "selector": { "type": "string" },
            "text": { "type": "string" },
            "dx": { "type": "integer" },
            "dy": { "type": "integer" },
            "url": { "type": "string", "format": "uri" }
        },
        "additionalProperties": false
    })
}

fn map_action_to_capability(action: &DomAction) -> CapabilityKind {
    match action {
        DomAction::Click { .. } => CapabilityKind::Click,
        DomAction::Scroll { .. } => CapabilityKind::Scroll,
        DomAction::Type { .. } => CapabilityKind::Type,
        DomAction::Navigate { .. } => CapabilityKind::Navigate,
    }
}

fn capability_error_to_mcp(err: CapabilityError) -> McpToolError {
    McpToolError::Invocation(format!("{}", err))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{CapabilityKind, CapabilityLimit, CapabilityRegistry};
    use ai_agent::{FoundationModelOptions, LanguageModelResponse};
    use serde_json::json;
    use std::collections::VecDeque;
    use tokio::sync::Mutex as TokioMutex;

    struct ScriptedModel {
        responses: TokioMutex<VecDeque<String>>,
    }

    impl ScriptedModel {
        fn new(responses: Vec<String>) -> Arc<Self> {
            Arc::new(Self {
                responses: TokioMutex::new(responses.into()),
            })
        }
    }

    #[async_trait]
    impl LanguageModelClient for ScriptedModel {
        async fn complete(
            &self,
            _prompt: &str,
            _options: &FoundationModelOptions,
        ) -> anyhow::Result<LanguageModelResponse> {
            let mut guard = self.responses.lock().await;
            let next = guard
                .pop_front()
                .expect("scripted model ran out of responses");
            Ok(LanguageModelResponse::new(next))
        }
    }

    fn agent_responses_for_order_test() -> Vec<String> {
        vec![
            json!({
                "type": "tool",
                "name": DOM_TOOL_NAME,
                "args": {
                    "action": "click",
                    "selector": "#signin"
                }
            })
            .to_string(),
            json!({
                "type": "tool",
                "name": DOM_TOOL_NAME,
                "args": {
                    "action": "scroll",
                    "dx": 0,
                    "dy": 600
                }
            })
            .to_string(),
            json!({
                "type": "finish",
                "answer": "Login flow completed"
            })
            .to_string(),
        ]
    }

    #[tokio::test]
    async fn executes_dom_actions_in_order() {
        let model = ScriptedModel::new(agent_responses_for_order_test());
        let mut runtime = AgentRuntime::builder(model)
            .with_capabilities(CapabilityRegistry::with_browser_defaults())
            .build();

        let result = runtime
            .run("Sign into the dashboard and scroll to analytics.")
            .await
            .expect("agent runtime should succeed");

        assert_eq!(
            result.agent.final_answer,
            Some("Login flow completed".to_string())
        );

        let events = runtime.dom_events().await;
        assert_eq!(events.len(), 2);
        assert!(matches!(events[0].action, DomAction::Click { .. }));
        assert!(matches!(events[1].action, DomAction::Scroll { .. }));
        assert!(events[0].sequence < events[1].sequence);

        let ledger_root = result.ledger_root.clone().expect("ledger root expected");
        let snapshot_root =
            AgentLedger::compute_root_snapshot(&runtime.ledger_entries().await).unwrap();
        assert_eq!(ledger_root, snapshot_root);
    }

    #[tokio::test]
    async fn enforces_capability_caps() {
        let model = ScriptedModel::new(vec![
            json!({
                "type": "tool",
                "name": DOM_TOOL_NAME,
                "args": { "action": "click", "selector": "#confirm" }
            })
            .to_string(),
            json!({
                "type": "tool",
                "name": DOM_TOOL_NAME,
                "args": { "action": "click", "selector": "#danger" }
            })
            .to_string(),
        ]);

        let mut registry = CapabilityRegistry::new();
        registry.grant(CapabilityKind::Click, CapabilityLimit::limited(1));

        let mut runtime = AgentRuntime::builder(model)
            .with_capabilities(registry)
            .build();

        let err = runtime.run("Attempt multiple destructive clicks").await;
        assert!(err.is_err(), "second click should exceed capability");
        let err_text = format!("{}", err.unwrap_err());
        assert!(
            err_text.contains("quota"),
            "error message should mention quota: {err_text}"
        );
    }

    #[tokio::test]
    async fn ledger_root_updates_on_tamper() {
        let model = ScriptedModel::new(vec![
            json!({
                "type": "tool",
                "name": DOM_TOOL_NAME,
                "args": { "action": "navigate", "url": "https://example.com" }
            })
            .to_string(),
            json!({
                "type": "finish",
                "answer": "Navigation complete"
            })
            .to_string(),
        ]);

        let mut runtime = AgentRuntime::builder(model).build();
        let result = runtime.run("Open example.com").await.unwrap();
        let root = result.ledger_root.clone().unwrap();

        let mut entries = runtime.ledger_entries().await;
        assert_eq!(entries.len(), 1);
        let original_hash = entries[0].hash.clone();
        entries[0].hash = "tampered".to_string();

        let tampered_root = AgentLedger::compute_root_snapshot(&entries).unwrap();
        assert_ne!(root, tampered_root);
        assert_eq!(runtime.ledger_root_hash().await.unwrap(), root);
        assert_ne!(original_hash, "tampered");
    }
}
