use anyhow::{anyhow, Result};
use codec::{Decode, Encode};
use sp_core::crypto::AccountId32;
use sp_runtime::{
    generic::Era,
    traits::{IdentifyAccount, Verify},
    MultiSignature,
};
use std::str::FromStr;

/// A transaction to be submitted to the blockchain
#[derive(Debug, Clone, Encode, Decode)]
pub struct Transaction {
    /// The sender's account ID
    pub from: AccountId32,
    /// The recipient's account ID
    pub to: AccountId32,
    /// The amount to transfer (in the smallest unit)
    pub amount: u128,
    /// The transaction nonce
    pub nonce: u32,
    /// The transaction tip
    pub tip: u128,
    /// The transaction era
    pub era: Era,
    /// The transaction signature
    pub signature: Option<MultiSignature>,
}

impl Transaction {
    /// Create a new unsigned transaction
    pub fn new(
        from: AccountId32,
        to: AccountId32,
        amount: u128,
        nonce: u32,
        tip: u128,
        era: Era,
    ) -> Self {
        Self {
            from,
            to,
            amount,
            nonce,
            tip,
            era,
            signature: None,
        }
    }

    /// Sign the transaction with the given key pair
    pub fn sign(mut self, signer: &sp_core::sr25519::Pair) -> Result<Self> {
        // Create the signer payload
        let signer_payload = self.encode();
        
        // Sign the payload
        let signature = signer.sign(&signer_payload);
        
        // Convert to multi-signature
        self.signature = Some(MultiSignature::Sr25519(signature));
        
        Ok(self)
    }

    /// Verify the transaction signature
    pub fn verify(&self) -> bool {
        if let Some(signature) = &self.signature {
            // Create the signer payload (same as in sign)
            let mut unsigned = self.clone();
            unsigned.signature = None;
            let signer_payload = unsigned.encode();
            
            // Verify the signature
            match signature.verify(&*signer_payload, &self.from) {
                Ok(valid) => valid,
                Err(_) => false,
            }
        } else {
            false // No signature to verify
        }
    }
}

/// A transaction builder for creating transactions
pub struct TransactionBuilder {
    from: Option<AccountId32>,
    to: Option<AccountId32>,
    amount: u128,
    nonce: Option<u32>,
    tip: u128,
    era: Era,
}

impl Default for TransactionBuilder {
    fn default() -> Self {
        Self {
            from: None,
            to: None,
            amount: 0,
            nonce: None,
            tip: 0,
            era: Era::Immortal,
        }
    }
}

impl TransactionBuilder {
    /// Create a new transaction builder
    pub fn new() -> Self {
        Self::default()
    }

    /// Set the sender's account ID
    pub fn from(mut self, from: &str) -> Result<Self> {
        let account_id = AccountId32::from_str(from)
            .map_err(|_| anyhow!("Invalid account ID: {}", from))?;
        self.from = Some(account_id);
        Ok(self)
    }

    /// Set the recipient's account ID
    pub fn to(mut self, to: &str) -> Result<Self> {
        let account_id = AccountId32::from_str(to)
            .map_err(|_| anyhow!("Invalid account ID: {}", to))?;
        self.to = Some(account_id);
        Ok(self)
    }

    /// Set the amount to transfer
    pub fn amount(mut self, amount: u128) -> Self {
        self.amount = amount;
        self
    }

    /// Set the transaction nonce
    pub fn nonce(mut self, nonce: u32) -> Self {
        self.nonce = Some(nonce);
        self
    }

    /// Set the transaction tip
    pub fn tip(mut self, tip: u128) -> Self {
        self.tip = tip;
        self
    }

    /// Set the transaction era
    pub fn era(mut self, era: Era) -> Self {
        self.era = era;
        self
    }

    /// Build the transaction
    pub fn build(self) -> Result<Transaction> {
        let from = self.from.ok_or_else(|| anyhow!("Missing 'from' account"))?;
        let to = self.to.ok_or_else(|| anyhow!("Missing 'to' account"))?;
        let nonce = self.nonce.ok_or_else(|| anyhow!("Missing nonce"))?;

        Ok(Transaction {
            from,
            to,
            amount: self.amount,
            nonce,
            tip: self.tip,
            era: self.era,
            signature: None,
        })
    }
}

/// A transaction receipt
#[derive(Debug, Clone, Encode, Decode)]
pub struct TransactionReceipt {
    /// The transaction hash
    pub hash: [u8; 32],
    /// The block hash where the transaction was included
    pub block_hash: [u8; 32],
    /// The block number where the transaction was included
    pub block_number: u64,
    /// The transaction index in the block
    pub tx_index: u32,
    /// Whether the transaction was successful
    pub success: bool,
    /// Any error message if the transaction failed
    pub error: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use sp_core::{
        crypto::Pair,
        sr25519::Pair as Sr25519Pair,
    };
    use sp_keyring::AccountKeyring;

    #[test]
    fn test_transaction_builder() {
        let alice = AccountKeyring::Alice.to_account_id();
        let bob = AccountKeyring::Bob.to_account_id();
        
        let tx = TransactionBuilder::new()
            .from(&hex::encode(alice.as_ref()))
            .unwrap()
            .to(&hex::encode(bob.as_ref()))
            .unwrap()
            .amount(1000)
            .nonce(1)
            .tip(10)
            .build()
            .unwrap();
            
        assert_eq!(tx.from, alice);
        assert_eq!(tx.to, bob);
        assert_eq!(tx.amount, 1000);
        assert_eq!(tx.nonce, 1);
        assert_eq!(tx.tip, 10);
    }
    
    #[test]
    fn test_transaction_signing() {
        // Create a key pair
        let pair = Sr25519Pair::from_string("//Alice", None).unwrap();
        let public = pair.public();
        
        // Create a transaction
        let mut tx = Transaction {
            from: public.into(),
            to: AccountKeyring::Bob.to_account_id(),
            amount: 1000,
            nonce: 1,
            tip: 10,
            era: Era::Immortal,
            signature: None,
        };
        
        // Sign the transaction
        let signed_tx = tx.clone().sign(&pair).unwrap();
        
        // Verify the signature
        assert!(signed_tx.verify());
        
        // Tamper with the transaction and verify it fails
        let mut tampered_tx = signed_tx.clone();
        tampered_tx.amount = 2000;
        assert!(!tampered_tx.verify());
    }
}
