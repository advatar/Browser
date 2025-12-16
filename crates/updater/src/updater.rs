use crate::{
    error::{Result, UpdaterError},
    fetcher::IpfsFetcher,
    manifest::{SignedManifest, UpdateManifest},
};
use cid::Cid;
use ed25519_dalek::{Verifier, VerifyingKey};
use sha2::{Digest, Sha256};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use tempfile::{NamedTempFile, PathPersistError};
use tokio::task;

/// Updater capable of retrieving and applying signed releases from IPFS.
pub struct Updater<F> {
    fetcher: F,
    verifying_key: VerifyingKey,
}

impl<F> Updater<F>
where
    F: IpfsFetcher,
{
    /// Create a new updater with the given fetcher and verifying key.
    pub fn new(fetcher: F, verifying_key: VerifyingKey) -> Self {
        Self {
            fetcher,
            verifying_key,
        }
    }

    /// Retrieve and verify a manifest from IPFS.
    pub async fn fetch_manifest(&self, manifest_cid: &Cid) -> Result<UpdateManifest> {
        let bytes = self.fetcher.fetch_bytes(manifest_cid, None).await?;
        let manifest: UpdateManifest = serde_json::from_slice(&bytes)?;
        self.verify_manifest(&manifest)?;
        Ok(manifest)
    }

    fn verify_manifest(&self, manifest: &UpdateManifest) -> Result<()> {
        let signature = manifest.parsed_signature()?;
        let payload = manifest.signing_bytes()?;
        self.verifying_key
            .verify(&payload, &signature)
            .map_err(|_| UpdaterError::ManifestSignatureInvalid)?;
        Ok(())
    }

    /// Determine whether a newer version is available compared to `current_version`.
    pub async fn check_for_update(
        &self,
        current_version: &semver::Version,
        manifest_cid: &Cid,
    ) -> Result<UpdateStatus> {
        let manifest = self.fetch_manifest(manifest_cid).await?;
        let manifest_version = manifest.version()?;

        if manifest_version > *current_version {
            Ok(UpdateStatus::Available(AvailableUpdate { manifest }))
        } else {
            Ok(UpdateStatus::UpToDate)
        }
    }

    /// Convenience wrapper when the current version is provided as a string.
    pub async fn check_for_update_str(
        &self,
        current_version: &str,
        manifest_cid: &Cid,
    ) -> Result<UpdateStatus> {
        let parsed = semver::Version::parse(current_version)?;
        self.check_for_update(&parsed, manifest_cid).await
    }

    /// Download and atomically apply the given update to `binary_path`.
    pub async fn download_and_apply(
        &self,
        update: &AvailableUpdate,
        binary_path: &Path,
    ) -> Result<DownloadOutcome> {
        if !binary_path.is_absolute() {
            return Err(UpdaterError::NonAbsolutePath(binary_path.to_path_buf()));
        }

        let SignedManifest {
            binary_sha256,
            binary_size,
            ..
        } = &update.manifest.signed;
        let binary_cid = update.manifest.signed.binary_cid()?;
        let binary_path_component = update.manifest.signed.binary_path();

        let bytes = self
            .fetcher
            .fetch_bytes(&binary_cid, binary_path_component)
            .await?;

        if bytes.len() as u64 != *binary_size {
            return Err(UpdaterError::IntegrityMismatch {
                expected: format!("{binary_size} bytes"),
                actual: format!("{} bytes", bytes.len()),
            });
        }

        let hash = Sha256::digest(&bytes);
        let actual_sha = hex::encode(hash);
        let expected_sha = binary_sha256.to_ascii_lowercase();
        if actual_sha != expected_sha {
            return Err(UpdaterError::IntegrityMismatch {
                expected: expected_sha,
                actual: actual_sha,
            });
        }

        let version = update.manifest.version()?;
        let target_path = binary_path.to_path_buf();
        let writer_bytes: Vec<u8> = bytes;

        // Perform blocking filesystem work in a dedicated thread.
        let outcome = task::spawn_blocking(move || {
            apply_payload(writer_bytes, &target_path).map(|backup| DownloadOutcome {
                new_version: version,
                target_path,
                backup_path: backup,
            })
        })
        .await
        .map_err(|err| UpdaterError::Other(format!("task join error: {err}")))??;

        Ok(outcome)
    }
}

/// Apply the downloaded payload to the target path atomically.
fn apply_payload(bytes: Vec<u8>, target_path: &Path) -> Result<Option<PathBuf>> {
    let parent = target_path
        .parent()
        .ok_or_else(|| UpdaterError::validation("target path must have a parent directory"))?;

    if !parent.exists() {
        fs::create_dir_all(parent)?;
    }

    let mut temp = NamedTempFile::new_in(parent)?;
    temp.write_all(&bytes)?;
    temp.flush()?;
    temp.as_file().sync_all()?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = temp.as_file().metadata()?.permissions();
        // Ensure binary is executable by default.
        perms.set_mode(0o755);
        temp.as_file().set_permissions(perms)?;
    }

    let temp_path = temp.into_temp_path();
    #[cfg(unix)]
    {
        temp_path.persist(&target_path).map_err(map_persist_error)?;
        return Ok(None);
    }

    #[cfg(not(unix))]
    {
        let interim = target_path.with_extension("new");
        temp_path.persist(&interim).map_err(map_persist_error)?;

        let backup = if target_path.exists() {
            let mut counter = 0usize;
            let mut candidate = target_path.with_extension("old");
            while candidate.exists() {
                counter += 1;
                candidate = target_path.with_extension(format!("old{counter}"));
            }
            fs::rename(&target_path, &candidate)?;
            Some(candidate)
        } else {
            None
        };

        if let Err(err) = fs::rename(&interim, target_path) {
            // Attempt rollback if rename fails.
            if let Some(ref backup_path) = backup {
                let _ = fs::rename(backup_path, target_path);
            }
            return Err(UpdaterError::Io(err));
        }

        // Attempt to remove backup if possible; otherwise keep the path for the caller.
        if let Some(ref backup_path) = backup {
            if let Err(err) = fs::remove_file(backup_path) {
                tracing::warn!("failed to remove old binary {:?}: {}", backup_path, err);
                return Ok(Some(backup_path.clone()));
            }
        }

        return Ok(None);
    }
}

fn map_persist_error(err: PathPersistError) -> UpdaterError {
    UpdaterError::Io(err.error)
}

/// Result of checking for updates.
pub enum UpdateStatus {
    /// There is no newer version available.
    UpToDate,
    /// A newer version is available.
    Available(AvailableUpdate),
}

/// Details about an available update.
#[derive(Clone)]
pub struct AvailableUpdate {
    manifest: UpdateManifest,
}

impl AvailableUpdate {
    /// Access the manifest.
    pub fn manifest(&self) -> &UpdateManifest {
        &self.manifest
    }

    /// Convenience accessor to the version.
    pub fn version(&self) -> Result<semver::Version> {
        self.manifest.version()
    }

    /// CID of the binary artefact.
    pub fn binary_cid(&self) -> Result<Cid> {
        self.manifest.signed.binary_cid()
    }

    /// Optional path inside the UnixFS object.
    pub fn binary_path(&self) -> Option<&str> {
        self.manifest.signed.binary_path()
    }

    /// Expected size of the binary.
    pub fn binary_size(&self) -> u64 {
        self.manifest.signed.binary_size
    }

    /// Expected SHA-256 digest.
    pub fn binary_sha256(&self) -> &str {
        &self.manifest.signed.binary_sha256
    }
}

impl From<UpdateManifest> for AvailableUpdate {
    fn from(manifest: UpdateManifest) -> Self {
        AvailableUpdate { manifest }
    }
}

/// Result of applying an update.
pub struct DownloadOutcome {
    /// Version that was applied.
    pub new_version: semver::Version,
    /// Final location of the binary.
    pub target_path: PathBuf,
    /// Optional leftover backup path (Windows rollback).
    pub backup_path: Option<PathBuf>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::{engine::general_purpose, Engine as _};
    use ed25519_dalek::{Signer, SigningKey};
    use std::collections::HashMap;
    use tempfile::tempdir;

    struct MockFetcher {
        entries: HashMap<(String, Option<String>), Vec<u8>>,
    }

    impl MockFetcher {
        fn new() -> Self {
            Self {
                entries: HashMap::new(),
            }
        }

        fn insert(&mut self, cid: &Cid, path: Option<&str>, data: Vec<u8>) {
            let key = (cid.to_string(), path.map(|p| p.to_string()));
            self.entries.insert(key, data);
        }
    }

    #[async_trait::async_trait]
    impl IpfsFetcher for MockFetcher {
        async fn fetch_bytes(&self, cid: &Cid, path: Option<&str>) -> Result<Vec<u8>> {
            let key = (cid.to_string(), path.map(|p| p.to_string()));
            self.entries
                .get(&key)
                .cloned()
                .ok_or_else(|| UpdaterError::validation("unknown cid in mock fetcher"))
        }
    }

    #[tokio::test]
    async fn end_to_end_update_applies_binary() {
        let binary_bytes = b"browser-binary".to_vec();
        let binary_cid =
            Cid::try_from("bafkreigh2akiscaildcqabsyg3dfr6chu3fgpregiymsck7e7aqa4s52zy")
                .expect("valid cid");
        let binary_sha = hex::encode(Sha256::digest(&binary_bytes));

        let signed = SignedManifest {
            version: "1.0.1".into(),
            binary_cid: binary_cid.to_string(),
            binary_sha256: binary_sha,
            binary_size: binary_bytes.len() as u64,
            binary_path: None,
            created_at: 1_700_000_000,
            release_notes_cid: None,
        };

        let signing_key = SigningKey::from_bytes(&[7u8; 32]);
        let verifying_key = signing_key.verifying_key();

        let payload = serde_json::to_vec(&signed).unwrap();
        let signature = signing_key.sign(&payload);
        let manifest = UpdateManifest {
            signed,
            signature: general_purpose::STANDARD.encode(signature.to_bytes()),
        };

        let manifest_bytes = serde_json::to_vec(&manifest).expect("manifest serialises");
        let manifest_cid =
            Cid::try_from("bafybeigdyrztv6xg4ga33z7smnq4e6g4boomolvqqpfgbzx6p5u4r3q7hu")
                .expect("valid manifest cid");

        let mut fetcher = MockFetcher::new();
        fetcher.insert(&manifest_cid, None, manifest_bytes);
        fetcher.insert(&binary_cid, None, binary_bytes.clone());

        let updater = Updater::new(fetcher, verifying_key);

        let status = updater
            .check_for_update_str("1.0.0", &manifest_cid)
            .await
            .expect("check_for_update succeeds");

        let update = match status {
            UpdateStatus::Available(update) => update,
            UpdateStatus::UpToDate => panic!("expected update to be available"),
        };

        let temp_dir = tempdir().unwrap();
        let binary_path = temp_dir.path().join("browser");

        let outcome = updater
            .download_and_apply(&update, &binary_path)
            .await
            .expect("download succeeds");

        assert_eq!(
            outcome.new_version,
            semver::Version::parse("1.0.1").unwrap()
        );
        assert_eq!(outcome.target_path, binary_path);
        assert!(outcome.backup_path.is_none());

        let written = fs::read(&binary_path).unwrap();
        assert_eq!(written, binary_bytes);
    }
}
