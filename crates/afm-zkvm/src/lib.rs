use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio::fs;
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum ProverBackend {
    Sp1,
    RiscZero,
}

impl std::fmt::Display for ProverBackend {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProverBackend::Sp1 => write!(f, "SP1"),
            ProverBackend::RiscZero => write!(f, "RISC Zero"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZkvmHostConfig {
    pub backend: ProverBackend,
    pub program_dir: PathBuf,
    pub artifacts_dir: PathBuf,
}

impl Default for ZkvmHostConfig {
    fn default() -> Self {
        Self {
            backend: ProverBackend::Sp1,
            program_dir: PathBuf::from("zkvm/program"),
            artifacts_dir: PathBuf::from("target/afm-zkvm/artifacts"),
        }
    }
}

pub struct ZkvmHost {
    config: ZkvmHostConfig,
}

impl ZkvmHost {
    pub fn new(config: ZkvmHostConfig) -> Self {
        Self { config }
    }

    pub fn config(&self) -> &ZkvmHostConfig {
        &self.config
    }

    pub async fn ensure_layout(&self) -> Result<(), ZkvmHostError> {
        fs::create_dir_all(&self.config.program_dir).await?;
        fs::create_dir_all(&self.config.artifacts_dir).await?;
        Ok(())
    }

    pub async fn generate_proof(
        &self,
        request: &ZkvmProofRequest,
    ) -> Result<ZkvmProofArtifacts, ZkvmHostError> {
        self.ensure_layout().await?;

        let program_path = self.resolve_program(&request.program);
        if fs::metadata(&program_path).await.is_err() {
            return Err(ZkvmHostError::MissingProgram(program_path));
        }

        let input_path = self.resolve_program(&request.input);
        if fs::metadata(&input_path).await.is_err() {
            return Err(ZkvmHostError::MissingInput(input_path));
        }

        let proof_path = self
            .config
            .artifacts_dir
            .join(format!("{}.proof.json", request.job_id));
        let journal_path = self
            .config
            .artifacts_dir
            .join(format!("{}.journal.json", request.job_id));
        let manifest_path = self
            .config
            .artifacts_dir
            .join(format!("{}.manifest.json", request.job_id));

        let manifest = ProofManifest::new(
            &request.job_id,
            &self.config.backend,
            &program_path,
            &input_path,
        );

        let proof_blob = serde_json::json!({
            "job_id": request.job_id,
            "backend": self.config.backend,
            "proof": format!("0x{:x}", manifest.checksum),
        });

        let journal_blob = serde_json::json!({
            "job_id": request.job_id,
            "input": input_path,
            "program": program_path,
        });

        fs::write(&proof_path, serde_json::to_vec_pretty(&proof_blob)?).await?;
        fs::write(&journal_path, serde_json::to_vec_pretty(&journal_blob)?).await?;
        fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest)?).await?;

        info!(
            target: "afm_zkvm",
            job_id = %request.job_id,
            backend = %self.config.backend,
            "wrote stub proof artifacts"
        );

        Ok(ZkvmProofArtifacts {
            backend: self.config.backend.clone(),
            proof_path,
            journal_path,
            manifest_path,
        })
    }

    fn resolve_program(&self, candidate: &Path) -> PathBuf {
        if candidate.is_absolute() {
            candidate.to_path_buf()
        } else {
            self.config.program_dir.join(candidate)
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZkvmProofRequest {
    pub job_id: String,
    pub program: PathBuf,
    pub input: PathBuf,
}

impl ZkvmProofRequest {
    pub fn new(
        job_id: impl Into<String>,
        program: impl Into<PathBuf>,
        input: impl Into<PathBuf>,
    ) -> Self {
        Self {
            job_id: job_id.into(),
            program: program.into(),
            input: input.into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZkvmProofArtifacts {
    pub backend: ProverBackend,
    pub proof_path: PathBuf,
    pub journal_path: PathBuf,
    pub manifest_path: PathBuf,
}

#[derive(Debug, Error)]
pub enum ZkvmHostError {
    #[error("program not found at {0}")]
    MissingProgram(PathBuf),
    #[error("input not found at {0}")]
    MissingInput(PathBuf),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("serialization error: {0}")]
    Serialization(#[from] serde_json::Error),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ProofManifest {
    job_id: String,
    backend: ProverBackend,
    program: PathBuf,
    input: PathBuf,
    created_at: u64,
    checksum: u64,
}

impl ProofManifest {
    fn new(job_id: &str, backend: &ProverBackend, program: &Path, input: &Path) -> Self {
        let fingerprint = fingerprint(job_id, program, input);
        let created_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        Self {
            job_id: job_id.to_string(),
            backend: backend.clone(),
            program: program.to_path_buf(),
            input: input.to_path_buf(),
            created_at,
            checksum: fingerprint,
        }
    }
}

fn fingerprint(job_id: &str, program: &Path, input: &Path) -> u64 {
    let mut hasher = DefaultHasher::new();
    job_id.hash(&mut hasher);
    program.hash(&mut hasher);
    input.hash(&mut hasher);
    hasher.finish()
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn writes_artifacts() {
        let tmp = tempdir().unwrap();
        let program_dir = tmp.path().join("program");
        let artifacts_dir = tmp.path().join("artifacts");
        std::fs::create_dir_all(&program_dir).unwrap();
        let program_path = program_dir.join("demo.bin");
        let input_path = program_dir.join("demo.input");
        std::fs::write(&program_path, b"program").unwrap();
        std::fs::write(&input_path, b"input").unwrap();

        let host = ZkvmHost::new(ZkvmHostConfig {
            backend: ProverBackend::RiscZero,
            program_dir: program_dir.clone(),
            artifacts_dir: artifacts_dir.clone(),
        });

        let request = ZkvmProofRequest::new("job-123", "demo.bin", "demo.input");
        let artifacts = host.generate_proof(&request).await.unwrap();

        assert!(artifacts.proof_path.exists());
        assert!(artifacts.journal_path.exists());
        assert!(artifacts.manifest_path.exists());
    }
}
