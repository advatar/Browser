use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Wallet UI state and management
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WalletUIState {
    pub is_connected: bool,
    pub current_account: Option<AccountInfo>,
    pub accounts: Vec<AccountInfo>,
    pub networks: Vec<NetworkInfo>,
    pub current_network: Option<String>,
    pub transactions: Vec<TransactionInfo>,
    pub is_loading: bool,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AccountInfo {
    pub address: String,
    pub name: String,
    pub balance: String,
    pub network: String,
    pub account_type: AccountType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AccountType {
    Software,
    Hardware,
    WatchOnly,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkInfo {
    pub id: String,
    pub name: String,
    pub rpc_url: String,
    pub chain_id: u64,
    pub currency_symbol: String,
    pub block_explorer_url: Option<String>,
    pub is_testnet: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionInfo {
    pub hash: String,
    pub from: String,
    pub to: String,
    pub value: String,
    pub gas_used: Option<String>,
    pub gas_price: Option<String>,
    pub timestamp: u64,
    pub status: TransactionStatus,
    pub block_number: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum TransactionStatus {
    Pending,
    Confirmed,
    Failed,
}

impl Default for WalletUIState {
    fn default() -> Self {
        Self {
            is_connected: false,
            current_account: None,
            accounts: Vec::new(),
            networks: Self::default_networks(),
            current_network: Some("ethereum-mainnet".to_string()),
            transactions: Vec::new(),
            is_loading: false,
            error_message: None,
        }
    }
}

impl WalletUIState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Get default networks
    fn default_networks() -> Vec<NetworkInfo> {
        vec![
            NetworkInfo {
                id: "ethereum-mainnet".to_string(),
                name: "Ethereum Mainnet".to_string(),
                rpc_url: "https://cloudflare-eth.com".to_string(),
                chain_id: 1,
                currency_symbol: "ETH".to_string(),
                block_explorer_url: Some("https://etherscan.io".to_string()),
                is_testnet: false,
            },
            NetworkInfo {
                id: "ethereum-goerli".to_string(),
                name: "Ethereum Goerli".to_string(),
                rpc_url: "https://goerli.infura.io/v3/YOUR_PROJECT_ID".to_string(),
                chain_id: 5,
                currency_symbol: "ETH".to_string(),
                block_explorer_url: Some("https://goerli.etherscan.io".to_string()),
                is_testnet: true,
            },
            NetworkInfo {
                id: "polygon-mainnet".to_string(),
                name: "Polygon Mainnet".to_string(),
                rpc_url: "https://polygon-rpc.com".to_string(),
                chain_id: 137,
                currency_symbol: "MATIC".to_string(),
                block_explorer_url: Some("https://polygonscan.com".to_string()),
                is_testnet: false,
            },
            NetworkInfo {
                id: "bitcoin-mainnet".to_string(),
                name: "Bitcoin Mainnet".to_string(),
                rpc_url: "https://bitcoin.example.com".to_string(),
                chain_id: 0, // Bitcoin doesn't use chain IDs
                currency_symbol: "BTC".to_string(),
                block_explorer_url: Some("https://blockstream.info".to_string()),
                is_testnet: false,
            },
        ]
    }

    /// Connect wallet
    pub fn connect_wallet(&mut self, account: AccountInfo) -> Result<()> {
        self.current_account = Some(account.clone());
        self.accounts.push(account);
        self.is_connected = true;
        self.error_message = None;
        Ok(())
    }

    /// Disconnect wallet
    pub fn disconnect_wallet(&mut self) -> Result<()> {
        self.current_account = None;
        self.accounts.clear();
        self.transactions.clear();
        self.is_connected = false;
        self.error_message = None;
        Ok(())
    }

    /// Switch account
    pub fn switch_account(&mut self, address: &str) -> Result<()> {
        if let Some(account) = self.accounts.iter().find(|a| a.address == address) {
            self.current_account = Some(account.clone());
            Ok(())
        } else {
            Err(anyhow::anyhow!("Account not found: {}", address))
        }
    }

    /// Switch network
    pub fn switch_network(&mut self, network_id: &str) -> Result<()> {
        if self.networks.iter().any(|n| n.id == network_id) {
            self.current_network = Some(network_id.to_string());
            // Clear transactions when switching networks
            self.transactions.clear();
            Ok(())
        } else {
            Err(anyhow::anyhow!("Network not found: {}", network_id))
        }
    }

    /// Add transaction
    pub fn add_transaction(&mut self, transaction: TransactionInfo) {
        // Add to the beginning of the list (most recent first)
        self.transactions.insert(0, transaction);
        
        // Keep only the last 100 transactions
        if self.transactions.len() > 100 {
            self.transactions.truncate(100);
        }
    }

    /// Update transaction status
    pub fn update_transaction_status(&mut self, hash: &str, status: TransactionStatus, block_number: Option<u64>) {
        if let Some(tx) = self.transactions.iter_mut().find(|t| t.hash == hash) {
            tx.status = status;
            tx.block_number = block_number;
        }
    }

    /// Get current network info
    pub fn get_current_network(&self) -> Option<&NetworkInfo> {
        if let Some(network_id) = &self.current_network {
            self.networks.iter().find(|n| &n.id == network_id)
        } else {
            None
        }
    }

    /// Set loading state
    pub fn set_loading(&mut self, loading: bool) {
        self.is_loading = loading;
    }

    /// Set error message
    pub fn set_error(&mut self, error: Option<String>) {
        self.error_message = error;
    }

    /// Clear error
    pub fn clear_error(&mut self) {
        self.error_message = None;
    }

    /// Get formatted balance
    pub fn get_formatted_balance(&self) -> String {
        if let Some(account) = &self.current_account {
            if let Some(network) = self.get_current_network() {
                format!("{} {}", account.balance, network.currency_symbol)
            } else {
                account.balance.clone()
            }
        } else {
            "0.0".to_string()
        }
    }

    /// Get pending transactions count
    pub fn get_pending_transactions_count(&self) -> usize {
        self.transactions
            .iter()
            .filter(|tx| matches!(tx.status, TransactionStatus::Pending))
            .count()
    }

    /// Get recent transactions (last 10)
    pub fn get_recent_transactions(&self) -> Vec<&TransactionInfo> {
        self.transactions.iter().take(10).collect()
    }
}

/// Wallet UI component manager
#[derive(Debug)]
pub struct WalletUIManager {
    state: WalletUIState,
}

impl WalletUIManager {
    pub fn new() -> Self {
        Self {
            state: WalletUIState::new(),
        }
    }

    /// Get current state
    pub fn get_state(&self) -> &WalletUIState {
        &self.state
    }

    /// Get mutable state
    pub fn get_state_mut(&mut self) -> &mut WalletUIState {
        &mut self.state
    }

    /// Generate wallet UI HTML
    pub fn generate_wallet_html(&self) -> String {
        if self.state.is_connected {
            self.generate_connected_wallet_html()
        } else {
            self.generate_disconnected_wallet_html()
        }
    }

    /// Generate HTML for connected wallet
    fn generate_connected_wallet_html(&self) -> String {
        let account = self.state.current_account.as_ref().unwrap();
        let network = self.state.get_current_network().unwrap();
        let balance = self.state.get_formatted_balance();
        let pending_count = self.state.get_pending_transactions_count();

        format!(
            r#"
            <div class="wallet-connected">
                <div class="wallet-header">
                    <div class="account-info">
                        <div class="account-address">{}</div>
                        <div class="account-balance">{}</div>
                        <div class="network-info">{}</div>
                    </div>
                    <div class="wallet-actions">
                        <button onclick="sendTransaction()">Send</button>
                        <button onclick="receiveTokens()">Receive</button>
                        <button onclick="disconnectWallet()">Disconnect</button>
                    </div>
                </div>
                <div class="transaction-summary">
                    <div class="pending-transactions">
                        Pending: {}
                    </div>
                </div>
                <div class="recent-transactions">
                    <h4>Recent Transactions</h4>
                    {}
                </div>
            </div>
            "#,
            self.format_address(&account.address),
            balance,
            network.name,
            pending_count,
            self.generate_transactions_html()
        )
    }

    /// Generate HTML for disconnected wallet
    fn generate_disconnected_wallet_html(&self) -> String {
        r#"
        <div class="wallet-disconnected">
            <div class="wallet-prompt">
                <h3>Connect Your Wallet</h3>
                <p>Connect your wallet to interact with decentralized applications</p>
                <div class="wallet-options">
                    <button onclick="connectSoftwareWallet()">Software Wallet</button>
                    <button onclick="connectHardwareWallet()">Hardware Wallet</button>
                    <button onclick="importWallet()">Import Wallet</button>
                </div>
            </div>
        </div>
        "#.to_string()
    }

    /// Generate transactions HTML
    fn generate_transactions_html(&self) -> String {
        let recent_transactions = self.state.get_recent_transactions();
        
        if recent_transactions.is_empty() {
            return "<div class=\"no-transactions\">No recent transactions</div>".to_string();
        }

        let mut html = String::new();
        for tx in recent_transactions {
            let status_class = match tx.status {
                TransactionStatus::Pending => "pending",
                TransactionStatus::Confirmed => "confirmed",
                TransactionStatus::Failed => "failed",
            };

            html.push_str(&format!(
                r#"
                <div class="transaction-item {}">
                    <div class="tx-hash">{}</div>
                    <div class="tx-details">
                        <div class="tx-from-to">{} → {}</div>
                        <div class="tx-value">{}</div>
                    </div>
                    <div class="tx-status">{:?}</div>
                </div>
                "#,
                status_class,
                self.format_hash(&tx.hash),
                self.format_address(&tx.from),
                self.format_address(&tx.to),
                tx.value,
                tx.status
            ));
        }

        html
    }

    /// Format address for display
    fn format_address(&self, address: &str) -> String {
        if address.len() > 10 {
            format!("{}...{}", &address[0..6], &address[address.len()-4..])
        } else {
            address.to_string()
        }
    }

    /// Format hash for display
    fn format_hash(&self, hash: &str) -> String {
        if hash.len() > 16 {
            format!("{}...{}", &hash[0..8], &hash[hash.len()-8..])
        } else {
            hash.to_string()
        }
    }

    /// Generate wallet CSS
    pub fn generate_wallet_css(&self) -> String {
        r#"
        .wallet-connected, .wallet-disconnected {
            padding: 16px;
            background: #f8f9fa;
            border-radius: 8px;
            margin: 8px;
        }

        .wallet-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 16px;
        }

        .account-info {
            flex: 1;
        }

        .account-address {
            font-family: monospace;
            font-size: 14px;
            color: #666;
        }

        .account-balance {
            font-size: 18px;
            font-weight: bold;
            color: #333;
            margin: 4px 0;
        }

        .network-info {
            font-size: 12px;
            color: #888;
        }

        .wallet-actions {
            display: flex;
            gap: 8px;
        }

        .wallet-actions button {
            padding: 8px 16px;
            border: none;
            border-radius: 4px;
            background: #007bff;
            color: white;
            cursor: pointer;
            font-size: 14px;
        }

        .wallet-actions button:hover {
            background: #0056b3;
        }

        .transaction-summary {
            margin-bottom: 16px;
            padding: 8px;
            background: #e9ecef;
            border-radius: 4px;
        }

        .recent-transactions h4 {
            margin: 0 0 12px 0;
            color: #333;
        }

        .transaction-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px;
            margin-bottom: 8px;
            background: white;
            border-radius: 4px;
            border-left: 4px solid #ddd;
        }

        .transaction-item.pending {
            border-left-color: #ffc107;
        }

        .transaction-item.confirmed {
            border-left-color: #28a745;
        }

        .transaction-item.failed {
            border-left-color: #dc3545;
        }

        .tx-hash {
            font-family: monospace;
            font-size: 12px;
            color: #666;
        }

        .tx-from-to {
            font-family: monospace;
            font-size: 12px;
            color: #333;
        }

        .tx-value {
            font-weight: bold;
            color: #333;
        }

        .tx-status {
            font-size: 12px;
            text-transform: uppercase;
        }

        .wallet-prompt {
            text-align: center;
            padding: 32px;
        }

        .wallet-prompt h3 {
            margin-bottom: 16px;
            color: #333;
        }

        .wallet-prompt p {
            margin-bottom: 24px;
            color: #666;
        }

        .wallet-options {
            display: flex;
            justify-content: center;
            gap: 16px;
        }

        .wallet-options button {
            padding: 12px 24px;
            border: 2px solid #007bff;
            border-radius: 8px;
            background: white;
            color: #007bff;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.2s;
        }

        .wallet-options button:hover {
            background: #007bff;
            color: white;
        }

        .no-transactions {
            text-align: center;
            color: #666;
            font-style: italic;
            padding: 16px;
        }
        "#.to_string()
    }
}

impl Default for WalletUIManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wallet_ui_state_creation() {
        let state = WalletUIState::new();
        assert!(!state.is_connected);
        assert!(state.current_account.is_none());
        assert!(!state.networks.is_empty());
    }

    #[test]
    fn test_wallet_connection() {
        let mut state = WalletUIState::new();
        let account = AccountInfo {
            address: "0x1234567890123456789012345678901234567890".to_string(),
            name: "Test Account".to_string(),
            balance: "1.5".to_string(),
            network: "ethereum-mainnet".to_string(),
            account_type: AccountType::Software,
        };

        state.connect_wallet(account).unwrap();
        assert!(state.is_connected);
        assert!(state.current_account.is_some());
        assert_eq!(state.accounts.len(), 1);
    }

    #[test]
    fn test_network_switching() {
        let mut state = WalletUIState::new();
        
        state.switch_network("polygon-mainnet").unwrap();
        assert_eq!(state.current_network, Some("polygon-mainnet".to_string()));
        
        let network = state.get_current_network().unwrap();
        assert_eq!(network.name, "Polygon Mainnet");
    }

    #[test]
    fn test_transaction_management() {
        let mut state = WalletUIState::new();
        let tx = TransactionInfo {
            hash: "0xabcdef".to_string(),
            from: "0x1111".to_string(),
            to: "0x2222".to_string(),
            value: "1.0 ETH".to_string(),
            gas_used: Some("21000".to_string()),
            gas_price: Some("20".to_string()),
            timestamp: 1234567890,
            status: TransactionStatus::Pending,
            block_number: None,
        };

        state.add_transaction(tx);
        assert_eq!(state.transactions.len(), 1);
        assert_eq!(state.get_pending_transactions_count(), 1);

        state.update_transaction_status("0xabcdef", TransactionStatus::Confirmed, Some(12345));
        assert_eq!(state.get_pending_transactions_count(), 0);
    }
}
