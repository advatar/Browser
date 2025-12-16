use serde::Serialize;
use thiserror::Error;

#[derive(Debug, Serialize, Clone)]
pub struct CreditSnapshot {
    pub balance_tokens: i64,
    pub total_spent_tokens: u64,
}

#[derive(Debug)]
pub struct CreditAccount {
    balance_tokens: i64,
    total_spent_tokens: u64,
}

impl CreditAccount {
    pub fn new(initial_balance: i64) -> Self {
        Self {
            balance_tokens: initial_balance,
            total_spent_tokens: 0,
        }
    }

    pub fn snapshot(&self) -> CreditSnapshot {
        CreditSnapshot {
            balance_tokens: self.balance_tokens,
            total_spent_tokens: self.total_spent_tokens,
        }
    }

    pub fn charge(&mut self, tokens: u32) -> Result<(), CreditError> {
        let tokens = tokens as i64;
        self.balance_tokens -= tokens;
        self.total_spent_tokens = self.total_spent_tokens.saturating_add(tokens as u64);
        if self.balance_tokens < 0 {
            Err(CreditError::InsufficientBalance {
                deficit: (-self.balance_tokens) as u64,
            })
        } else {
            Ok(())
        }
    }

    pub fn top_up(&mut self, tokens: u32) {
        self.balance_tokens += tokens as i64;
    }

    pub fn balance(&self) -> i64 {
        self.balance_tokens
    }
}

#[derive(Debug, Error)]
pub enum CreditError {
    #[error("insufficient credits (deficit {deficit} tokens)")]
    InsufficientBalance { deficit: u64 },
}
