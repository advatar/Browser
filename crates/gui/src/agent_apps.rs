use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

const DEFAULT_APPS_PATH: &str = "configs/agent_apps.json";

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
