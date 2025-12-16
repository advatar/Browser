use std::env;
use std::path::PathBuf;

use afm_node::{AfmNodeConfig, NodeStatus};
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct AfmNodeSnapshot {
    pub config: AfmNodeConfig,
    pub status: NodeStatus,
}

impl AfmNodeSnapshot {
    pub fn new(config: AfmNodeConfig, status: NodeStatus) -> Self {
        Self { config, status }
    }
}

pub fn resolve_config(base: &AfmNodeConfig) -> AfmNodeConfig {
    let mut cfg = base.clone();

    if let Ok(router) = env::var("AFM_ROUTER_URL") {
        if !router.is_empty() {
            cfg.router_url = router;
        }
    }

    if let Ok(registry) = env::var("AFM_REGISTRY_URL") {
        if !registry.is_empty() {
            cfg.registry_url = registry;
        }
    }

    if let Ok(port) = env::var("AFM_NODE_RPC_PORT") {
        if let Ok(value) = port.parse::<u16>() {
            cfg.node_rpc_port = value;
        }
    }

    if let Ok(dir) = env::var("AFM_NODE_DATA_DIR") {
        if !dir.is_empty() {
            cfg.data_dir = PathBuf::from(dir);
        }
    }

    if let Ok(flag) = env::var("AFM_ENABLE_LOCAL_ATTESTATION") {
        if let Some(value) = parse_bool(&flag) {
            cfg.enable_local_attestation = value;
        }
    }

    cfg
}

fn parse_bool(input: &str) -> Option<bool> {
    match input.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}
