pub mod browser_engine;
pub mod protocol_handlers;
pub mod security;
pub mod telemetry;
pub mod telemetry_commands;
pub mod commands;
pub mod performance;
pub mod wallet_ui;
pub mod app_state;

// Re-export commonly used items at the crate root
pub use app_state::AppState;
