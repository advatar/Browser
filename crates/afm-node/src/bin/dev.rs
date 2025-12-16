use std::time::Duration;

use afm_node::{AfmNodeConfig, AfmNodeController, AfmTaskDescriptor};
use serde_json::json;
use tokio::time::sleep;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter("info,afm_node=debug")
        .init();

    let controller = AfmNodeController::launch(AfmNodeConfig::default()).await?;
    let handle = controller.handle();

    handle
        .submit_task(AfmTaskDescriptor::new(
            "dev-demo",
            json!({ "message": "hello from afm-node stub" }),
        ))
        .await?;

    sleep(Duration::from_secs(1)).await;
    controller.shutdown().await?;
    Ok(())
}
