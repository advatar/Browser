use anyhow::Result;
use clap::{Parser, Subcommand};
use ipfs::{blockstore::SledStore, default_ipfs_path};
use std::path::PathBuf;

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    /// Path to the IPFS data directory
    #[arg(short, long, default_value_os_t = default_ipfs_path())]
    data_dir: PathBuf,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Store data in the blockstore and print its CID
    Put {
        /// Data to store (as a string)
        data: String,
    },
    /// Retrieve data from the blockstore by CID
    Get {
        /// CID of the data to retrieve
        cid: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let cli = Cli::parse();
    let store = SledStore::new(&cli.data_dir)?;

    match cli.command {
        Commands::Put { data } => {
            let cid = store.put(data.as_bytes())?;
            println!("Stored data with CID: {}", cid);
        }
        Commands::Get { cid } => {
            let cid = cid.parse()?;
            if let Some(data) = store.get(&cid)? {
                if let Ok(s) = String::from_utf8(data) {
                    println!("{}", s);
                } else {
                    println!("<binary data>");
                }
            } else {
                eprintln!("No data found for CID: {}", cid);
                std::process::exit(1);
            }
        }
    }

    Ok(())
}
