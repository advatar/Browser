use crate::error::{Result, UpdaterError};
use base64::{engine::general_purpose, Engine as _};
use cid::Cid;
use ed25519_dalek::Signature;
use serde::{Deserialize, Serialize};
use std::convert::TryInto;

/// The data covered by the release signature.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SignedManifest {
    /// Semantic version string for the release.
    pub version: String,
    /// CID pointing to the release artefact (binary or archive).
    pub binary_cid: String,
    /// Expected SHA-256 digest (hex encoded, lowercase) of the artefact.
    pub binary_sha256: String,
    /// Expected size (in bytes) of the artefact to catch truncated downloads.
    pub binary_size: u64,
    /// Optional path within the DAG (e.g. when the release artefact is inside a tarball CID).
    #[serde(default)]
    pub binary_path: Option<String>,
    /// Unix timestamp (seconds) when the manifest was produced.
    pub created_at: u64,
    /// Optional CID to release notes or metadata.
    #[serde(default)]
    pub release_notes_cid: Option<String>,
}

impl SignedManifest {
    /// Convert the binary CID string into a [`Cid`].
    pub fn binary_cid(&self) -> Result<Cid> {
        Cid::try_from(self.binary_cid.as_str())
            .map_err(|_| UpdaterError::InvalidCid(self.binary_cid.clone()))
    }

    /// Convert the optional release-notes CID into a [`Cid`].
    pub fn release_notes_cid(&self) -> Result<Option<Cid>> {
        if let Some(cid) = &self.release_notes_cid {
            let parsed =
                Cid::try_from(cid.as_str()).map_err(|_| UpdaterError::InvalidCid(cid.clone()))?;
            Ok(Some(parsed))
        } else {
            Ok(None)
        }
    }

    /// Parse the semantic version contained in the manifest.
    pub fn parsed_version(&self) -> Result<semver::Version> {
        Ok(semver::Version::parse(&self.version)?)
    }

    /// Optional path component within the referenced CID.
    pub fn binary_path(&self) -> Option<&str> {
        self.binary_path.as_deref()
    }
}

/// Signed release manifest.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct UpdateManifest {
    #[serde(flatten)]
    pub signed: SignedManifest,
    /// Base64 encoded Ed25519 signature over the canonical JSON of [`SignedManifest`].
    pub signature: String,
}

impl UpdateManifest {
    /// Render the signed payload to canonical JSON bytes that were signed.
    pub fn signing_bytes(&self) -> Result<Vec<u8>> {
        Ok(serde_json::to_vec(&self.signed)?)
    }

    /// Parse the Ed25519 signature from the manifest.
    pub fn parsed_signature(&self) -> Result<Signature> {
        let raw = general_purpose::STANDARD
            .decode(self.signature.as_bytes())
            .map_err(|err| {
                UpdaterError::validation(format!("malformed base64 signature: {err}"))
            })?;

        let array: [u8; 64] = raw
            .try_into()
            .map_err(|_| UpdaterError::validation("signature must be 64 bytes"))?;
        Ok(Signature::from_bytes(&array))
    }

    /// Convenience accessor to the parsed version.
    pub fn version(&self) -> Result<semver::Version> {
        self.signed.parsed_version()
    }
}
