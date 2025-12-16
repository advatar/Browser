use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Manager, Runtime, WebviewWindow};
use url::Url;

/// Browser tab information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tab {
    pub id: String,
    pub title: String,
    pub url: String,
    pub favicon: Option<String>,
    pub is_loading: bool,
    pub can_go_back: bool,
    pub can_go_forward: bool,
    pub is_pinned: bool,
    pub is_muted: bool,
}

impl Tab {
    pub fn new(id: String, url: String) -> Self {
        Self {
            id,
            title: "New Tab".to_string(),
            url,
            favicon: None,
            is_loading: false,
            can_go_back: false,
            can_go_forward: false,
            is_pinned: false,
            is_muted: false,
        }
    }
}

/// Browser history entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryEntry {
    pub id: String,
    pub url: String,
    pub title: String,
    pub timestamp: u64,
    pub visit_count: u32,
}

/// Bookmark entry
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bookmark {
    pub id: String,
    pub title: String,
    pub url: String,
    pub folder: Option<String>,
    pub tags: Vec<String>,
    pub created_at: u64,
}

/// Browser engine state
#[derive(Debug, Clone)]
pub struct BrowserEngine {
    pub tabs: Arc<Mutex<HashMap<String, Tab>>>,
    pub active_tab_id: Arc<Mutex<Option<String>>>,
    pub history: Arc<Mutex<Vec<HistoryEntry>>>,
    pub bookmarks: Arc<Mutex<Vec<Bookmark>>>,
    pub downloads: Arc<Mutex<Vec<DownloadItem>>>,
}

/// Download item
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DownloadItem {
    pub id: String,
    pub url: String,
    pub filename: String,
    pub total_bytes: Option<u64>,
    pub received_bytes: u64,
    pub state: DownloadState,
    pub start_time: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum DownloadState {
    InProgress,
    Completed,
    Cancelled,
    Failed(String),
}

impl BrowserEngine {
    pub fn new() -> Self {
        Self {
            tabs: Arc::new(Mutex::new(HashMap::new())),
            active_tab_id: Arc::new(Mutex::new(None)),
            history: Arc::new(Mutex::new(Vec::new())),
            bookmarks: Arc::new(Mutex::new(Vec::new())),
            downloads: Arc::new(Mutex::new(Vec::new())),
        }
    }

    /// Create a new tab
    pub fn create_tab(&self, url: String) -> Result<String> {
        let tab_id = uuid::Uuid::new_v4().to_string();
        let tab = Tab::new(tab_id.clone(), url);

        if let Ok(mut tabs) = self.tabs.lock() {
            tabs.insert(tab_id.clone(), tab);
        }

        // Set as active tab if it's the first one
        if let Ok(mut active_id) = self.active_tab_id.lock() {
            if active_id.is_none() {
                *active_id = Some(tab_id.clone());
            }
        }

        Ok(tab_id)
    }

    /// Close a tab
    pub fn close_tab(&self, tab_id: &str) -> Result<()> {
        if let Ok(mut tabs) = self.tabs.lock() {
            tabs.remove(tab_id);
        }

        // If this was the active tab, switch to another one
        if let Ok(mut active_id) = self.active_tab_id.lock() {
            if active_id.as_ref() == Some(&tab_id.to_string()) {
                if let Ok(tabs) = self.tabs.lock() {
                    *active_id = tabs.keys().next().cloned();
                }
            }
        }

        Ok(())
    }

    /// Switch to a tab
    pub fn switch_tab(&self, tab_id: &str) -> Result<()> {
        if let Ok(tabs) = self.tabs.lock() {
            if tabs.contains_key(tab_id) {
                if let Ok(mut active_id) = self.active_tab_id.lock() {
                    *active_id = Some(tab_id.to_string());
                }
                return Ok(());
            }
        }
        Err(anyhow!("Tab not found: {}", tab_id))
    }

    /// Get all tabs
    pub fn get_tabs(&self) -> Result<Vec<Tab>> {
        if let Ok(tabs) = self.tabs.lock() {
            Ok(tabs.values().cloned().collect())
        } else {
            Err(anyhow!("Failed to lock tabs"))
        }
    }

    /// Get active tab
    pub fn get_active_tab(&self) -> Result<Option<Tab>> {
        if let Ok(active_id) = self.active_tab_id.lock() {
            if let Some(id) = active_id.as_ref() {
                if let Ok(tabs) = self.tabs.lock() {
                    return Ok(tabs.get(id).cloned());
                }
            }
        }
        Ok(None)
    }

    /// Update tab information
    pub fn update_tab(
        &self,
        tab_id: &str,
        title: Option<String>,
        url: Option<String>,
        is_loading: Option<bool>,
    ) -> Result<()> {
        if let Ok(mut tabs) = self.tabs.lock() {
            if let Some(tab) = tabs.get_mut(tab_id) {
                if let Some(title) = title {
                    tab.title = title;
                }
                if let Some(url) = url {
                    tab.url = url;
                }
                if let Some(is_loading) = is_loading {
                    tab.is_loading = is_loading;
                }
                return Ok(());
            }
        }
        Err(anyhow!("Tab not found: {}", tab_id))
    }

    /// Add to history
    pub fn add_to_history(&self, url: String, title: String) -> Result<()> {
        let entry = HistoryEntry {
            id: uuid::Uuid::new_v4().to_string(),
            url,
            title,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            visit_count: 1,
        };

        if let Ok(mut history) = self.history.lock() {
            // Check if URL already exists and update visit count
            if let Some(existing) = history.iter_mut().find(|h| h.url == entry.url) {
                existing.visit_count += 1;
                existing.timestamp = entry.timestamp;
            } else {
                history.push(entry);
            }

            // Keep only last 1000 entries
            let history_len = history.len();
            if history_len > 1000 {
                history.drain(0..history_len - 1000);
            }
        }

        Ok(())
    }

    /// Get history
    pub fn get_history(&self) -> Result<Vec<HistoryEntry>> {
        if let Ok(history) = self.history.lock() {
            let mut entries = history.clone();
            entries.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
            Ok(entries)
        } else {
            Err(anyhow!("Failed to lock history"))
        }
    }

    /// Add bookmark
    pub fn add_bookmark(
        &self,
        title: String,
        url: String,
        folder: Option<String>,
        tags: Vec<String>,
    ) -> Result<String> {
        let bookmark = Bookmark {
            id: uuid::Uuid::new_v4().to_string(),
            title,
            url,
            folder,
            tags,
            created_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        };

        let bookmark_id = bookmark.id.clone();

        if let Ok(mut bookmarks) = self.bookmarks.lock() {
            bookmarks.push(bookmark);
        }

        Ok(bookmark_id)
    }

    /// Remove bookmark
    pub fn remove_bookmark(&self, bookmark_id: &str) -> Result<()> {
        if let Ok(mut bookmarks) = self.bookmarks.lock() {
            bookmarks.retain(|b| b.id != bookmark_id);
        }
        Ok(())
    }

    /// Get bookmarks
    pub fn get_bookmarks(&self) -> Result<Vec<Bookmark>> {
        if let Ok(bookmarks) = self.bookmarks.lock() {
            Ok(bookmarks.clone())
        } else {
            Err(anyhow!("Failed to lock bookmarks"))
        }
    }

    /// Start download
    pub fn start_download(&self, url: String, filename: String) -> Result<String> {
        let download = DownloadItem {
            id: uuid::Uuid::new_v4().to_string(),
            url,
            filename,
            total_bytes: None,
            received_bytes: 0,
            state: DownloadState::InProgress,
            start_time: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        };

        let download_id = download.id.clone();

        if let Ok(mut downloads) = self.downloads.lock() {
            downloads.push(download);
        }

        Ok(download_id)
    }

    /// Update download progress
    pub fn update_download(
        &self,
        download_id: &str,
        received_bytes: u64,
        total_bytes: Option<u64>,
    ) -> Result<()> {
        if let Ok(mut downloads) = self.downloads.lock() {
            if let Some(download) = downloads.iter_mut().find(|d| d.id == download_id) {
                download.received_bytes = received_bytes;
                if let Some(total) = total_bytes {
                    download.total_bytes = Some(total);
                }

                // Check if download is complete
                if let Some(total) = download.total_bytes {
                    if received_bytes >= total {
                        download.state = DownloadState::Completed;
                    }
                }
            }
        }
        Ok(())
    }

    /// Get downloads
    pub fn get_downloads(&self) -> Result<Vec<DownloadItem>> {
        if let Ok(downloads) = self.downloads.lock() {
            Ok(downloads.clone())
        } else {
            Err(anyhow!("Failed to lock downloads"))
        }
    }
}

impl Default for BrowserEngine {
    fn default() -> Self {
        Self::new()
    }
}

/// Navigation helper functions
pub mod navigation {
    use super::*;

    /// Check if URL is valid
    pub fn is_valid_url(url: &str) -> bool {
        if url.starts_with("http://") || url.starts_with("https://") {
            Url::parse(url).is_ok()
        } else if url.starts_with("ipfs://") || url.starts_with("ipns://") {
            // Basic validation for IPFS URLs
            url.len() > 7 && !url[7..].is_empty()
        } else if url.starts_with("ens://") {
            // Basic validation for ENS URLs
            url.len() > 6 && url[6..].contains('.')
        } else {
            false
        }
    }

    /// Convert search query to URL
    pub fn search_query_to_url(query: &str, search_engine: &str) -> String {
        let encoded_query = urlencoding::encode(query);
        match search_engine {
            "duckduckgo" => format!("https://duckduckgo.com/?q={}", encoded_query),
            "google" => format!("https://www.google.com/search?q={}", encoded_query),
            "bing" => format!("https://www.bing.com/search?q={}", encoded_query),
            _ => format!("https://duckduckgo.com/?q={}", encoded_query),
        }
    }

    /// Normalize URL for display
    pub fn normalize_url_for_display(url: &str) -> String {
        if url.starts_with("https://") {
            url[8..].to_string()
        } else if url.starts_with("http://") {
            url[7..].to_string()
        } else {
            url.to_string()
        }
    }

    /// Get domain from URL
    pub fn get_domain(url: &str) -> Option<String> {
        if let Ok(parsed) = Url::parse(url) {
            parsed.host_str().map(|s| s.to_string())
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_browser_engine_creation() {
        let engine = BrowserEngine::new();
        assert!(engine.get_tabs().unwrap().is_empty());
        assert!(engine.get_active_tab().unwrap().is_none());
    }

    #[test]
    fn test_tab_management() {
        let engine = BrowserEngine::new();

        // Create a tab
        let tab_id = engine
            .create_tab("https://example.com".to_string())
            .unwrap();
        assert_eq!(engine.get_tabs().unwrap().len(), 1);

        // Switch to tab
        engine.switch_tab(&tab_id).unwrap();
        assert!(engine.get_active_tab().unwrap().is_some());

        // Close tab
        engine.close_tab(&tab_id).unwrap();
        assert!(engine.get_tabs().unwrap().is_empty());
    }

    #[test]
    fn test_history_management() {
        let engine = BrowserEngine::new();

        engine
            .add_to_history("https://example.com".to_string(), "Example".to_string())
            .unwrap();
        let history = engine.get_history().unwrap();
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].url, "https://example.com");
    }

    #[test]
    fn test_bookmark_management() {
        let engine = BrowserEngine::new();

        let bookmark_id = engine
            .add_bookmark(
                "Example".to_string(),
                "https://example.com".to_string(),
                None,
                vec!["test".to_string()],
            )
            .unwrap();

        let bookmarks = engine.get_bookmarks().unwrap();
        assert_eq!(bookmarks.len(), 1);

        engine.remove_bookmark(&bookmark_id).unwrap();
        assert!(engine.get_bookmarks().unwrap().is_empty());
    }

    #[test]
    fn test_url_validation() {
        assert!(navigation::is_valid_url("https://example.com"));
        assert!(navigation::is_valid_url("http://example.com"));
        assert!(navigation::is_valid_url("ipfs://QmHash"));
        assert!(navigation::is_valid_url("ens://example.eth"));
        assert!(!navigation::is_valid_url("invalid"));
    }
}
