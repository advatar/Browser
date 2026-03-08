use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

const DEFAULT_SCHEDULES_PATH: &str = "configs/agent_app_schedules.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentAppScheduleDefinition {
    pub id: String,
    pub app_id: String,
    pub label: String,
    #[serde(default)]
    pub input: Option<String>,
    pub interval_minutes: u64,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
    #[serde(default)]
    pub last_run_at_ms: Option<u64>,
    #[serde(default)]
    pub next_run_at_ms: Option<u64>,
    #[serde(default)]
    pub last_run_status: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentAppScheduleDraft {
    #[serde(default)]
    pub id: Option<String>,
    pub app_id: String,
    #[serde(default)]
    pub label: Option<String>,
    #[serde(default)]
    pub input: Option<String>,
    pub interval_minutes: u64,
    #[serde(default = "default_enabled")]
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentAppScheduleSummary {
    pub id: String,
    pub app_id: String,
    pub label: String,
    pub input: Option<String>,
    pub interval_minutes: u64,
    pub enabled: bool,
    pub last_run_at_ms: Option<u64>,
    pub next_run_at_ms: Option<u64>,
    pub last_run_status: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
struct AgentAppScheduleManifest {
    schedules: Vec<AgentAppScheduleDefinition>,
}

fn default_enabled() -> bool {
    true
}

fn interval_millis(interval_minutes: u64) -> u64 {
    interval_minutes.max(1).saturating_mul(60_000)
}

fn compute_next_run_at_ms(interval_minutes: u64, from_ms: u64) -> u64 {
    from_ms.saturating_add(interval_millis(interval_minutes))
}

impl AgentAppScheduleDefinition {
    fn summary(&self) -> AgentAppScheduleSummary {
        AgentAppScheduleSummary {
            id: self.id.clone(),
            app_id: self.app_id.clone(),
            label: self.label.clone(),
            input: self.input.clone(),
            interval_minutes: self.interval_minutes,
            enabled: self.enabled,
            last_run_at_ms: self.last_run_at_ms,
            next_run_at_ms: self.next_run_at_ms,
            last_run_status: self.last_run_status.clone(),
        }
    }

    fn from_draft(draft: AgentAppScheduleDraft, now_ms: u64) -> Self {
        let id = draft.id.unwrap_or_else(|| Uuid::new_v4().to_string());
        let label = draft
            .label
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| draft.app_id.clone());
        let next_run_at_ms = if draft.enabled {
            Some(compute_next_run_at_ms(draft.interval_minutes, now_ms))
        } else {
            None
        };

        Self {
            id,
            app_id: draft.app_id.trim().to_string(),
            label,
            input: draft.input.and_then(trimmed_or_none),
            interval_minutes: draft.interval_minutes.max(1),
            enabled: draft.enabled,
            last_run_at_ms: None,
            next_run_at_ms,
            last_run_status: Some("scheduled".to_string()),
        }
    }
}

pub struct AgentAppScheduleRegistry {
    schedules: Arc<RwLock<Vec<AgentAppScheduleDefinition>>>,
    manifest_path: PathBuf,
}

impl AgentAppScheduleRegistry {
    pub fn load_default() -> Result<Self> {
        Self::from_path(DEFAULT_SCHEDULES_PATH)
    }

    pub fn from_path(path: impl AsRef<Path>) -> Result<Self> {
        let manifest_path = path.as_ref().to_path_buf();
        let schedules = Self::read_manifest(&manifest_path)?;
        Ok(Self {
            schedules: Arc::new(RwLock::new(schedules)),
            manifest_path,
        })
    }

    pub fn empty() -> Self {
        Self {
            schedules: Arc::new(RwLock::new(Vec::new())),
            manifest_path: PathBuf::from(DEFAULT_SCHEDULES_PATH),
        }
    }

    pub fn list(&self) -> Vec<AgentAppScheduleSummary> {
        let mut schedules = self
            .schedules
            .read()
            .expect("agent app schedules poisoned")
            .iter()
            .map(AgentAppScheduleDefinition::summary)
            .collect::<Vec<_>>();
        schedules.sort_by(|left, right| {
            right
                .next_run_at_ms
                .unwrap_or_default()
                .cmp(&left.next_run_at_ms.unwrap_or_default())
        });
        schedules
    }

    pub fn upsert(&self, draft: AgentAppScheduleDraft, now_ms: u64) -> Result<AgentAppScheduleSummary> {
        if draft.app_id.trim().is_empty() {
            return Err(anyhow::anyhow!("app_id must not be empty"));
        }
        if draft.interval_minutes == 0 {
            return Err(anyhow::anyhow!("interval_minutes must be at least 1"));
        }

        let mut schedules = self
            .schedules
            .write()
            .expect("agent app schedules poisoned");

        let summary = if let Some(id) = draft.id.as_deref().filter(|value| !value.trim().is_empty()) {
            let schedule = schedules
                .iter_mut()
                .find(|schedule| schedule.id == id)
                .ok_or_else(|| anyhow::anyhow!("agent app schedule `{id}` not found"))?;
            schedule.app_id = draft.app_id.trim().to_string();
            schedule.label = draft
                .label
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or(schedule.app_id.as_str())
                .to_string();
            schedule.input = draft.input.and_then(trimmed_or_none);
            schedule.interval_minutes = draft.interval_minutes.max(1);
            schedule.enabled = draft.enabled;
            schedule.next_run_at_ms = if schedule.enabled {
                Some(compute_next_run_at_ms(schedule.interval_minutes, now_ms))
            } else {
                None
            };
            schedule.last_run_status = Some(if schedule.enabled {
                "scheduled".to_string()
            } else {
                "disabled".to_string()
            });
            schedule.summary()
        } else {
            let schedule = AgentAppScheduleDefinition::from_draft(draft, now_ms);
            let summary = schedule.summary();
            schedules.push(schedule);
            summary
        };

        Self::write_manifest(&self.manifest_path, &schedules)?;
        Ok(summary)
    }

    pub fn delete(&self, id: &str) -> Result<bool> {
        let mut schedules = self
            .schedules
            .write()
            .expect("agent app schedules poisoned");
        let before = schedules.len();
        schedules.retain(|schedule| schedule.id != id);
        let removed = schedules.len() != before;
        if removed {
            Self::write_manifest(&self.manifest_path, &schedules)?;
        }
        Ok(removed)
    }

    pub fn claim_due(&self, now_ms: u64) -> Result<Vec<AgentAppScheduleDefinition>> {
        let mut schedules = self
            .schedules
            .write()
            .expect("agent app schedules poisoned");
        let mut due = Vec::new();

        for schedule in schedules.iter_mut() {
            if !schedule.enabled {
                continue;
            }
            let next_run_at_ms = schedule
                .next_run_at_ms
                .unwrap_or_else(|| compute_next_run_at_ms(schedule.interval_minutes, now_ms));
            if next_run_at_ms > now_ms {
                continue;
            }
            schedule.last_run_at_ms = Some(now_ms);
            schedule.next_run_at_ms = Some(compute_next_run_at_ms(schedule.interval_minutes, now_ms));
            schedule.last_run_status = Some("running".to_string());
            due.push(schedule.clone());
        }

        if !due.is_empty() {
            Self::write_manifest(&self.manifest_path, &schedules)?;
        }

        Ok(due)
    }

    pub fn record_run_result(&self, id: &str, status: &str) -> Result<()> {
        let mut schedules = self
            .schedules
            .write()
            .expect("agent app schedules poisoned");
        if let Some(schedule) = schedules.iter_mut().find(|schedule| schedule.id == id) {
            schedule.last_run_status = Some(status.to_string());
            Self::write_manifest(&self.manifest_path, &schedules)?;
        }
        Ok(())
    }

    fn read_manifest(path: &Path) -> Result<Vec<AgentAppScheduleDefinition>> {
        if !path.exists() {
            return Ok(Vec::new());
        }
        let raw = fs::read_to_string(path)
            .with_context(|| format!("reading agent app schedules at {}", path.display()))?;
        let manifest: AgentAppScheduleManifest = serde_json::from_str(&raw)
            .with_context(|| format!("parsing agent app schedules at {}", path.display()))?;
        Ok(manifest.schedules)
    }

    fn write_manifest(path: &Path, schedules: &[AgentAppScheduleDefinition]) -> Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("creating agent app schedules dir {}", parent.display()))?;
        }
        let manifest = serde_json::json!({ "schedules": schedules });
        let raw = serde_json::to_string_pretty(&manifest)?;
        fs::write(path, raw)
            .with_context(|| format!("writing agent app schedules at {}", path.display()))?;
        Ok(())
    }
}

fn trimmed_or_none(value: String) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_manifest_path(name: &str) -> PathBuf {
        let dir = std::env::temp_dir()
            .join("dbrowser-agent-app-schedules-tests")
            .join(Uuid::new_v4().to_string());
        fs::create_dir_all(&dir).expect("create temp test dir");
        dir.join(name)
    }

    #[test]
    fn upsert_persists_schedule_manifest() {
        let path = temp_manifest_path("schedules.json");
        let registry = AgentAppScheduleRegistry::from_path(&path).expect("registry");

        let summary = registry
            .upsert(
                AgentAppScheduleDraft {
                    id: None,
                    app_id: "research-brief".to_string(),
                    label: Some("Morning brief".to_string()),
                    input: Some("Summarise today's web3 funding".to_string()),
                    interval_minutes: 60,
                    enabled: true,
                },
                1_000,
            )
            .expect("schedule saved");

        let reloaded = AgentAppScheduleRegistry::from_path(&path).expect("reloaded");
        let schedules = reloaded.list();
        assert_eq!(schedules.len(), 1);
        assert_eq!(schedules[0].id, summary.id);
        assert_eq!(schedules[0].label, "Morning brief");
        assert_eq!(schedules[0].next_run_at_ms, Some(3_601_000));
    }

    #[test]
    fn claim_due_advances_next_run_and_marks_running() {
        let path = temp_manifest_path("due.json");
        let registry = AgentAppScheduleRegistry::from_path(&path).expect("registry");
        let summary = registry
            .upsert(
                AgentAppScheduleDraft {
                    id: None,
                    app_id: "workflow-designer".to_string(),
                    label: Some("Ops cadence".to_string()),
                    input: None,
                    interval_minutes: 15,
                    enabled: true,
                },
                0,
            )
            .expect("schedule saved");

        let due = registry.claim_due(summary.next_run_at_ms.unwrap()).expect("claimed");
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].id, summary.id);

        let schedules = registry.list();
        assert_eq!(schedules[0].last_run_status.as_deref(), Some("running"));
        assert_eq!(schedules[0].next_run_at_ms, Some(1_800_000));
    }

    #[test]
    fn delete_removes_schedule() {
        let path = temp_manifest_path("delete.json");
        let registry = AgentAppScheduleRegistry::from_path(&path).expect("registry");
        let summary = registry
            .upsert(
                AgentAppScheduleDraft {
                    id: None,
                    app_id: "research-brief".to_string(),
                    label: None,
                    input: None,
                    interval_minutes: 30,
                    enabled: true,
                },
                100,
            )
            .expect("schedule saved");

        assert!(registry.delete(&summary.id).expect("delete schedule"));
        assert!(registry.list().is_empty());
    }
}
