pub mod afm;
pub mod agent;
pub mod agent_apps;
pub mod app_state;
pub mod browser_engine;
pub mod commands;
pub mod mcp_profiles;
pub mod performance;
pub mod protocol_handlers;
pub mod security;
pub mod telemetry;
pub mod telemetry_commands;
pub mod wallet_store;
pub mod wallet_ui;

// Re-export commonly used items at the crate root
pub use app_state::AppState;
