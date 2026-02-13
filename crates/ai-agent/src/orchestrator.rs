use std::sync::Arc;

use anyhow::{anyhow, Result};
use indexmap::IndexMap;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tracing::warn;

use crate::foundation::FoundationModelOptions;
use crate::language_model::{LanguageModelClient, LanguageModelResponse};
use crate::mcp::{McpTool, McpToolDescription};

#[derive(Debug, Clone)]
pub struct AgentConfig {
    pub system_prompt: String,
    pub max_steps: usize,
    pub model_options: FoundationModelOptions,
}

impl Default for AgentConfig {
    fn default() -> Self {
        let options = FoundationModelOptions {
            temperature: 0.4,
            max_tokens: Some(768),
            ..FoundationModelOptions::default()
        };
        Self {
            system_prompt: DEFAULT_SYSTEM_PROMPT.trim().to_string(),
            max_steps: crate::DEFAULT_AGENT_MAX_STEPS,
            model_options: options,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolInvocation {
    pub name: String,
    pub arguments: Value,
    pub observation: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PlanStep {
    Tool {
        thought: Option<String>,
        call: ToolInvocation,
    },
    Finish {
        summary: Option<String>,
        answer: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AgentEvent {
    ModelResponse { raw: String },
    ToolCall { name: String, args: Value },
    ToolResult { name: String, result: Value },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentResult {
    pub final_answer: Option<String>,
    pub steps: Vec<PlanStep>,
    pub events: Vec<AgentEvent>,
    pub halted: bool,
}

struct ToolRecord {
    description: McpToolDescription,
    handler: Arc<dyn McpTool>,
}

pub struct AgentOrchestrator {
    model: Arc<dyn LanguageModelClient>,
    config: AgentConfig,
    tools: IndexMap<String, ToolRecord>,
    history: Vec<DialogueTurn>,
    events: Vec<AgentEvent>,
}

impl AgentOrchestrator {
    pub fn new(model: Arc<dyn LanguageModelClient>, config: AgentConfig) -> Self {
        Self {
            model,
            config,
            tools: IndexMap::new(),
            history: Vec::new(),
            events: Vec::new(),
        }
    }

    pub fn register_tool(&mut self, tool: Arc<dyn McpTool>) {
        let description = tool.description().clone();
        self.tools.insert(
            description.name.clone(),
            ToolRecord {
                description,
                handler: tool,
            },
        );
    }

    pub fn tool_descriptions(&self) -> Vec<McpToolDescription> {
        self.tools
            .values()
            .map(|record| record.description.clone())
            .collect()
    }

    fn build_prompt(&self, task: &str) -> String {
        let mut prompt = String::new();
        prompt.push_str("You must decide the next best action given the conversation so far.\n\n");
        prompt.push_str("<<TOOLS>>\n");
        for record in self.tools.values() {
            prompt.push_str(&format!(
                "- {}: {}\n  input_schema: {}\n",
                record.description.name,
                record.description.description,
                serde_json::to_string_pretty(&record.description.input_schema)
                    .unwrap_or("{}".to_string())
            ));
        }
        prompt.push_str("<<CONTEXT>>\n");
        for turn in &self.history {
            match turn {
                DialogueTurn::User(msg) => {
                    prompt.push_str("User: ");
                    prompt.push_str(msg);
                    prompt.push('\n');
                }
                DialogueTurn::Agent(msg) => {
                    prompt.push_str("Agent: ");
                    prompt.push_str(msg);
                    prompt.push('\n');
                }
                DialogueTurn::Tool {
                    name,
                    args,
                    observation,
                } => {
                    prompt.push_str(&format!(
                        "ToolCall[{}]: {}\n",
                        name,
                        serde_json::to_string(args).unwrap_or_default()
                    ));
                    if let Some(obs) = observation {
                        prompt.push_str(&format!(
                            "Observation[{}]: {}\n",
                            name,
                            serde_json::to_string(obs).unwrap_or_default()
                        ));
                    }
                }
            }
        }
        prompt.push_str("<<TASK>>\n");
        prompt.push_str(task);
        prompt.push_str("\n\nRespond ONLY with JSON matching this schema:\n");
        prompt.push_str(JSON_SCHEMA_DESCRIPTION.trim());
        prompt
    }

    pub async fn run_task(&mut self, task: &str) -> Result<AgentResult> {
        self.history.push(DialogueTurn::User(task.to_string()));
        let mut steps = Vec::new();
        self.events.clear();

        for step_idx in 0..self.config.max_steps {
            let prompt = self.build_prompt(task);
            let mut options = self.config.model_options.clone();
            options.system_prompt = Some(self.config.system_prompt.clone());

            let response = self.model.complete(&prompt, &options).await?;
            self.events.push(AgentEvent::ModelResponse {
                raw: response.text.clone(),
            });

            let directive = self.parse_model_directive(&response)?;
            match directive {
                ModelDirective::Tool {
                    thought,
                    name,
                    args,
                } => {
                    let record = self
                        .tools
                        .get(&name)
                        .ok_or_else(|| anyhow!("Model requested unknown tool: {name}"))?
                        .handler
                        .clone();
                    self.events.push(AgentEvent::ToolCall {
                        name: name.clone(),
                        args: args.clone(),
                    });

                    let observation = record
                        .invoke(args.clone())
                        .await
                        .map_err(|err| anyhow!("Tool {} invocation failed: {}", name, err))?;
                    self.events.push(AgentEvent::ToolResult {
                        name: name.clone(),
                        result: observation.content.clone(),
                    });

                    self.history.push(DialogueTurn::Tool {
                        name: name.clone(),
                        args: args.clone(),
                        observation: Some(observation.content.clone()),
                    });
                    steps.push(PlanStep::Tool {
                        thought,
                        call: ToolInvocation {
                            name,
                            arguments: args,
                            observation: Some(observation.content),
                        },
                    });
                }
                ModelDirective::Finish { summary, answer } => {
                    steps.push(PlanStep::Finish {
                        summary,
                        answer: answer.clone(),
                    });
                    self.history.push(DialogueTurn::Agent(answer.clone()));
                    return Ok(AgentResult {
                        final_answer: Some(answer),
                        steps,
                        events: self.events.clone(),
                        halted: false,
                    });
                }
            }

            if step_idx + 1 == self.config.max_steps {
                warn!("Agent exhausted max_steps without finishing");
            }
        }

        Ok(AgentResult {
            final_answer: None,
            steps,
            events: self.events.clone(),
            halted: true,
        })
    }

    fn parse_model_directive(&self, response: &LanguageModelResponse) -> Result<ModelDirective> {
        let directive: ModelDirective = serde_json::from_str(&response.text).map_err(|err| {
            anyhow!(
                "Model response was not valid JSON directive: {}\nRaw: {}",
                err,
                response.text
            )
        })?;
        Ok(directive)
    }
}

#[derive(Debug, Clone)]
enum DialogueTurn {
    User(String),
    Agent(String),
    Tool {
        name: String,
        args: Value,
        observation: Option<Value>,
    },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ModelDirective {
    Tool {
        thought: Option<String>,
        name: String,
        args: Value,
    },
    Finish {
        summary: Option<String>,
        answer: String,
    },
}

const JSON_SCHEMA_DESCRIPTION: &str = r#"{
  "type": "object",
  "required": ["type"],
  "properties": {
    "type": {
      "type": "string",
      "enum": ["tool", "finish"]
    },
    "thought": {
      "type": "string",
      "description": "Concise reasoning for the chosen action"
    },
    "name": {
      "type": "string",
      "description": "When type=tool: the tool name to invoke"
    },
    "args": {
      "type": "object",
      "description": "JSON arguments for the selected tool"
    },
    "summary": {
      "type": "string",
      "description": "When finishing: optional short summary"
    },
    "answer": {
      "type": "string",
      "description": "When finishing: final response for the user"
    }
  }
}"#;

const DEFAULT_SYSTEM_PROMPT: &str = r#"
You are Advatar Copilot, an autonomous browsing agent. You decide on the next step for accomplishing the user's task.
Rules:
- Prefer calling tools for navigation, DOM inspection, wallet actions, and policy enforcement instead of fabricating answers.
- After each tool call, wait for the observation before planning further.
- When ready to respond to the user, emit type="finish" with a concise answer and actionable summary.
- Always respond with strict JSON matching the provided schema. Do not include any extra text, code fencing, or commentary.
- Tool arguments must be valid JSON objects; omit null keys.
"#;
