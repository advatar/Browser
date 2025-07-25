use anyhow::Result;
use clap::Parser;
use p2p::{P2PConfig, P2PService};
use std::time::Duration;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

/// Command-line arguments for the p2p daemon
#[derive(Parser, Debug)]
#[clap(version, about = "Decentralized Browser P2P Node")]
struct Args {
    /// Enable debug logging
    #[clap(short, long)]
    debug: bool,

    /// Disable mDNS discovery
    #[clap(long)]
    no_mdns: bool,


    /// Disable Kademlia DHT
    #[clap(long)]
    no_kademlia: bool,


    /// Bootstrap nodes to connect to (multiaddr format)
    #[clap(long, value_delimiter = ',')]
    bootstrap_nodes: Option<Vec<String>>,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Parse command line arguments
    let args = Args::parse();

    // Initialize logging
    let log_level = if args.debug {
        Level::DEBUG
    } else {
        Level::INFO
    };

    let subscriber = FmtSubscriber::builder()
        .with_max_level(log_level)
        .finish();
    tracing::subscriber::set_global_default(subscriber).expect("setting default subscriber failed");

    info!("Starting P2P node...");

    // Create P2P configuration
    let mut config = P2PConfig::default();
    config.enable_mdns = !args.no_mdns;
    config.enable_kademlia = !args.no_kademlia;
    
    if let Some(nodes) = args.bootstrap_nodes {
        config.bootstrap_nodes = nodes;
    }

    // Create P2P service with the specified configuration
    let mut service = P2PService::with_config(config)
        .expect("Failed to create P2P service");

    info!("Local peer ID: {}", service.peer_id);
    
    // Start the service
    if let Err(e) = service.start().await {
        eprintln!("Error starting P2P service: {}", e);
        std::process::exit(1);
    }

    // Keep the service running
    loop {
        tokio::time::sleep(Duration::from_secs(60)).await;
    }
    
    // Unreachable but keeps the compiler happy with the return type
    #[allow(unreachable_code)]
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[tokio::test]
    async fn test_p2p_service() -> Result<()> {
        let mut config = P2PConfig {
            enable_mdns: false,
            enable_kademlia: false,
            ..Default::default()
        };
        
        let mut service = P2PService::new(config)?;
        
        // Start the service in the background
        let handle = tokio::spawn(async move {
            service.start().await.unwrap();
        });
        
        // Give it a moment to start
        tokio::time::sleep(Duration::from_millis(100)).await;
        
        // Cancel the service
        handle.abort();
        
        Ok(())
    }
}

#[cfg(test)]
impl P2PService {
    /// Create a new P2P service with the provided configuration
    pub fn new(config: P2PConfig) -> Result<Self, anyhow::Error> {
        // Generate a fixed key for now
        let local_key = Self::generate_ed25519_keypair();
        let peer_id = PeerId::from(local_key.public());

        info!("Local peer ID: {}", peer_id);

        // Create a dummy swarm
        let swarm = todo!("Cannot create swarm due to dependency conflicts");

        // Set up the event channel
        let (event_sender, event_receiver) = mpsc::channel::<P2PEvent>(32);

        // Create a simple task handle (we'll actually spawn it in start())
        let task_handle = tokio::task::spawn(async {
            // This is just a placeholder and will be replaced in start()
        });

        Ok(Self {
            swarm,
            event_sender,
            event_receiver,
            _task_handle: task_handle,
            config,
            peer_id,
        })
    }
}
