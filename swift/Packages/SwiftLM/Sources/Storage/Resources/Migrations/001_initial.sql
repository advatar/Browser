PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hardware_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  collected_at TEXT NOT NULL,
  chip_family TEXT NOT NULL,
  performance_cores INTEGER,
  efficiency_cores INTEGER,
  gpu_cores INTEGER,
  total_memory_bytes INTEGER NOT NULL,
  os_version TEXT NOT NULL,
  metal_available INTEGER NOT NULL,
  notes_json TEXT
);

CREATE TABLE IF NOT EXISTS engine_backends (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  version TEXT,
  runtime_path TEXT,
  python_version TEXT,
  status TEXT NOT NULL,
  capabilities_json TEXT NOT NULL,
  last_healthcheck_at TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS models (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  source_kind TEXT NOT NULL,
  source_ref TEXT NOT NULL,
  family TEXT,
  architecture TEXT,
  modality TEXT NOT NULL,
  parameter_count INTEGER,
  quantization TEXT,
  tokenizer_family TEXT,
  chat_template_state TEXT NOT NULL,
  default_context_window INTEGER,
  size_on_disk_bytes INTEGER NOT NULL DEFAULT 0,
  primary_artifact_path TEXT,
  sha256 TEXT,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS model_artifacts (
  id TEXT PRIMARY KEY,
  model_id TEXT NOT NULL REFERENCES models(id) ON DELETE CASCADE,
  artifact_kind TEXT NOT NULL,
  path TEXT NOT NULL,
  format TEXT,
  size_bytes INTEGER,
  sha256 TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS model_capabilities (
  model_id TEXT PRIMARY KEY REFERENCES models(id) ON DELETE CASCADE,
  supports_vllm_metal INTEGER NOT NULL DEFAULT 0,
  supports_mlx_native INTEGER NOT NULL DEFAULT 0,
  supports_chat INTEGER NOT NULL DEFAULT 0,
  supports_responses INTEGER NOT NULL DEFAULT 0,
  supports_embeddings INTEGER NOT NULL DEFAULT 0,
  supports_vision INTEGER NOT NULL DEFAULT 0,
  supports_audio INTEGER NOT NULL DEFAULT 0,
  supports_tools INTEGER NOT NULL DEFAULT 0,
  supports_structured_outputs INTEGER NOT NULL DEFAULT 0,
  supports_reasoning INTEGER NOT NULL DEFAULT 0,
  needs_custom_chat_template INTEGER NOT NULL DEFAULT 0,
  risk_tier TEXT NOT NULL DEFAULT 'unknown',
  validation_json TEXT NOT NULL,
  last_validated_at TEXT
);

CREATE TABLE IF NOT EXISTS launch_profiles (
  id TEXT PRIMARY KEY,
  model_id TEXT NOT NULL REFERENCES models(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  preferred_engine TEXT NOT NULL,
  gpu_only INTEGER NOT NULL DEFAULT 1,
  context_window INTEGER NOT NULL,
  max_output_tokens INTEGER NOT NULL,
  temperature REAL,
  top_p REAL,
  top_k INTEGER,
  repetition_penalty REAL,
  enable_tools INTEGER NOT NULL DEFAULT 0,
  enable_reasoning INTEGER NOT NULL DEFAULT 0,
  structured_output_backend TEXT,
  chat_template_path TEXT,
  extra_args_json TEXT,
  env_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(model_id, name)
);

CREATE TABLE IF NOT EXISTS engine_instances (
  id TEXT PRIMARY KEY,
  engine_backend_id TEXT NOT NULL REFERENCES engine_backends(id),
  model_id TEXT NOT NULL REFERENCES models(id),
  launch_profile_id TEXT REFERENCES launch_profiles(id),
  pid INTEGER,
  host TEXT NOT NULL DEFAULT '127.0.0.1',
  port INTEGER,
  status TEXT NOT NULL,
  is_warm INTEGER NOT NULL DEFAULT 0,
  memory_reserved_bytes INTEGER NOT NULL DEFAULT 0,
  kv_cache_bytes INTEGER NOT NULL DEFAULT 0,
  queue_depth INTEGER NOT NULL DEFAULT 0,
  launched_at TEXT,
  stopped_at TEXT,
  last_heartbeat_at TEXT,
  crash_count INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT
);

CREATE TABLE IF NOT EXISTS downloads (
  id TEXT PRIMARY KEY,
  model_id TEXT REFERENCES models(id),
  source_url TEXT,
  destination_path TEXT,
  status TEXT NOT NULL,
  bytes_total INTEGER,
  bytes_completed INTEGER,
  checksum_expected TEXT,
  checksum_actual TEXT,
  error_text TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS benchmarks (
  id TEXT PRIMARY KEY,
  model_id TEXT NOT NULL REFERENCES models(id) ON DELETE CASCADE,
  engine_backend_id TEXT NOT NULL REFERENCES engine_backends(id),
  launch_profile_id TEXT REFERENCES launch_profiles(id),
  scenario TEXT NOT NULL,
  prompt_tokens INTEGER,
  output_tokens INTEGER,
  ttft_ms REAL,
  tok_s REAL,
  total_latency_ms REAL,
  peak_memory_bytes INTEGER,
  success INTEGER NOT NULL,
  raw_metrics_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT,
  model_id TEXT REFERENCES models(id),
  launch_profile_id TEXT REFERENCES launch_profiles(id),
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  metadata_json TEXT
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  content_json TEXT NOT NULL,
  tool_name TEXT,
  tool_call_id TEXT,
  token_count INTEGER,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS api_keys (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  key_hash TEXT NOT NULL UNIQUE,
  scopes_json TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_used_at TEXT,
  revoked_at TEXT
);

CREATE TABLE IF NOT EXISTS request_logs (
  id TEXT PRIMARY KEY,
  engine_instance_id TEXT REFERENCES engine_instances(id),
  model_id TEXT REFERENCES models(id),
  endpoint TEXT NOT NULL,
  status_code INTEGER,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  ttft_ms REAL,
  total_latency_ms REAL,
  client_name TEXT,
  store_body INTEGER NOT NULL DEFAULT 0,
  request_body_json TEXT,
  response_summary_json TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_models_status ON models(status);
CREATE INDEX IF NOT EXISTS idx_instances_status ON engine_instances(status);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON messages(conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_request_logs_created ON request_logs(created_at);
