use anyhow::{anyhow, Result};
use sp_core::{
    crypto::{Derive, Ss58Codec, Ss58AddressFormatRegistry},
    ed25519, sr25519, ecdsa, Pair as PairT,
};
use std::{
    fmt,
    str::FromStr,
    sync::Arc,
};
use thiserror::Error;

/// Supported key types for the wallet
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyType {
    Sr25519,
    Ed25519,
    Ecdsa,
}

impl fmt::Display for KeyType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            KeyType::Sr25519 => write!(f, "sr25519"),
            KeyType::Ed25519 => write!(f, "ed25519"),
            KeyType::Ecdsa => write!(f, "ecdsa"),
        }
    }
}

impl FromStr for KeyType {
    type Err = anyhow::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "sr25519" => Ok(KeyType::Sr25519),
            "ed25519" => Ok(KeyType::Ed25519),
            "ecdsa" => Ok(KeyType::Ecdsa),
            _ => Err(anyhow!("Unsupported key type: {}", s)),
        }
    }
}

/// Errors that can occur when working with the wallet
#[derive(Error, Debug)]
pub enum WalletError {
    #[error("Invalid mnemonic phrase: {0}")]
    InvalidMnemonic(String),
    #[error("Invalid private key: {0}")]
    InvalidPrivateKey(String),
    #[error("Invalid public key: {0}")]
    InvalidPublicKey(String),
    #[error("Key generation failed: {0}")]
    KeyGenerationFailed(String),
    #[error("Signature verification failed")]
    SignatureVerificationFailed,
    #[error("Unsupported key type: {0}")]
    UnsupportedKeyType(String),
}

/// A key pair in the wallet
#[derive(Clone)]
pub enum KeyPair {
    Sr25519(sr25519::Pair),
    Ed25519(ed25519::Pair),
    Ecdsa(ecdsa::Pair),
}

impl KeyPair {
    /// Create a new key pair from a seed phrase
    pub fn from_phrase(phrase: &str, password: Option<&str>) -> Result<Self> {
        let pair = sr25519::Pair::from_phrase(phrase, password)
            .map_err(|e| WalletError::InvalidMnemonic(e.to_string()))?
            .0;
        Ok(KeyPair::Sr25519(pair))
    }

    /// Create a new key pair from a seed
    pub fn from_seed(seed: &[u8], key_type: KeyType) -> Result<Self> {
        match key_type {
            KeyType::Sr25519 => {
                let pair = sr25519::Pair::from_seed_slice(seed)
                    .map_err(|e| WalletError::KeyGenerationFailed(e.to_string()))?;
                Ok(KeyPair::Sr25519(pair))
            }
            KeyType::Ed25519 => {
                let pair = ed25519::Pair::from_seed_slice(seed)
                    .map_err(|e| WalletError::KeyGenerationFailed(e.to_string()))?;
                Ok(KeyPair::Ed25519(pair))
            }
            KeyType::Ecdsa => {
                let pair = ecdsa::Pair::from_seed_slice(seed)
                    .map_err(|e| WalletError::KeyGenerationFailed(e.to_string()))?;
                Ok(KeyPair::Ecdsa(pair))
            }
        }
    }

    /// Get the public key as bytes
    pub fn public_key(&self) -> Vec<u8> {
        match self {
            KeyPair::Sr25519(pair) => pair.public().0.to_vec(),
            KeyPair::Ed25519(pair) => pair.public().0.to_vec(),
            KeyPair::Ecdsa(pair) => pair.public().0.to_vec(),
        }
    }

    /// Get the SS58-encoded address
    pub fn to_ss58(&self) -> String {
        match self {
            KeyPair::Sr25519(pair) => pair.public().to_ss58check(),
            KeyPair::Ed25519(pair) => pair.public().to_ss58check(),
            KeyPair::Ecdsa(pair) => pair.public().to_ss58check(),
        }
    }

    /// Sign a message with this key pair
    pub fn sign(&self, message: &[u8]) -> Vec<u8> {
        match self {
            KeyPair::Sr25519(pair) => pair.sign(message).0.to_vec(),
            KeyPair::Ed25519(pair) => pair.sign(message).0.to_vec(),
            KeyPair::Ecdsa(pair) => pair.sign(message).0.to_vec(),
        }
    }

    /// Verify a signature for a message
    pub fn verify(&self, message: &[u8], signature: &[u8]) -> bool {
        match self {
            KeyPair::Sr25519(pair) => {
                let sig = match sr25519::Signature::from_slice(signature) {
                    Ok(sig) => sig,
                    Err(_) => return false,
                };
                pair.verify(message, &sig)
            }
            KeyPair::Ed25519(pair) => {
                let sig = match ed25519::Signature::from_slice(signature) {
                    Ok(sig) => sig,
                    Err(_) => return false,
                };
                pair.verify(message, &sig)
            }
            KeyPair::Ecdsa(pair) => {
                let sig = match ecdsa::Signature::from_slice(signature) {
                    Ok(sig) => sig,
                    Err(_) => return false,
                };
                pair.verify(message, &sig)
            }
        }
    }
}

/// A wallet that can hold multiple key pairs
pub struct Wallet {
    keys: std::collections::HashMap<String, KeyPair>,
    default_key: Option<String>,
}

impl Default for Wallet {
    fn default() -> Self {
        Self::new()
    }
}

impl Wallet {
    /// Create a new empty wallet
    pub fn new() -> Self {
        Self {
            keys: Default::default(),
            default_key: None,
        }
    }

    /// Add a key pair to the wallet
    pub fn add_key(&mut self, name: &str, key_pair: KeyPair) -> Result<()> {
        if self.keys.contains_key(name) {
            return Err(anyhow!("Key with name '{}' already exists", name));
        }
        
        if self.default_key.is_none() {
            self.default_key = Some(name.to_string());
        }
        
        self.keys.insert(name.to_string(), key_pair);
        Ok(())
    }

    /// Get a key pair by name
    pub fn get_key(&self, name: &str) -> Option<&KeyPair> {
        self.keys.get(name)
    }

    /// Get the default key pair
    pub fn default_key(&self) -> Option<&KeyPair> {
        self.default_key
            .as_ref()
            .and_then(|name| self.keys.get(name))
    }

    /// Set the default key pair
    pub fn set_default_key(&mut self, name: &str) -> Result<()> {
        if !self.keys.contains_key(name) {
            return Err(anyhow!("Key '{}' not found in wallet", name));
        }
        self.default_key = Some(name.to_string());
        Ok(())
    }

    /// List all keys in the wallet
    pub fn list_keys(&self) -> Vec<(&str, String)> {
        self.keys
            .iter()
            .map(|(name, key)| (name.as_str(), key.to_ss58()))
            .collect()
    }

    /// Remove a key pair from the wallet
    pub fn remove_key(&mut self, name: &str) -> Option<KeyPair> {
        let removed = self.keys.remove(name);
        
        // Update default key if needed
        if let Some(ref default) = self.default_key {
            if default == name {
                self.default_key = self.keys.keys().next().cloned();
            }
        }
        
        removed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sp_core::crypto::DEV_PHRASE;

    #[test]
    fn test_key_pair_from_phrase() {
        let key_pair = KeyPair::from_phrase(DEV_PHRASE, None).unwrap();
        let public_key = key_pair.public_key();
        assert!(!public_key.is_empty());
        
        let ss58 = key_pair.to_ss58();
        assert!(!ss58.is_empty());
    }

    #[test]
    fn test_key_pair_sign_verify() {
        let key_pair = KeyPair::from_phrase(DEV_PHRASE, None).unwrap();
        let message = b"test message";
        
        let signature = key_pair.sign(message);
        assert!(key_pair.verify(message, &signature));
        
        // Test with wrong message
        assert!(!key_pair.verify(b"wrong message", &signature));
    }

    #[test]
    fn test_wallet_operations() {
        let mut wallet = Wallet::new();
        
        // Add a key
        let key_pair = KeyPair::from_phrase(DEV_PHRASE, None).unwrap();
        wallet.add_key("alice", key_pair).unwrap();
        
        // Check default key is set
        assert!(wallet.default_key().is_some());
        
        // Add another key and set as default
        let key_pair2 = KeyPair::from_seed(&[1; 32], KeyType::Sr25519).unwrap();
        wallet.add_key("bob", key_pair2).unwrap();
        wallet.set_default_key("bob").unwrap();
        
        // List keys
        let keys = wallet.list_keys();
        assert_eq!(keys.len(), 2);
        
        // Remove a key
        wallet.remove_key("alice");
        assert_eq!(wallet.list_keys().len(), 1);
    }
}
