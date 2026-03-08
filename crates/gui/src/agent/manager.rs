use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use afm_node::{AfmNodeHandle, AgentRuntimeAfmExt};
use agent_core::{
    AgentRuntime, AgentRuntimeResult, CapabilityKind, DomExecutionResult, DomExecutor, LedgerEntry,
};
use ai_agent::{
    AgentCancellationCheck, AgentConfig, AgentEvent, AgentEventCallback, AgentResult,
    FoundationModelOptions, LanguageModelClient, LanguageModelResponse, McpTool,
    McpToolDescription,
};
use anyhow::{anyhow, Result};
use async_trait::async_trait;
use llm_router::{LlmRouter, RoutingPolicy};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Wry};
use tokio::sync::Mutex as AsyncMutex;

use super::approvals::{ApprovalBroker, GuiApprovalHandler};
use super::credits::{CreditAccount, CreditSnapshot};
use super::iproov::IproovServices;
use super::mcp_client::McpServerRegistry;
use super::skills::{SkillDefinition, SkillRegistry};
use super::tools::{
    DomQueryTool, GatewayApproveCartTool, GatewayApprovePresentationTool, GatewayAwaitDecisionTool,
    GatewayCreatePresentationTool, GatewayFetchMandateTool, GatewayIntrospectTool,
    MerchantPlaceOrderTool, MerchantQuoteCartTool, NavigateTool, PageSnapshotTool, TabsTool,
    WalletInfoTool, WalletSpendTool,
};
use crate::app_state::AppState;
use crate::browser_engine::BrowserEngine;
use crate::wallet_store::{WalletOwner, WalletStore};
use crate::webview_automation::execute_active_dom_action;

const DEFAULT_INITIAL_CREDITS: i64 = 50_000;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentRunRequest {
    pub task: String,
    #[serde(default)]
    pub skill_id: Option<String>,
    #[serde(default)]
    pub no_egress: Option<bool>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentRunResponse {
    pub run_id: String,
    pub agent: AgentResult,
    pub ledger_root: Option<String>,
    pub ledger_entries: Vec<LedgerEntry>,
    pub tokens_used: u64,
    pub tokens_estimated: bool,
    pub credits_spent: u64,
    pub cancelled: bool,
    pub credit: CreditSnapshot,
    pub capabilities: HashMap<String, Option<u32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub skill_id: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AgentSkillSummary {
    pub id: String,
    pub name: String,
    pub description: String,
    pub tags: Vec<String>,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct AgentRunEventEnvelope {
    pub run_id: String,
    #[serde(flatten)]
    pub payload: AgentRunEventPayload,
}

#[derive(Debug, Serialize, Clone)]
#[serde(tag = "stage", rename_all = "snake_case")]
pub enum AgentRunEventPayload {
    Started {
        task: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        skill_id: Option<String>,
    },
    Activity {
        event: AgentEvent,
    },
    CancelRequested,
    Finished {
        halted: bool,
        cancelled: bool,
        #[serde(skip_serializing_if = "Option::is_none")]
        final_answer: Option<String>,
        tokens_used: u64,
        tokens_estimated: bool,
        credits_spent: u64,
    },
    Failed {
        error: String,
        tokens_used: u64,
        tokens_estimated: bool,
        credits_spent: u64,
    },
}

struct RunControl {
    cancelled: AtomicBool,
}

impl RunControl {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            cancelled: AtomicBool::new(false),
        })
    }

    fn cancel(&self) {
        self.cancelled.store(true, Ordering::SeqCst);
    }

    fn is_cancelled(&self) -> bool {
        self.cancelled.load(Ordering::SeqCst)
    }
}

#[derive(Clone)]
struct GuiDomExecutor {
    app_handle: AppHandle<Wry>,
}

impl GuiDomExecutor {
    fn new(app_handle: AppHandle<Wry>) -> Self {
        Self { app_handle }
    }
}

#[async_trait]
impl DomExecutor for GuiDomExecutor {
    async fn execute(&self, action: &agent_core::DomAction) -> Result<DomExecutionResult> {
        execute_active_dom_action(&self.app_handle, action)
            .await
            .map_err(anyhow::Error::msg)
    }
}

pub struct AgentManager {
    app_handle: AppHandle<Wry>,
    router: LlmRouter,
    browser_engine: Arc<BrowserEngine>,
    wallet_store: Arc<std::sync::Mutex<WalletStore>>,
    iproov: Arc<IproovServices>,
    approval_handler: Arc<GuiApprovalHandler>,
    skills: SkillRegistry,
    credit_account: Arc<AsyncMutex<CreditAccount>>,
    model_available: bool,
    no_egress: AtomicBool,
    afm_node_handle: Arc<Mutex<Option<AfmNodeHandle>>>,
    mcp_registry: Arc<McpServerRegistry>,
    run_seq: AtomicU64,
    active_runs: AsyncMutex<HashMap<String, Arc<RunControl>>>,
}

impl AgentManager {
    pub fn new(
        app_handle: AppHandle<Wry>,
        state: &AppState,
        broker: Arc<ApprovalBroker>,
    ) -> Result<Self> {
        let router = LlmRouter::new()?;
        let iproov = Arc::new(IproovServices::new(100_000)?);
        let approval_handler = GuiApprovalHandler::new(app_handle.clone(), broker);
        let credit_account = Arc::new(AsyncMutex::new(CreditAccount::new(DEFAULT_INITIAL_CREDITS)));
        let skills = SkillRegistry::load()?;
        let mcp_registry = state.mcp_registry.clone();
        let wallet_store = state.wallet_store.clone();
        // Ensure the primary user wallet exists up front.
        {
            let mut guard = wallet_store
                .lock()
                .map_err(|_| anyhow!("wallet store mutex poisoned"))?;
            let _ = guard.ensure_user_profile();
        }

        Ok(Self {
            model_available: router.local_available(),
            app_handle,
            router,
            browser_engine: state.browser_engine.clone(),
            wallet_store,
            iproov,
            approval_handler,
            skills,
            credit_account,
            no_egress: AtomicBool::new(false),
            afm_node_handle: state.afm_node_handle.clone(),
            mcp_registry,
            run_seq: AtomicU64::new(1),
            active_runs: AsyncMutex::new(HashMap::new()),
        })
    }

    pub fn is_model_available(&self) -> bool {
        self.model_available
    }

    pub fn list_skills(&self) -> Vec<AgentSkillSummary> {
        self.skills
            .list()
            .iter()
            .map(|skill| AgentSkillSummary {
                id: skill.id.clone(),
                name: skill.name.clone(),
                description: skill.description.clone(),
                tags: skill.tags.clone(),
            })
            .collect()
    }

    pub async fn credit_snapshot(&self) -> CreditSnapshot {
        let account = self.credit_account.lock().await;
        account.snapshot()
    }

    pub async fn top_up_credits(&self, tokens: u32) -> CreditSnapshot {
        let mut account = self.credit_account.lock().await;
        account.top_up(tokens);
        account.snapshot()
    }

    pub fn set_no_egress(&self, value: bool) {
        self.no_egress.store(value, Ordering::SeqCst);
    }

    pub async fn tool_descriptions(&self) -> Result<Vec<McpToolDescription>> {
        let policy = RoutingPolicy {
            no_egress: self.no_egress.load(Ordering::SeqCst),
            ..RoutingPolicy::default()
        };
        let (runtime, _) = self
            .build_runtime(None, policy, WalletOwner::User, None, None)
            .await?;
        Ok(runtime.tool_descriptions())
    }

    pub async fn cancel_run(&self, run_id: &str) -> Result<bool> {
        let maybe_control = {
            let active_runs = self.active_runs.lock().await;
            active_runs.get(run_id).cloned()
        };

        if let Some(control) = maybe_control {
            control.cancel();
            self.emit_run_event(run_id, AgentRunEventPayload::CancelRequested, false)?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub async fn run_task(&self, request: AgentRunRequest) -> Result<AgentRunResponse> {
        if request.task.trim().is_empty() {
            return Err(anyhow!("task must not be empty"));
        }

        {
            let account = self.credit_account.lock().await;
            if account.balance() <= 0 {
                return Err(anyhow!(
                    "insufficient credits: top up before starting a new agent run"
                ));
            }
        }

        let skill_ref = request
            .skill_id
            .as_ref()
            .and_then(|id| self.skills.find(id));

        let no_egress = request
            .no_egress
            .unwrap_or_else(|| self.no_egress.load(Ordering::SeqCst));

        let policy = RoutingPolicy {
            no_egress,
            ..RoutingPolicy::default()
        };

        let run_seq = self.run_seq.fetch_add(1, Ordering::SeqCst);
        let run_id = format!("run-{}", run_seq);
        let agent_id = format!("agent-{}", run_seq);
        let wallet_owner = WalletOwner::Agent(agent_id.clone());
        {
            let mut store = self
                .wallet_store
                .lock()
                .map_err(|_| anyhow!("wallet store mutex poisoned"))?;
            store.ensure_agent_profile(&agent_id)?;
        }

        let run_control = RunControl::new();
        {
            let mut active_runs = self.active_runs.lock().await;
            active_runs.insert(run_id.clone(), run_control.clone());
        }

        self.emit_run_event(
            &run_id,
            AgentRunEventPayload::Started {
                task: request.task.clone(),
                skill_id: request.skill_id.clone(),
            },
            false,
        )?;

        let runtime_result = self
            .build_runtime(
                skill_ref,
                policy,
                wallet_owner,
                Some(self.build_run_event_callback(&run_id)),
                Some(self.build_cancellation_check(run_control)),
            )
            .await;
        let (mut runtime, metered_model) = match runtime_result {
            Ok(result) => result,
            Err(err) => {
                let mut active_runs = self.active_runs.lock().await;
                active_runs.remove(&run_id);
                let _ = self.emit_run_event(
                    &run_id,
                    AgentRunEventPayload::Failed {
                        error: err.to_string(),
                        tokens_used: 0,
                        tokens_estimated: false,
                        credits_spent: 0,
                    },
                    true,
                );
                return Err(err);
            }
        };
        metered_model.reset();

        let run_result = runtime.run(&request.task).await;

        let ledger_entries = runtime.ledger_entries().await;
        let capabilities = runtime.capability_snapshot().await;
        let tokens_used = metered_model.tokens_used();
        let tokens_estimated = metered_model.used_estimated_tokens();
        let credits_spent = tokens_used;
        let credit = self.credit_snapshot().await;

        let result = match run_result {
            Ok(result) => result,
            Err(err) => {
                let _ = self.emit_run_event(
                    &run_id,
                    AgentRunEventPayload::Failed {
                        error: err.to_string(),
                        tokens_used,
                        tokens_estimated,
                        credits_spent,
                    },
                    true,
                );
                let mut active_runs = self.active_runs.lock().await;
                active_runs.remove(&run_id);
                return Err(err);
            }
        };

        let AgentRuntimeResult { agent, ledger_root } = result;
        let cancelled = agent
            .events
            .iter()
            .any(|event| matches!(event, AgentEvent::Cancelled { .. }));

        self.emit_run_event(
            &run_id,
            AgentRunEventPayload::Finished {
                halted: agent.halted,
                cancelled,
                final_answer: agent.final_answer.clone(),
                tokens_used,
                tokens_estimated,
                credits_spent,
            },
            true,
        )?;

        let mut active_runs = self.active_runs.lock().await;
        active_runs.remove(&run_id);

        Ok(AgentRunResponse {
            run_id,
            agent,
            ledger_root,
            ledger_entries,
            tokens_used,
            tokens_estimated,
            credits_spent,
            cancelled,
            credit,
            capabilities,
            skill_id: request.skill_id,
        })
    }

    fn build_run_event_callback(&self, run_id: &str) -> AgentEventCallback {
        let app_handle = self.app_handle.clone();
        let run_id = run_id.to_string();
        Arc::new(move |event: AgentEvent| {
            let _ = app_handle.emit(
                "agent://run-event",
                AgentRunEventEnvelope {
                    run_id: run_id.clone(),
                    payload: AgentRunEventPayload::Activity { event },
                },
            );
        })
    }

    fn build_cancellation_check(&self, run_control: Arc<RunControl>) -> AgentCancellationCheck {
        Arc::new(move || run_control.is_cancelled())
    }

    fn emit_run_event(
        &self,
        run_id: &str,
        payload: AgentRunEventPayload,
        finished: bool,
    ) -> Result<()> {
        let event = AgentRunEventEnvelope {
            run_id: run_id.to_string(),
            payload,
        };
        self.app_handle.emit("agent://run-event", event.clone())?;
        if finished {
            self.app_handle.emit("agent://run-finished", event)?;
        }
        Ok(())
    }

    async fn build_runtime(
        &self,
        skill: Option<&SkillDefinition>,
        policy: RoutingPolicy,
        wallet_owner: WalletOwner,
        event_callback: Option<AgentEventCallback>,
        cancellation_check: Option<AgentCancellationCheck>,
    ) -> Result<(AgentRuntime, Arc<MeteredModel>)> {
        let capabilities = self
            .skills
            .build_capabilities(skill.map(|skill| skill.id.as_str()));

        let mut config = AgentConfig::default();
        if let Some(skill) = skill {
            if let Some(prompt) = &skill.system_prompt {
                config.system_prompt = prompt.clone();
            }
            if let Some(max_steps) = skill.max_steps {
                config.max_steps = max_steps;
            }
        }

        let base_model = self.router.route(policy)?;
        let metered_model = MeteredModel::new(base_model, self.credit_account.clone());
        let model: Arc<dyn LanguageModelClient> = metered_model.clone();

        let mut builder = AgentRuntime::builder(model)
            .with_config(config)
            .with_capabilities(capabilities)
            .with_approval_handler(self.approval_handler.clone())
            .with_dom_executor(Arc::new(GuiDomExecutor::new(self.app_handle.clone())));

        if let Some(callback) = event_callback {
            builder = builder.with_event_callback(callback);
        }

        if let Some(check) = cancellation_check {
            builder = builder.with_cancellation_check(check);
        }

        for (tool, capability) in self.build_tools(wallet_owner.clone()).await {
            builder = builder.register_tool(tool, capability);
        }

        if let Ok(slot) = self.afm_node_handle.lock() {
            if let Some(handle) = slot.as_ref() {
                builder = builder.with_afm_handle(handle.clone());
            }
        }

        Ok((builder.build(), metered_model))
    }

    async fn build_tools(
        &self,
        wallet_owner: WalletOwner,
    ) -> Vec<(Arc<dyn McpTool>, Option<CapabilityKind>)> {
        let mut tools: Vec<(Arc<dyn McpTool>, Option<CapabilityKind>)> = Vec::new();

        tools.push((
            Arc::new(NavigateTool::new(self.app_handle.clone())),
            Some(CapabilityKind::Navigate),
        ));
        tools.push((Arc::new(DomQueryTool::new(self.app_handle.clone())), None));
        tools.push((
            Arc::new(PageSnapshotTool::new(self.app_handle.clone())),
            None,
        ));
        tools.push((Arc::new(TabsTool::new(self.browser_engine.clone())), None));
        tools.push((
            Arc::new(WalletInfoTool::new(
                self.wallet_store.clone(),
                wallet_owner.clone(),
            )),
            None,
        ));
        tools.push((
            Arc::new(WalletSpendTool::new(
                self.wallet_store.clone(),
                wallet_owner.clone(),
            )),
            Some(CapabilityKind::WalletSpend),
        ));

        let iproov = self.iproov.clone();
        tools.push((
            Arc::new(GatewayCreatePresentationTool::new(iproov.clone())),
            None,
        ));
        tools.push((
            Arc::new(GatewayApprovePresentationTool::new(iproov.clone())),
            None,
        ));
        tools.push((
            Arc::new(GatewayAwaitDecisionTool::new(iproov.clone())),
            None,
        ));
        tools.push((Arc::new(GatewayIntrospectTool::new(iproov.clone())), None));
        tools.push((Arc::new(MerchantQuoteCartTool::new(iproov.clone())), None));
        tools.push((Arc::new(GatewayApproveCartTool::new(iproov.clone())), None));
        tools.push((Arc::new(GatewayFetchMandateTool::new(iproov.clone())), None));
        tools.push((Arc::new(MerchantPlaceOrderTool::new(iproov)), None));

        let remote_tools = self.mcp_registry.remote_tools().await;
        tools.extend(remote_tools);

        tools
    }
}

struct MeteredModel {
    inner: Arc<dyn LanguageModelClient>,
    credits: Arc<AsyncMutex<CreditAccount>>,
    tokens_used: AtomicU64,
    estimated_tokens_used: AtomicU64,
}

impl MeteredModel {
    fn new(
        inner: Arc<dyn LanguageModelClient>,
        credits: Arc<AsyncMutex<CreditAccount>>,
    ) -> Arc<Self> {
        Arc::new(Self {
            inner,
            credits,
            tokens_used: AtomicU64::new(0),
            estimated_tokens_used: AtomicU64::new(0),
        })
    }

    fn reset(&self) {
        self.tokens_used.store(0, Ordering::SeqCst);
        self.estimated_tokens_used.store(0, Ordering::SeqCst);
    }

    fn tokens_used(&self) -> u64 {
        self.tokens_used.load(Ordering::SeqCst)
    }

    fn used_estimated_tokens(&self) -> bool {
        self.estimated_tokens_used.load(Ordering::SeqCst) > 0
    }
}

#[async_trait]
impl LanguageModelClient for MeteredModel {
    async fn complete(
        &self,
        prompt: &str,
        options: &FoundationModelOptions,
    ) -> anyhow::Result<LanguageModelResponse> {
        let mut response = self.inner.complete(prompt, options).await?;
        let (tokens, estimated) = usage_tokens(prompt, &response);
        if response.usage.total_tokens.is_none() && tokens > 0 {
            response.usage.total_tokens = Some(tokens);
        }

        if tokens > 0 {
            self.tokens_used.fetch_add(tokens as u64, Ordering::SeqCst);
            if estimated {
                self.estimated_tokens_used
                    .fetch_add(tokens as u64, Ordering::SeqCst);
            }
            let mut account = self.credits.lock().await;
            if let Err(err) = account.charge(tokens) {
                return Err(anyhow!(err));
            }
        }

        Ok(response)
    }
}

fn usage_tokens(prompt: &str, response: &LanguageModelResponse) -> (u32, bool) {
    if let Some(total) = response.usage.total_tokens {
        return (total, false);
    }

    let prompt_tokens = response
        .usage
        .prompt_tokens
        .unwrap_or_else(|| estimate_tokens(prompt));
    let completion_tokens = response
        .usage
        .completion_tokens
        .unwrap_or_else(|| estimate_tokens(&response.text));
    let estimated =
        response.usage.prompt_tokens.is_none() || response.usage.completion_tokens.is_none();

    (prompt_tokens.saturating_add(completion_tokens), estimated)
}

fn estimate_tokens(input: &str) -> u32 {
    let chars = input.chars().count() as u64;
    if chars == 0 {
        0
    } else {
        chars.div_ceil(4).min(u32::MAX as u64) as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ai_agent::language_model::LanguageModelUsage;
    use ai_agent::LanguageModelResponse;
    use async_trait::async_trait;
    use std::sync::{Arc, Mutex};
    use tokio::sync::Mutex as AsyncMutex;

    #[derive(Clone)]
    struct StubModel {
        response: LanguageModelResponse,
        calls: Arc<Mutex<Vec<String>>>,
    }

    #[async_trait]
    impl LanguageModelClient for StubModel {
        async fn complete(
            &self,
            prompt: &str,
            _options: &FoundationModelOptions,
        ) -> anyhow::Result<LanguageModelResponse> {
            self.calls
                .lock()
                .expect("stub model call log poisoned")
                .push(prompt.to_string());
            Ok(self.response.clone())
        }
    }

    #[tokio::test]
    async fn metered_model_tracks_usage_and_charges() {
        let response = LanguageModelResponse {
            text: "ok".into(),
            usage: LanguageModelUsage {
                total_tokens: Some(42),
                prompt_tokens: Some(20),
                completion_tokens: Some(22),
            },
        };
        let stub = StubModel {
            response,
            calls: Arc::new(Mutex::new(Vec::new())),
        };
        let credits = Arc::new(AsyncMutex::new(CreditAccount::new(100)));
        let metered = MeteredModel::new(Arc::new(stub.clone()), credits.clone());

        let result = metered
            .complete("summarise", &FoundationModelOptions::default())
            .await
            .expect("stub completion should succeed");
        assert_eq!(result.text, "ok");
        assert_eq!(
            stub.calls.lock().unwrap().as_slice(),
            &["summarise".to_string()]
        );

        let balance = credits.lock().await.balance();
        assert_eq!(balance, 58);
        assert_eq!(metered.tokens_used(), 42);
    }

    #[tokio::test]
    async fn metered_model_propagates_credit_errors() {
        let response = LanguageModelResponse {
            text: "denied".into(),
            usage: LanguageModelUsage {
                total_tokens: Some(80),
                prompt_tokens: None,
                completion_tokens: None,
            },
        };
        let stub = StubModel {
            response,
            calls: Arc::new(Mutex::new(Vec::new())),
        };
        let credits = Arc::new(AsyncMutex::new(CreditAccount::new(50)));
        let metered = MeteredModel::new(Arc::new(stub.clone()), credits.clone());

        let err = metered
            .complete("exhaust", &FoundationModelOptions::default())
            .await
            .expect_err("credit exhaustion should error");
        assert!(
            err.to_string().contains("insufficient credits"),
            "unexpected error message: {err}"
        );

        assert_eq!(
            stub.calls.lock().unwrap().as_slice(),
            &["exhaust".to_string()]
        );
        assert_eq!(metered.tokens_used(), 80);
    }

    #[tokio::test]
    async fn metered_model_estimates_missing_usage() {
        let response = LanguageModelResponse::new("estimated output".into());
        let stub = StubModel {
            response,
            calls: Arc::new(Mutex::new(Vec::new())),
        };
        let credits = Arc::new(AsyncMutex::new(CreditAccount::new(100)));
        let metered = MeteredModel::new(Arc::new(stub), credits.clone());

        let result = metered
            .complete("estimate this prompt", &FoundationModelOptions::default())
            .await
            .expect("fallback estimation should still succeed");

        let expected = estimate_tokens("estimate this prompt") + estimate_tokens(&result.text);
        assert_eq!(result.usage.total_tokens, Some(expected));
        assert_eq!(metered.tokens_used(), expected as u64);
        assert!(metered.used_estimated_tokens());
        assert_eq!(credits.lock().await.balance(), 100 - expected as i64);
    }
}
