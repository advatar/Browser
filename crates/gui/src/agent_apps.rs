use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

const DEFAULT_APPS_PATH: &str = "configs/agent_apps.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BlockchainAccessContract {
    #[serde(default)]
    pub read_chain_data: bool,
    #[serde(default)]
    pub read_wallet_state: bool,
    #[serde(default)]
    pub prepare_transactions: bool,
    #[serde(default)]
    pub simulate_transactions: bool,
    #[serde(default)]
    pub request_signing: bool,
    #[serde(default)]
    pub request_broadcast: bool,
    #[serde(default)]
    pub account_scope: Option<String>,
    #[serde(default)]
    pub allowed_chain_refs: Vec<String>,
    #[serde(default)]
    pub spend_limit: Option<String>,
    #[serde(default)]
    pub approval_gates: Vec<String>,
    #[serde(default)]
    pub host_tools: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentAppDefinition {
    pub id: String,
    pub name: String,
    pub tagline: String,
    pub description: String,
    #[serde(default)]
    pub categories: Vec<String>,
    #[serde(default)]
    pub hero_color: Option<String>,
    #[serde(default)]
    pub quick_prompts: Vec<String>,
    #[serde(default)]
    pub input_hint: Option<String>,
    #[serde(default)]
    pub default_input: Option<String>,
    #[serde(default)]
    pub communication_surface: Option<String>,
    #[serde(default)]
    pub required_tools: Vec<String>,
    #[serde(default)]
    pub approval_gates: Vec<String>,
    #[serde(default)]
    pub blockchain_access: Option<BlockchainAccessContract>,
    #[serde(default)]
    pub skill_id: Option<String>,
    #[serde(default)]
    pub no_egress: Option<bool>,
    pub prompt_template: String,
    #[serde(default)]
    pub instructions: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentAppSummary {
    pub id: String,
    pub name: String,
    pub tagline: String,
    pub description: String,
    pub categories: Vec<String>,
    pub hero_color: Option<String>,
    pub quick_prompts: Vec<String>,
    pub input_hint: Option<String>,
    pub default_input: Option<String>,
    pub communication_surface: Option<String>,
    pub required_tools: Vec<String>,
    pub approval_gates: Vec<String>,
    pub blockchain_access: Option<BlockchainAccessContract>,
}

#[derive(Debug, Clone, Deserialize)]
struct AgentAppManifest {
    apps: Vec<AgentAppDefinition>,
}

impl AgentAppDefinition {
    pub fn summary(&self) -> AgentAppSummary {
        AgentAppSummary {
            id: self.id.clone(),
            name: self.name.clone(),
            tagline: self.tagline.clone(),
            description: self.description.clone(),
            categories: self.categories.clone(),
            hero_color: self.hero_color.clone(),
            quick_prompts: self.quick_prompts.clone(),
            input_hint: self.input_hint.clone(),
            default_input: self.default_input.clone(),
            communication_surface: self.communication_surface.clone(),
            required_tools: self.required_tools.clone(),
            approval_gates: self.approval_gates.clone(),
            blockchain_access: self.blockchain_access.clone(),
        }
    }

    pub fn render_task(&self, user_input: Option<&str>) -> String {
        let trimmed_input = user_input
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
            .map(|value| value.to_string())
            .or_else(|| self.default_input.clone())
            .unwrap_or_else(|| "".to_string());

        let mut prompt = self.prompt_template.clone();
        prompt = prompt.replace("{{input}}", &trimmed_input);

        if let Some(instructions) = &self.instructions {
            format!("{}\n\n{}", instructions.trim(), prompt.trim())
        } else {
            prompt
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn default_manifest_path() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../configs/agent_apps.json")
    }

    #[test]
    fn default_manifest_includes_travel_booker_a2ui_metadata() {
        let registry = AgentAppRegistry::from_path(default_manifest_path()).expect("registry");
        let app = registry.find("travel-booker").expect("travel-booker app");
        let summary = app.summary();

        assert_eq!(summary.name, "Travel Booker");
        assert_eq!(summary.communication_surface.as_deref(), Some("a2ui-v0.9"));
        assert!(summary.categories.iter().any(|category| category == "travel"));
        assert!(summary.required_tools.iter().any(|tool| tool == "browser.page_snapshot"));
        assert!(summary.required_tools.iter().any(|tool| tool == "browser.dom_query"));
        assert!(summary
            .approval_gates
            .iter()
            .any(|gate| gate.contains("booking")));
        let blockchain_access = summary.blockchain_access.expect("blockchain access");
        assert!(blockchain_access.read_chain_data);
        assert!(blockchain_access.read_wallet_state);
        assert!(blockchain_access.prepare_transactions);
        assert!(blockchain_access.simulate_transactions);
        assert!(blockchain_access.request_signing);
        assert!(blockchain_access.request_broadcast);
        assert_eq!(blockchain_access.account_scope.as_deref(), Some("selectedAccount"));
        assert!(blockchain_access
            .host_tools
            .iter()
            .any(|tool| tool == "dbrowser.tx.request_signature"));
    }

    #[test]
    fn default_manifest_includes_remaining_a2ui_demo_apps() {
        let registry = AgentAppRegistry::from_path(default_manifest_path()).expect("registry");
        let expected_apps = [
            ("travel-disruption-rebooker", "Travel Disruption Rebooker", "recovery", "rebook"),
            ("conference-trip-agent", "Conference Trip Agent", "events", "registration"),
            ("form-filling-concierge", "Form-Filling Concierge", "forms", "submit"),
            ("shopping-returns-agent", "Shopping and Returns Agent", "returns", "purchase"),
            ("apartment-stay-finder", "Apartment and Stay Finder", "housing", "application"),
        ];

        for (id, name, category, approval_fragment) in expected_apps {
            let app = registry.find(id).unwrap_or_else(|| panic!("{id} app"));
            let summary = app.summary();
            assert_eq!(summary.name, name);
            assert_eq!(summary.communication_surface.as_deref(), Some("a2ui-v0.9"));
            assert!(summary.categories.iter().any(|item| item == category));
            assert!(summary.required_tools.iter().any(|tool| tool == "browser.page_snapshot"));
            assert!(summary.required_tools.iter().any(|tool| tool == "browser.dom_query"));
            assert!(summary
                .approval_gates
                .iter()
                .any(|gate| gate.contains(approval_fragment)));
            let blockchain_access = summary
                .blockchain_access
                .unwrap_or_else(|| panic!("{id} blockchain access"));
            assert!(blockchain_access.read_chain_data);
            assert!(blockchain_access.read_wallet_state);
            assert!(blockchain_access.prepare_transactions);
            assert!(blockchain_access.request_signing);
            assert!(blockchain_access
                .approval_gates
                .iter()
                .any(|gate| gate.contains("broadcast")));

            let rendered = app.render_task(Some("Demo request with a current page."));
            assert!(rendered.contains("Demo request"));
            assert!(rendered.contains("A2UI v0.9"));
            assert!(rendered.contains("browser.page_snapshot"));
            assert!(rendered.contains("explicit user approval"));
        }
    }

    #[test]
    fn travel_booker_rendered_task_preserves_dom_a2ui_and_approval_requirements() {
        let registry = AgentAppRegistry::from_path(default_manifest_path()).expect("registry");
        let app = registry.find("travel-booker").expect("travel-booker app");

        let task = app.render_task(Some(
            "Find flights from SFO to Tokyo for May 20-27 under $1500 with one checked bag.",
        ));

        assert!(task.contains("SFO to Tokyo"));
        assert!(task.contains("A2UI v0.9"));
        assert!(task.contains("browser.page_snapshot"));
        assert!(task.contains("browser.dom_query"));
        assert!(task.contains("Do not book"));
        assert!(task.contains("explicit user approval"));
    }
}

pub struct AgentAppRegistry {
    apps: Arc<RwLock<Vec<AgentAppDefinition>>>,
    manifest_path: PathBuf,
}

impl AgentAppRegistry {
    pub fn load_default() -> Result<Self> {
        Self::from_path(DEFAULT_APPS_PATH)
    }

    pub fn from_path(path: impl AsRef<Path>) -> Result<Self> {
        let manifest_path = path.as_ref().to_path_buf();
        let apps = Self::read_manifest(&manifest_path)?;
        Ok(Self {
            apps: Arc::new(RwLock::new(apps)),
            manifest_path,
        })
    }

    pub fn empty() -> Self {
        Self {
            apps: Arc::new(RwLock::new(Vec::new())),
            manifest_path: PathBuf::from(DEFAULT_APPS_PATH),
        }
    }

    pub fn list(&self) -> Vec<AgentAppSummary> {
        self.apps
            .read()
            .expect("agent apps poisoned")
            .iter()
            .map(|app| app.summary())
            .collect()
    }

    pub fn find(&self, id: &str) -> Option<AgentAppDefinition> {
        self.apps
            .read()
            .expect("agent apps poisoned")
            .iter()
            .find(|app| app.id == id)
            .cloned()
    }

    pub fn reload(&self) -> Result<()> {
        let apps = Self::read_manifest(&self.manifest_path)?;
        let mut guard = self.apps.write().expect("agent apps poisoned");
        *guard = apps;
        Ok(())
    }

    fn read_manifest(path: &Path) -> Result<Vec<AgentAppDefinition>> {
        if !path.exists() {
            return Ok(Vec::new());
        }
        let raw = fs::read_to_string(path)
            .with_context(|| format!("reading agent apps manifest at {}", path.display()))?;
        let manifest: AgentAppManifest = serde_json::from_str(&raw)
            .with_context(|| format!("parsing agent apps manifest at {}", path.display()))?;
        Ok(manifest.apps)
    }
}
