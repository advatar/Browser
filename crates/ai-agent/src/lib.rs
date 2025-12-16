//! Core AI agent orchestration primitives shared by the Browser workspace.
//! The crate exposes a simple agent runtime that can plan tool calls using
//! the macOS Foundation Model runtime (when available) and execute MCP-style
//! tools provided by the host application.

pub mod foundation;
pub mod language_model;
pub mod mcp;
pub mod orchestrator;

pub use foundation::{FoundationModelClient, FoundationModelOptions, PlatformModelClient};
pub use language_model::{LanguageModelClient, LanguageModelResponse};
pub use mcp::{McpTool, McpToolDescription, McpToolError, McpToolResult};
pub use orchestrator::{
    AgentConfig, AgentEvent, AgentOrchestrator, AgentResult, PlanStep, ToolInvocation,
};

pub const DEFAULT_AGENT_MAX_STEPS: usize = 8;
