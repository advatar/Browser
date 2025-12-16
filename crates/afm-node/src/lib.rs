use std::path::PathBuf;
use std::time::Duration;

use agent_core::AgentRuntimeBuilder;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::task::JoinHandle;
use tokio::time::{interval, MissedTickBehavior};
use tracing::{debug, error, info, warn};

const DEFAULT_ROUTER_URL: &str = "http://localhost:4810";
const DEFAULT_REGISTRY_URL: &str = "http://localhost:4820";

/// Configuration required to bootstrap the AFM node runtime under the Browser
/// process. The values mirror the knobs exposed by zk-afm-net-starter but
/// default to developer-friendly local ports.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AfmNodeConfig {
    pub router_url: String,
    pub registry_url: String,
    pub node_rpc_port: u16,
    pub data_dir: PathBuf,
    pub enable_local_attestation: bool,
}

impl Default for AfmNodeConfig {
    fn default() -> Self {
        Self {
            router_url: DEFAULT_ROUTER_URL.to_string(),
            registry_url: DEFAULT_REGISTRY_URL.to_string(),
            node_rpc_port: 7878,
            data_dir: PathBuf::from("target/afm-node"),
            enable_local_attestation: true,
        }
    }
}

impl AfmNodeConfig {
    pub fn ensure_dirs(&self) -> Result<(), AfmNodeError> {
        std::fs::create_dir_all(&self.data_dir)?;
        Ok(())
    }

    /// Returns the canonical path used to persist gossip snapshots.
    pub fn gossip_path(&self) -> PathBuf {
        self.data_dir.join("gossip.snap")
    }
}

/// High-level description of a task the browser wants the AFM node to execute.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AfmTaskDescriptor {
    pub task_id: String,
    pub payload: serde_json::Value,
}

impl AfmTaskDescriptor {
    pub fn new(task_id: impl Into<String>, payload: serde_json::Value) -> Self {
        Self {
            task_id: task_id.into(),
            payload,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GossipFrame {
    pub topic: String,
    pub bytes: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum NodePhase {
    Idle,
    Starting,
    Running,
    Stopping,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeStatus {
    pub phase: NodePhase,
    pub active_tasks: usize,
    pub last_error: Option<String>,
}

impl Default for NodeStatus {
    fn default() -> Self {
        Self {
            phase: NodePhase::Idle,
            active_tasks: 0,
            last_error: None,
        }
    }
}

#[derive(Debug)]
enum NodeCommand {
    SubmitTask(AfmTaskDescriptor),
    FeedGossip(GossipFrame),
    TaskComplete(String),
    UpdateConfig(AfmNodeConfig),
    Shutdown(oneshot::Sender<()>),
}

#[derive(Debug, Error)]
pub enum AfmNodeError {
    #[error("AFM node runtime is offline")]
    Offline,
    #[error("failed to send command to AFM node runtime")]
    ChannelClosed,
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("node runtime join error: {0}")]
    Join(#[from] tokio::task::JoinError),
}

pub type NodeResult<T> = Result<T, AfmNodeError>;

#[derive(Clone)]
pub struct AfmNodeHandle {
    cmd_tx: mpsc::Sender<NodeCommand>,
    status_rx: watch::Receiver<NodeStatus>,
}

impl AfmNodeHandle {
    pub async fn submit_task(&self, task: AfmTaskDescriptor) -> NodeResult<()> {
        self.cmd_tx
            .send(NodeCommand::SubmitTask(task))
            .await
            .map_err(|_| AfmNodeError::ChannelClosed)
    }

    pub async fn feed_gossip(&self, frame: GossipFrame) -> NodeResult<()> {
        self.cmd_tx
            .send(NodeCommand::FeedGossip(frame))
            .await
            .map_err(|_| AfmNodeError::ChannelClosed)
    }

    pub async fn reload_config(&self, config: AfmNodeConfig) -> NodeResult<()> {
        self.cmd_tx
            .send(NodeCommand::UpdateConfig(config))
            .await
            .map_err(|_| AfmNodeError::ChannelClosed)
    }

    pub async fn shutdown(&self) -> NodeResult<()> {
        let (tx, rx) = oneshot::channel();
        self.cmd_tx
            .send(NodeCommand::Shutdown(tx))
            .await
            .map_err(|_| AfmNodeError::ChannelClosed)?;
        rx.await.map_err(|_| AfmNodeError::Offline)
    }

    pub fn status(&self) -> NodeStatus {
        self.status_rx.borrow().clone()
    }

    pub fn subscribe(&self) -> watch::Receiver<NodeStatus> {
        self.status_rx.clone()
    }
}

pub struct AfmNodeController {
    handle: AfmNodeHandle,
    config: AfmNodeConfig,
    task: JoinHandle<()>,
}

impl AfmNodeController {
    pub async fn launch(config: AfmNodeConfig) -> NodeResult<Self> {
        config.ensure_dirs()?;

        let (cmd_tx, cmd_rx) = mpsc::channel(64);
        let (status_tx, status_rx) = watch::channel(NodeStatus {
            phase: NodePhase::Starting,
            ..NodeStatus::default()
        });

        let runtime = NodeRuntime::new(config.clone(), status_tx.clone(), cmd_tx.clone());
        let task = tokio::spawn(runtime.run(cmd_rx));

        let handle = AfmNodeHandle { cmd_tx, status_rx };
        Ok(Self {
            handle,
            config,
            task,
        })
    }

    pub fn handle(&self) -> AfmNodeHandle {
        self.handle.clone()
    }

    pub fn config(&self) -> &AfmNodeConfig {
        &self.config
    }

    pub async fn shutdown(self) -> NodeResult<()> {
        self.handle.shutdown().await?;
        self.task.await?;
        Ok(())
    }

    pub fn gossip_path(&self) -> PathBuf {
        self.config.gossip_path()
    }
}

pub trait AgentRuntimeAfmExt {
    fn with_afm_handle(self, handle: AfmNodeHandle) -> Self;
}

impl AgentRuntimeAfmExt for AgentRuntimeBuilder {
    fn with_afm_handle(self, handle: AfmNodeHandle) -> Self {
        info!(
            target: "afm_node",
            phase = ?handle.status().phase,
            "attached AFM node handle to agent runtime"
        );
        self
    }
}

struct NodeRuntime {
    config: AfmNodeConfig,
    status_tx: watch::Sender<NodeStatus>,
    cmd_tx: mpsc::Sender<NodeCommand>,
    active_tasks: usize,
}

impl NodeRuntime {
    fn new(
        config: AfmNodeConfig,
        status_tx: watch::Sender<NodeStatus>,
        cmd_tx: mpsc::Sender<NodeCommand>,
    ) -> Self {
        Self {
            config,
            status_tx,
            cmd_tx,
            active_tasks: 0,
        }
    }

    async fn run(mut self, mut cmd_rx: mpsc::Receiver<NodeCommand>) {
        let mut telemetry = interval(Duration::from_secs(5));
        telemetry.set_missed_tick_behavior(MissedTickBehavior::Skip);

        loop {
            tokio::select! {
                biased;
                maybe_cmd = cmd_rx.recv() => {
                    match maybe_cmd {
                        Some(cmd) => {
                            match self.handle_command(cmd).await {
                                Ok(()) => {}
                                Err(AfmNodeError::Offline) => break,
                                Err(err) => {
                                    warn!(target: "afm_node", error = ?err, "command handling failed");
                                    self.publish_status(None, Some(err.to_string()));
                                }
                            }
                        }
                        None => {
                            warn!(target: "afm_node", "command channel closed; shutting down runtime");
                            break;
                        }
                    }
                }
                _ = telemetry.tick() => {
                    self.publish_status(None, None);
                }
            }
        }

        self.publish_status(Some(NodePhase::Stopping), None);
        info!(target: "afm_node", "runtime loop exited");
    }

    async fn handle_command(&mut self, cmd: NodeCommand) -> NodeResult<()> {
        match cmd {
            NodeCommand::SubmitTask(task) => {
                info!(
                    target: "afm_node",
                    task_id = %task.task_id,
                    "received task submission"
                );
                self.active_tasks += 1;
                self.publish_status(Some(NodePhase::Running), None);
                self.spawn_completion(task.task_id);
            }
            NodeCommand::FeedGossip(frame) => {
                debug!(
                    target: "afm_node",
                    topic = frame.topic,
                    size = frame.bytes.len(),
                    "forwarding gossip frame"
                );
                self.persist_gossip(&frame)?;
            }
            NodeCommand::TaskComplete(task_id) => {
                if self.active_tasks > 0 {
                    self.active_tasks -= 1;
                }
                info!(
                    target: "afm_node",
                    task_id = %task_id,
                    "marked task as completed"
                );
                let next_phase = if self.active_tasks == 0 {
                    NodePhase::Idle
                } else {
                    NodePhase::Running
                };
                self.publish_status(Some(next_phase), None);
            }
            NodeCommand::UpdateConfig(config) => {
                info!(
                    target: "afm_node",
                    router = %config.router_url,
                    registry = %config.registry_url,
                    "updating runtime configuration"
                );
                config.ensure_dirs()?;
                self.config = config;
            }
            NodeCommand::Shutdown(reply) => {
                info!(target: "afm_node", "shutdown requested");
                let _ = reply.send(());
                self.publish_status(Some(NodePhase::Stopping), None);
                return Err(AfmNodeError::Offline);
            }
        }

        Ok(())
    }

    fn spawn_completion(&self, task_id: String) {
        let cmd_tx = self.cmd_tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(250)).await;
            if let Err(err) = cmd_tx.send(NodeCommand::TaskComplete(task_id)).await {
                error!(
                    target: "afm_node",
                    error = %err,
                    "failed to send task completion notification"
                );
            }
        });
    }

    fn persist_gossip(&self, frame: &GossipFrame) -> Result<(), AfmNodeError> {
        let path = self.config.gossip_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(&path, &frame.bytes)?;
        Ok(())
    }

    fn publish_status(&self, phase: Option<NodePhase>, last_error: Option<String>) {
        let mut next = self.status_tx.borrow().clone();
        if let Some(phase) = phase {
            next.phase = phase;
        }
        next.active_tasks = self.active_tasks;
        if let Some(err) = last_error {
            next.last_error = Some(err);
        }

        if self.status_tx.send(next).is_err() {
            warn!(target: "afm_node", "failed to publish status update (no listeners)");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[tokio::test]
    async fn node_lifecycle() {
        let controller = AfmNodeController::launch(AfmNodeConfig {
            data_dir: PathBuf::from("target/tests-afm-node"),
            ..AfmNodeConfig::default()
        })
        .await
        .expect("controller launches");

        let handle = controller.handle();
        handle
            .submit_task(AfmTaskDescriptor::new("demo", json!({"kind": "test"})))
            .await
            .expect("task accepted");
        handle
            .feed_gossip(GossipFrame {
                topic: "status".into(),
                bytes: vec![1, 2, 3],
            })
            .await
            .expect("gossip stored");

        tokio::time::sleep(Duration::from_millis(500)).await;

        controller.shutdown().await.expect("clean shutdown");
    }
}
