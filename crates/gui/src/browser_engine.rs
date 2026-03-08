use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(default)]
    pub keywords: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistorySearchMatch {
    pub entry: HistoryEntry,
    pub score: f32,
    pub matched_fields: Vec<String>,
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
        self.upsert_history_entry(url, title, None, Vec::new(), true)
    }

    pub fn enrich_history_entry(
        &self,
        url: &str,
        title: Option<String>,
        summary: Option<String>,
        keywords: Vec<String>,
    ) -> Result<()> {
        self.upsert_history_entry(
            url.to_string(),
            title.unwrap_or_else(|| url.to_string()),
            summary,
            keywords,
            false,
        )
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

    pub fn search_history(&self, query: &str, limit: usize) -> Result<Vec<HistorySearchMatch>> {
        let limit = limit.clamp(1, 50);
        let normalized_query = normalize_search_text(query);
        let entries = self.get_history()?;
        if normalized_query.is_empty() {
            return Ok(entries
                .into_iter()
                .take(limit)
                .map(|entry| HistorySearchMatch {
                    entry,
                    score: 0.0,
                    matched_fields: vec!["recent".to_string()],
                })
                .collect());
        }

        let query_tokens = tokenize_for_search(&normalized_query);
        let now = unix_timestamp();
        let mut matches: Vec<_> = entries
            .into_iter()
            .filter_map(|entry| score_history_entry(entry, &normalized_query, &query_tokens, now))
            .collect();
        matches.sort_by(|left, right| {
            right
                .score
                .partial_cmp(&left.score)
                .unwrap_or(Ordering::Equal)
                .then_with(|| right.entry.timestamp.cmp(&left.entry.timestamp))
        });
        matches.truncate(limit);
        Ok(matches)
    }

    pub fn remove_history_entry(&self, entry_id: &str) -> Result<bool> {
        let mut history = self
            .history
            .lock()
            .map_err(|_| anyhow!("Failed to lock history"))?;
        let before = history.len();
        history.retain(|entry| entry.id != entry_id);
        Ok(history.len() != before)
    }

    pub fn clear_history(&self) -> Result<()> {
        let mut history = self
            .history
            .lock()
            .map_err(|_| anyhow!("Failed to lock history"))?;
        history.clear();
        Ok(())
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

    fn upsert_history_entry(
        &self,
        url: String,
        title: String,
        summary: Option<String>,
        keywords: Vec<String>,
        increment_visit: bool,
    ) -> Result<()> {
        let mut history = self
            .history
            .lock()
            .map_err(|_| anyhow!("Failed to lock history"))?;
        let now = unix_timestamp();
        let summary = normalize_summary(summary);
        let derived_keywords = merge_keywords(
            keywords,
            extract_keywords(&url, &title, summary.as_deref()),
        );

        if let Some(existing) = history.iter_mut().find(|entry| entry.url == url) {
            if increment_visit {
                existing.visit_count = existing.visit_count.saturating_add(1);
                existing.timestamp = now;
            }
            if should_replace_title(&existing.title, &title, &existing.url) {
                existing.title = title;
            }
            if let Some(summary) = summary {
                existing.summary = Some(summary);
            }
            existing.keywords = merge_keywords(existing.keywords.clone(), derived_keywords);
        } else {
            history.push(HistoryEntry {
                id: uuid::Uuid::new_v4().to_string(),
                url,
                title,
                timestamp: now,
                visit_count: 1,
                summary,
                keywords: derived_keywords,
            });
        }

        let history_len = history.len();
        if history_len > 1000 {
            history.drain(0..history_len - 1000);
        }

        Ok(())
    }
}

impl Default for BrowserEngine {
    fn default() -> Self {
        Self::new()
    }
}

fn unix_timestamp() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

fn normalize_summary(summary: Option<String>) -> Option<String> {
    summary
        .map(|value| value.split_whitespace().collect::<Vec<_>>().join(" "))
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .map(|value| value.chars().take(280).collect::<String>())
}

fn should_replace_title(existing: &str, next: &str, url: &str) -> bool {
    let existing = existing.trim();
    let next = next.trim();
    !next.is_empty()
        && (existing.is_empty() || existing == url || next.len() > existing.len() || next != url)
}

fn extract_keywords(url: &str, title: &str, summary: Option<&str>) -> Vec<String> {
    let mut keywords = tokenize_for_search(url);
    keywords.extend(tokenize_for_search(title));
    if let Some(summary) = summary {
        keywords.extend(tokenize_for_search(summary));
    }
    merge_keywords(Vec::new(), keywords)
}

fn merge_keywords(existing: Vec<String>, next: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut merged = Vec::new();
    for token in existing.into_iter().chain(next.into_iter()) {
        let normalized = normalize_search_text(&token);
        if normalized.len() < 2 || seen.contains(&normalized) {
            continue;
        }
        seen.insert(normalized.clone());
        merged.push(normalized);
        if merged.len() >= 24 {
            break;
        }
    }
    merged
}

fn normalize_search_text(input: &str) -> String {
    input
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch.is_whitespace() {
                ch.to_ascii_lowercase()
            } else {
                ' '
            }
        })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn tokenize_for_search(input: &str) -> Vec<String> {
    normalize_search_text(input)
        .split_whitespace()
        .filter(|token| token.len() > 1)
        .map(|token| token.to_string())
        .collect()
}

fn score_history_entry(
    entry: HistoryEntry,
    normalized_query: &str,
    query_tokens: &[String],
    now: u64,
) -> Option<HistorySearchMatch> {
    let title = normalize_search_text(&entry.title);
    let url = normalize_search_text(&entry.url);
    let domain = navigation::get_domain(&entry.url)
        .map(|value| normalize_search_text(&value))
        .unwrap_or_default();
    let summary = entry
        .summary
        .as_deref()
        .map(normalize_search_text)
        .unwrap_or_default();

    let mut score = 0.0f32;
    let mut matched_fields = HashSet::new();

    if title.contains(normalized_query) {
        score += 12.0;
        matched_fields.insert("title".to_string());
    }
    if url.contains(normalized_query) || domain.contains(normalized_query) {
        score += 9.0;
        matched_fields.insert("url".to_string());
    }
    if summary.contains(normalized_query) {
        score += 10.0;
        matched_fields.insert("summary".to_string());
    }

    for token in query_tokens {
        if title.contains(token) {
            score += 5.0;
            matched_fields.insert("title".to_string());
        }
        if url.contains(token) || domain.contains(token) {
            score += 4.0;
            matched_fields.insert("url".to_string());
        }
        if summary.contains(token) {
            score += 3.0;
            matched_fields.insert("summary".to_string());
        }
        if entry.keywords.iter().any(|keyword| keyword.contains(token)) {
            score += 4.0;
            matched_fields.insert("keywords".to_string());
        }
    }

    if score <= 0.0 {
        return None;
    }

    let age_hours = now.saturating_sub(entry.timestamp) as f32 / 3600.0;
    score += 4.0 / (1.0 + age_hours / 24.0);
    score += (entry.visit_count.max(1) as f32).ln_1p();

    let mut matched_fields = matched_fields.into_iter().collect::<Vec<_>>();
    matched_fields.sort();

    Some(HistorySearchMatch {
        entry,
        score,
        matched_fields,
    })
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
        assert_eq!(history[0].visit_count, 1);
        assert!(history[0].summary.is_none());
    }

    #[test]
    fn test_history_search_uses_enriched_context() {
        let engine = BrowserEngine::new();

        engine
            .add_to_history("https://docs.example.com/mcp".to_string(), "MCP Transport Notes".to_string())
            .unwrap();
        engine
            .enrich_history_entry(
                "https://docs.example.com/mcp",
                Some("MCP Transport Notes".to_string()),
                Some("Notes about websocket and stdio transports for MCP servers".to_string()),
                vec!["transport".to_string(), "websocket".to_string()],
            )
            .unwrap();

        let matches = engine.search_history("websocket transport", 5).unwrap();
        assert_eq!(matches.len(), 1);
        assert_eq!(matches[0].entry.url, "https://docs.example.com/mcp");
        assert!(matches[0].matched_fields.iter().any(|field| field == "summary"));
    }

    #[test]
    fn test_remove_history_entry() {
        let engine = BrowserEngine::new();

        engine
            .add_to_history("https://example.com".to_string(), "Example".to_string())
            .unwrap();
        let history = engine.get_history().unwrap();
        let removed = engine.remove_history_entry(&history[0].id).unwrap();

        assert!(removed);
        assert!(engine.get_history().unwrap().is_empty());
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
