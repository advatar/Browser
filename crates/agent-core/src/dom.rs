use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

/// Actions the agent can perform on the DOM through the instrumentation bridge.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum DomAction {
    Click { selector: String },
    Scroll { dx: i32, dy: i32 },
    Type { selector: String, text: String },
    Navigate { url: String },
}

impl DomAction {
    pub fn description(&self) -> String {
        match self {
            DomAction::Click { selector } => format!("click {}", selector),
            DomAction::Scroll { dx, dy } => format!("scroll dx={}, dy={}", dx, dy),
            DomAction::Type { selector, text } => {
                format!("type into {} ({} chars)", selector, text.chars().count())
            }
            DomAction::Navigate { url } => format!("navigate {}", url),
        }
    }
}

/// Event emitted when an action is executed.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomEvent {
    pub sequence: u64,
    pub action: DomAction,
    pub timestamp_ms: u64,
}

impl DomEvent {
    pub fn new(sequence: u64, action: DomAction, timestamp_ms: u64) -> Self {
        Self {
            sequence,
            action,
            timestamp_ms,
        }
    }
}

/// Observation returned to the agent after a DOM action.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DomObservation {
    pub event: DomEvent,
    pub message: String,
}

impl DomObservation {
    pub fn new(event: DomEvent, message: String) -> Self {
        Self { event, message }
    }
}

/// In-memory instrumentation layer that records DOM events for the runtime.
#[derive(Debug, Default)]
pub struct DomInstrumentation {
    events: Vec<DomEvent>,
    next_sequence: u64,
}

impl DomInstrumentation {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn execute(&mut self, action: DomAction) -> DomObservation {
        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);
        let timestamp_ms = current_timestamp_ms();
        let event = DomEvent::new(sequence, action.clone(), timestamp_ms);
        self.events.push(event.clone());
        let message = format!("{} executed", action.description());
        DomObservation::new(event, message)
    }

    pub fn events(&self) -> &[DomEvent] {
        &self.events
    }
}

fn current_timestamp_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}
