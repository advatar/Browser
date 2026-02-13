use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use agent_core::{CapabilityKind, CapabilityLimit, CapabilityRegistry};
use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct SkillDefinition {
    pub id: String,
    pub name: String,
    pub description: String,
    #[serde(default)]
    pub system_prompt: Option<String>,
    #[serde(default)]
    pub max_steps: Option<usize>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub capabilities: HashMap<String, CapabilityLimitSpec>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
pub enum CapabilityLimitSpec {
    Number(u32),
    Map { max_calls_per_run: Option<u32> },
    Text(String),
    Null,
}

impl CapabilityLimitSpec {
    fn to_limit(&self) -> CapabilityLimit {
        match self {
            CapabilityLimitSpec::Number(value) => CapabilityLimit::limited(*value),
            CapabilityLimitSpec::Map { max_calls_per_run } => match max_calls_per_run {
                Some(value) => CapabilityLimit::limited(*value),
                None => CapabilityLimit::unlimited(),
            },
            CapabilityLimitSpec::Text(text) => {
                if text.eq_ignore_ascii_case("unlimited") {
                    CapabilityLimit::unlimited()
                } else {
                    CapabilityLimit::unlimited()
                }
            }
            CapabilityLimitSpec::Null => CapabilityLimit::unlimited(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct SkillRegistry {
    skills: Vec<SkillDefinition>,
}

impl SkillRegistry {
    pub fn load() -> Result<Self> {
        let manifest_path = PathBuf::from("skills/manifest.json");
        let skills = if manifest_path.exists() {
            let contents = fs::read_to_string(&manifest_path)
                .with_context(|| format!("reading skill manifest at {:?}", manifest_path))?;
            serde_json::from_str::<Vec<SkillDefinition>>(&contents)
                .with_context(|| "parsing skills manifest")?
        } else {
            default_skills()
        };

        Ok(Self { skills })
    }

    pub fn list(&self) -> &[SkillDefinition] {
        &self.skills
    }

    pub fn find(&self, id: &str) -> Option<&SkillDefinition> {
        self.skills.iter().find(|skill| skill.id == id)
    }

    pub fn build_capabilities(&self, skill_id: Option<&str>) -> CapabilityRegistry {
        let mut registry = CapabilityRegistry::with_browser_defaults();
        if let Some(skill_id) = skill_id {
            if let Some(skill) = self.find(skill_id) {
                for (capability, spec) in &skill.capabilities {
                    if let Some(kind) = CapabilityKind::parse(capability) {
                        registry.grant(kind, spec.to_limit());
                    }
                }
            }
        }
        registry
    }
}

fn default_skills() -> Vec<SkillDefinition> {
    serde_json::from_value(serde_json::json!([
        {
            "id": "extractor-ella",
            "name": "Extractor Ella",
            "description": "Extracts structured data from listings and exports to local storage.",
            "system_prompt": "You are Extractor Ella, focused on gathering structured leads into spreadsheets with minimal steps.",
            "max_steps": 6,
            "capabilities": {
                "click": null,
                "scroll": null,
                "type": { "max_calls_per_run": 12 },
                "navigate": { "max_calls_per_run": 6 },
                "email:send": { "max_calls_per_run": 0 }
            },
            "tags": ["research", "data"]
        },
        {
            "id": "sales-sally",
            "name": "Sales Sally",
            "description": "Finds contact emails, drafts outreach, and logs to CRM sheets.",
            "system_prompt": "You are Sales Sally. Always confirm contact details and keep tone upbeat yet concise.",
            "max_steps": 7,
            "capabilities": {
                "click": null,
                "scroll": null,
                "type": null,
                "navigate": { "max_calls_per_run": 8 },
                "email:send": { "max_calls_per_run": 2 }
            },
            "tags": ["sales", "outreach"]
        },
        {
            "id": "recruiter-riley",
            "name": "Recruiter Riley",
            "description": "Searches professional networks and compiles candidate shortlists.",
            "system_prompt": "You are Recruiter Riley. Focus on accuracy and keep notes brief.",
            "max_steps": 6,
            "capabilities": {
                "click": null,
                "scroll": null,
                "type": { "max_calls_per_run": 10 },
                "navigate": { "max_calls_per_run": 6 },
                "email:send": { "max_calls_per_run": 1 }
            },
            "tags": ["recruiting"]
        },
        {
            "id": "assistant-ari",
            "name": "Assistant Ari",
            "description": "General browser assistant for summarising pages and scheduling tasks.",
            "system_prompt": "You are Assistant Ari, a safety-first general purpose browsing assistant.",
            "max_steps": 5,
            "capabilities": {
                "click": null,
                "scroll": null,
                "type": { "max_calls_per_run": 6 },
                "navigate": { "max_calls_per_run": 5 },
                "email:send": { "max_calls_per_run": 0 }
            },
            "tags": ["assistant"]
        },
        {
            "id": "research-ravi",
            "name": "Research Ravi",
            "description": "Deep dives into competitive intelligence with rigorous note taking.",
            "system_prompt": "You are Research Ravi. Surface key numbers, cite sources, and capture follow-ups.",
            "max_steps": 8,
            "capabilities": {
                "click": null,
                "scroll": null,
                "type": { "max_calls_per_run": 12 },
                "navigate": { "max_calls_per_run": 9 },
                "email:send": { "max_calls_per_run": 0 }
            },
            "tags": ["research", "analysis"]
        }
    ])).expect("default skills to be valid JSON")
}
