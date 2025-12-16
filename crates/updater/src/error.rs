use std::path::PathBuf;

/// Convenient result alias for updater operations.
pub type Result<T> = std::result::Result<T, UpdaterError>;

/// Errors that can occur while performing an update.
#[derive(thiserror::Error, Debug)]
pub enum UpdaterError {
    /// Network request to the IPFS gateway failed.
    #[error("IPFS fetch failed: {0}")]
    Fetch(#[from] reqwest::Error),
    /// The manifest could not be decoded from JSON.
    #[error("manifest decoding failed: {0}")]
    ManifestDecode(#[from] serde_json::Error),
    /// The manifest signature was invalid.
    #[error("manifest signature invalid")]
    ManifestSignatureInvalid,
    /// A CID contained in the manifest was invalid.
    #[error("invalid cid in manifest: {0}")]
    InvalidCid(String),
    /// The downloaded artefact hash did not match the manifest.
    #[error("binary integrity check failed (expected {expected}, got {actual})")]
    IntegrityMismatch {
        /// Expected SHA-256 digest.
        expected: String,
        /// Actual SHA-256 digest.
        actual: String,
    },
    /// Failed to perform an I/O operation.
    #[error("filesystem operation failed: {0}")]
    Io(#[from] std::io::Error),
    /// Failed to parse or compare versions.
    #[error("version error: {0}")]
    Version(#[from] semver::Error),
    /// Attempted to apply an update to a non-absolute binary path.
    #[error("binary path must be absolute: {0}")]
    NonAbsolutePath(PathBuf),
    /// Attempts to perform an operation on an unsupported platform.
    #[error("unsupported operation on this platform: {0}")]
    Unsupported(&'static str),
    /// Generic error.
    #[error("{0}")]
    Other(String),
}

impl UpdaterError {
    /// Helper for wrapping validation failures.
    pub fn validation(msg: impl Into<String>) -> Self {
        UpdaterError::Other(msg.into())
    }
}
