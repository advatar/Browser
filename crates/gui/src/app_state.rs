use std::sync::{Arc, Mutex};
use blockchain::Wallet;

use crate::browser_engine::BrowserEngine;
use crate::protocol_handlers::ProtocolHandler;
use crate::security::SecurityManager;
use crate::telemetry::TelemetryManager;

pub struct AppState {
    pub current_url: Mutex<String>,
    pub browser_engine: Arc<BrowserEngine>,
    pub protocol_handler: Arc<Mutex<ProtocolHandler>>,
    pub security_manager: Arc<Mutex<SecurityManager>>,
    pub telemetry_manager: Arc<Mutex<TelemetryManager>>,
    pub wallet: Arc<Mutex<Wallet>>, // simple in-memory wallet state
}
