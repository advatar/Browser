//! Agent runtime crate providing DOM instrumentation, capability enforcement,
//! and ledger logging for the Advatar browser workspace.

pub mod approvals;
pub mod capabilities;
pub mod dom;
pub mod ledger;
pub mod runtime;

pub use approvals::ApprovalHandler;
pub use capabilities::{
    CapabilityError, CapabilityKind, CapabilityLimit, CapabilityRegistry, ConsumeOutcome,
};
pub use dom::{DomAction, DomEvent, DomObservation};
pub use ledger::{AgentLedger, LedgerEntry};
pub use runtime::{AgentRuntime, AgentRuntimeBuilder, AgentRuntimeResult};
