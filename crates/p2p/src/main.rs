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

    /// Listen port for the P2P service
    #[clap(short, long, default_value = "0")]
    port: u16,
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

    let subscriber = FmtSubscriber::builder().with_max_level(log_level).finish();
    tracing::subscriber::set_global_default(subscriber).expect("setting default subscriber failed");

    info!("Starting P2P node...");

    // Create P2P configuration
    let mut config = P2PConfig::default();
    config.enable_mdns = !args.no_mdns;
    config.enable_kademlia = !args.no_kademlia;

    // Set listen address with specified port
    config.listen_addr = format!("/ip4/0.0.0.0/tcp/{}", args.port)
        .parse()
        .expect("Valid multiaddr");

    if let Some(nodes) = args.bootstrap_nodes {
        config.bootstrap_nodes = nodes
            .into_iter()
            .filter_map(|addr| addr.parse().ok())
            .collect();
    }

    // Create P2P service with the specified configuration
    let mut service = P2PService::with_config(config).expect("Failed to create P2P service");

    info!("Local peer ID: {}", service.local_peer_id());

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
        let mut config = P2PConfig::default();
        config.enable_mdns = false;
        config.enable_kademlia = false;

        let service = P2PService::with_config(config)?;

        // Verify service creation
        assert_eq!(service.peer_count(), 0);
        assert!(!service.local_peer_id().to_string().is_empty());

        Ok(())
    }
}
