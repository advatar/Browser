AFM Control Panel

  - Added a floating AFM node control/status card with full styling plus task/gossip forms so you can drive the integration without leaving the browser UI.

  UI Wiring

  - Introduced typed AFM config/status snapshots, a dedicated AfmNodePanel controller, and global wiring so the front-end listens to afm-node-status events,
    calls the new start_afm_node/stop_afm_node/afm_submit_task/afm_feed_gossip commands, and stays in sync with backend state.

  Verification

  - cargo check -p gui

  You can open the browser, expand the AFM card (bottom-right), and start/stop the stub node, send arbitrary task JSON, or push gossip frames straight into the
  controller. When you swap in the real AFM node binary, the panel will already surface its lifecycle and telemetry.
