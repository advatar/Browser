use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};
use url::Url;

/// Content Security Policy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ContentSecurityPolicy {
    pub default_src: Vec<String>,
    pub script_src: Vec<String>,
    pub style_src: Vec<String>,
    pub img_src: Vec<String>,
    pub connect_src: Vec<String>,
    pub font_src: Vec<String>,
    pub object_src: Vec<String>,
    pub media_src: Vec<String>,
    pub frame_src: Vec<String>,
}

impl Default for ContentSecurityPolicy {
    fn default() -> Self {
        Self {
            default_src: vec!["'self'".to_string()],
            script_src: vec!["'self'".to_string(), "'unsafe-inline'".to_string()],
            style_src: vec!["'self'".to_string(), "'unsafe-inline'".to_string()],
            img_src: vec![
                "'self'".to_string(),
                "data:".to_string(),
                "https:".to_string(),
            ],
            connect_src: vec![
                "'self'".to_string(),
                "https:".to_string(),
                "wss:".to_string(),
            ],
            font_src: vec!["'self'".to_string(), "https:".to_string()],
            object_src: vec!["'none'".to_string()],
            media_src: vec!["'self'".to_string(), "https:".to_string()],
            frame_src: vec!["'self'".to_string()],
        }
    }
}

/// Certificate information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CertificateInfo {
    pub subject: String,
    pub issuer: String,
    pub valid_from: u64,
    pub valid_to: u64,
    pub fingerprint: String,
    pub is_valid: bool,
    pub is_trusted: bool,
}

/// Privacy settings
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrivacySettings {
    pub block_trackers: bool,
    pub block_ads: bool,
    pub block_social_media_trackers: bool,
    pub block_cryptominers: bool,
    pub clear_cookies_on_exit: bool,
    pub do_not_track: bool,
    pub private_browsing: bool,
    pub tor_enabled: bool,
}

impl Default for PrivacySettings {
    fn default() -> Self {
        Self {
            block_trackers: true,
            block_ads: true,
            block_social_media_trackers: true,
            block_cryptominers: true,
            clear_cookies_on_exit: false,
            do_not_track: true,
            private_browsing: false,
            tor_enabled: false,
        }
    }
}

/// Cookie information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Cookie {
    pub name: String,
    pub value: String,
    pub domain: String,
    pub path: String,
    pub expires: Option<u64>,
    pub secure: bool,
    pub http_only: bool,
    pub same_site: Option<String>,
}

/// Security manager
#[derive(Debug)]
pub struct SecurityManager {
    pub csp: ContentSecurityPolicy,
    pub privacy_settings: PrivacySettings,
    pub certificates: Arc<Mutex<HashMap<String, CertificateInfo>>>,
    pub cookies: Arc<Mutex<HashMap<String, Vec<Cookie>>>>,
    pub blocked_domains: Arc<Mutex<HashSet<String>>>,
    pub tracker_lists: Arc<Mutex<Vec<String>>>,
    pub ad_block_lists: Arc<Mutex<Vec<String>>>,
}

impl SecurityManager {
    pub fn new() -> Self {
        Self {
            csp: ContentSecurityPolicy::default(),
            privacy_settings: PrivacySettings::default(),
            certificates: Arc::new(Mutex::new(HashMap::new())),
            cookies: Arc::new(Mutex::new(HashMap::new())),
            blocked_domains: Arc::new(Mutex::new(HashSet::new())),
            tracker_lists: Arc::new(Mutex::new(Self::default_tracker_list())),
            ad_block_lists: Arc::new(Mutex::new(Self::default_ad_block_list())),
        }
    }

    /// Validate URL security
    pub fn validate_url_security(&self, url: &str) -> Result<bool> {
        let parsed_url = Url::parse(url)?;

        // Check if domain is blocked
        if let Some(domain) = parsed_url.host_str() {
            if let Ok(blocked_domains) = self.blocked_domains.lock() {
                if blocked_domains.contains::<str>(domain) {
                    return Ok(false);
                }
            }

            // Check against tracker lists
            if self.privacy_settings.block_trackers {
                if let Ok(tracker_lists) = self.tracker_lists.lock() {
                    for tracker_pattern in tracker_lists.iter() {
                        if domain.contains(tracker_pattern) {
                            return Ok(false);
                        }
                    }
                }
            }

            // Check against ad block lists
            if self.privacy_settings.block_ads {
                if let Ok(ad_block_lists) = self.ad_block_lists.lock() {
                    for ad_pattern in ad_block_lists.iter() {
                        if domain.contains(ad_pattern) {
                            return Ok(false);
                        }
                    }
                }
            }
        }

        // Check protocol security
        match parsed_url.scheme() {
            "https" => Ok(true),
            "http" => {
                // Allow HTTP for localhost and development
                if let Some(host) = parsed_url.host_str() {
                    Ok(host == "localhost" || host == "127.0.0.1" || host.starts_with("192.168."))
                } else {
                    Ok(false)
                }
            }
            "ipfs" | "ipns" => Ok(true), // Allow decentralized protocols
            _ => Ok(false),
        }
    }

    /// Generate CSP header
    pub fn generate_csp_header(&self) -> String {
        let mut directives = Vec::new();

        if !self.csp.default_src.is_empty() {
            directives.push(format!("default-src {}", self.csp.default_src.join(" ")));
        }
        if !self.csp.script_src.is_empty() {
            directives.push(format!("script-src {}", self.csp.script_src.join(" ")));
        }
        if !self.csp.style_src.is_empty() {
            directives.push(format!("style-src {}", self.csp.style_src.join(" ")));
        }
        if !self.csp.img_src.is_empty() {
            directives.push(format!("img-src {}", self.csp.img_src.join(" ")));
        }
        if !self.csp.connect_src.is_empty() {
            directives.push(format!("connect-src {}", self.csp.connect_src.join(" ")));
        }
        if !self.csp.font_src.is_empty() {
            directives.push(format!("font-src {}", self.csp.font_src.join(" ")));
        }
        if !self.csp.object_src.is_empty() {
            directives.push(format!("object-src {}", self.csp.object_src.join(" ")));
        }
        if !self.csp.media_src.is_empty() {
            directives.push(format!("media-src {}", self.csp.media_src.join(" ")));
        }
        if !self.csp.frame_src.is_empty() {
            directives.push(format!("frame-src {}", self.csp.frame_src.join(" ")));
        }

        directives.join("; ")
    }

    /// Validate certificate
    pub fn validate_certificate(&self, domain: &str, cert_info: CertificateInfo) -> Result<bool> {
        // Store certificate info
        if let Ok(mut certificates) = self.certificates.lock() {
            certificates.insert(domain.to_string(), cert_info.clone());
        }

        // Basic validation
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        if cert_info.valid_from > now || cert_info.valid_to < now {
            return Ok(false);
        }

        // Check if certificate is for the correct domain
        if !cert_info.subject.contains(domain) {
            return Ok(false);
        }

        Ok(cert_info.is_valid && cert_info.is_trusted)
    }

    /// Add cookie
    pub fn add_cookie(&self, domain: &str, cookie: Cookie) -> Result<()> {
        if let Ok(mut cookies) = self.cookies.lock() {
            let domain_cookies = cookies.entry(domain.to_string()).or_insert_with(Vec::new);

            // Remove existing cookie with same name
            domain_cookies.retain(|c| c.name != cookie.name);

            // Add new cookie
            domain_cookies.push(cookie);
        }
        Ok(())
    }

    /// Get cookies for domain
    pub fn get_cookies(&self, domain: &str) -> Result<Vec<Cookie>> {
        if let Ok(cookies) = self.cookies.lock() {
            if let Some(domain_cookies) = cookies.get(domain) {
                // Filter expired cookies
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs();

                let valid_cookies: Vec<Cookie> = domain_cookies
                    .iter()
                    .filter(|cookie| cookie.expires.map_or(true, |expires| expires > now))
                    .cloned()
                    .collect();

                return Ok(valid_cookies);
            }
        }
        Ok(Vec::new())
    }

    /// Clear cookies for domain
    pub fn clear_cookies(&self, domain: Option<&str>) -> Result<()> {
        if let Ok(mut cookies) = self.cookies.lock() {
            if let Some(domain) = domain {
                cookies.remove(domain);
            } else {
                cookies.clear();
            }
        }
        Ok(())
    }

    /// Block domain
    pub fn block_domain(&self, domain: &str) -> Result<()> {
        if let Ok(mut blocked_domains) = self.blocked_domains.lock() {
            blocked_domains.insert(domain.to_string());
        }
        Ok(())
    }

    /// Unblock domain
    pub fn unblock_domain(&self, domain: &str) -> Result<()> {
        if let Ok(mut blocked_domains) = self.blocked_domains.lock() {
            blocked_domains.remove(domain);
        }
        Ok(())
    }

    /// Update privacy settings
    pub fn update_privacy_settings(&mut self, settings: PrivacySettings) {
        self.privacy_settings = settings;
    }

    /// Get privacy headers
    pub fn get_privacy_headers(&self) -> HashMap<String, String> {
        let mut headers = HashMap::new();

        if self.privacy_settings.do_not_track {
            headers.insert("DNT".to_string(), "1".to_string());
        }

        // Add security headers
        headers.insert("X-Content-Type-Options".to_string(), "nosniff".to_string());
        headers.insert("X-Frame-Options".to_string(), "DENY".to_string());
        headers.insert("X-XSS-Protection".to_string(), "1; mode=block".to_string());
        headers.insert(
            "Referrer-Policy".to_string(),
            "strict-origin-when-cross-origin".to_string(),
        );

        // Add CSP header
        headers.insert(
            "Content-Security-Policy".to_string(),
            self.generate_csp_header(),
        );

        headers
    }

    /// Default tracker list
    fn default_tracker_list() -> Vec<String> {
        vec![
            "google-analytics.com".to_string(),
            "googletagmanager.com".to_string(),
            "facebook.com/tr".to_string(),
            "doubleclick.net".to_string(),
            "googlesyndication.com".to_string(),
            "amazon-adsystem.com".to_string(),
            "twitter.com/i/adsct".to_string(),
            "linkedin.com/px".to_string(),
            "pinterest.com/ct".to_string(),
            "snapchat.com/tr".to_string(),
        ]
    }

    /// Default ad block list
    fn default_ad_block_list() -> Vec<String> {
        vec![
            "ads.yahoo.com".to_string(),
            "adsystem.amazon.com".to_string(),
            "googleads.g.doubleclick.net".to_string(),
            "pagead2.googlesyndication.com".to_string(),
            "tpc.googlesyndication.com".to_string(),
            "partner.googleadservices.com".to_string(),
            "facebook.com/tr".to_string(),
            "connect.facebook.net".to_string(),
            "ads.twitter.com".to_string(),
            "analytics.twitter.com".to_string(),
        ]
    }

    /// Enable Tor proxy
    pub fn enable_tor(&mut self, proxy_address: &str) -> Result<()> {
        // In a real implementation, this would configure the HTTP client to use Tor
        self.privacy_settings.tor_enabled = true;
        log::info!("Tor proxy enabled: {}", proxy_address);
        Ok(())
    }

    /// Disable Tor proxy
    pub fn disable_tor(&mut self) -> Result<()> {
        self.privacy_settings.tor_enabled = false;
        log::info!("Tor proxy disabled");
        Ok(())
    }

    /// Clear all private data
    pub fn clear_private_data(&self) -> Result<()> {
        // Clear cookies
        self.clear_cookies(None)?;

        // Clear certificates cache
        if let Ok(mut certificates) = self.certificates.lock() {
            certificates.clear();
        }

        log::info!("Private data cleared");
        Ok(())
    }
}

impl Default for SecurityManager {
    fn default() -> Self {
        Self::new()
    }
}

/// Tor integration module
pub mod tor {
    use super::*;
    use std::process::{Command, Stdio};

    /// Tor proxy configuration
    #[derive(Debug, Clone)]
    pub struct TorConfig {
        pub socks_port: u16,
        pub control_port: u16,
        pub data_directory: String,
    }

    impl Default for TorConfig {
        fn default() -> Self {
            Self {
                socks_port: 9050,
                control_port: 9051,
                data_directory: "/tmp/tor_browser".to_string(),
            }
        }
    }

    /// Tor proxy manager
    pub struct TorManager {
        config: TorConfig,
        process: Option<std::process::Child>,
    }

    impl TorManager {
        pub fn new(config: TorConfig) -> Self {
            Self {
                config,
                process: None,
            }
        }

        /// Start Tor proxy
        pub fn start(&mut self) -> Result<()> {
            if self.process.is_some() {
                return Ok(()); // Already running
            }

            // Create data directory
            std::fs::create_dir_all(&self.config.data_directory)?;

            // Start Tor process
            let child = Command::new("tor")
                .args(&[
                    "--SocksPort",
                    &self.config.socks_port.to_string(),
                    "--ControlPort",
                    &self.config.control_port.to_string(),
                    "--DataDirectory",
                    &self.config.data_directory,
                    "--quiet",
                ])
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?;

            self.process = Some(child);

            // Wait a moment for Tor to start
            std::thread::sleep(std::time::Duration::from_secs(3));

            Ok(())
        }

        /// Stop Tor proxy
        pub fn stop(&mut self) -> Result<()> {
            if let Some(mut process) = self.process.take() {
                process.kill()?;
                process.wait()?;
            }
            Ok(())
        }

        /// Check if Tor is running
        pub fn is_running(&mut self) -> bool {
            if let Some(process) = &mut self.process {
                match process.try_wait() {
                    Ok(Some(_)) => {
                        self.process = None;
                        false
                    }
                    Ok(None) => true,
                    Err(_) => {
                        self.process = None;
                        false
                    }
                }
            } else {
                false
            }
        }

        /// Get SOCKS proxy URL
        pub fn get_proxy_url(&self) -> String {
            format!("socks5://127.0.0.1:{}", self.config.socks_port)
        }
    }

    impl Drop for TorManager {
        fn drop(&mut self) {
            let _ = self.stop();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_security_manager_creation() {
        let manager = SecurityManager::new();
        assert!(manager.privacy_settings.block_trackers);
        assert!(manager.privacy_settings.block_ads);
    }

    #[test]
    fn test_csp_generation() {
        let manager = SecurityManager::new();
        let csp = manager.generate_csp_header();
        assert!(csp.contains("default-src 'self'"));
        assert!(csp.contains("object-src 'none'"));
    }

    #[test]
    fn test_url_validation() {
        let manager = SecurityManager::new();

        assert!(manager
            .validate_url_security("https://example.com")
            .unwrap());
        assert!(manager
            .validate_url_security("http://localhost:3000")
            .unwrap());
        assert!(manager.validate_url_security("ipfs://QmHash").unwrap());
        assert!(!manager.validate_url_security("ftp://example.com").unwrap());
    }

    #[test]
    fn test_cookie_management() {
        let manager = SecurityManager::new();

        let cookie = Cookie {
            name: "test".to_string(),
            value: "value".to_string(),
            domain: "example.com".to_string(),
            path: "/".to_string(),
            expires: None,
            secure: true,
            http_only: false,
            same_site: Some("Strict".to_string()),
        };

        manager.add_cookie("example.com", cookie).unwrap();
        let cookies = manager.get_cookies("example.com").unwrap();
        assert_eq!(cookies.len(), 1);
        assert_eq!(cookies[0].name, "test");
    }

    #[test]
    fn test_domain_blocking() {
        let manager = SecurityManager::new();

        manager.block_domain("malicious.com").unwrap();
        assert!(!manager
            .validate_url_security("https://malicious.com")
            .unwrap());

        manager.unblock_domain("malicious.com").unwrap();
        assert!(manager
            .validate_url_security("https://malicious.com")
            .unwrap());
    }
}
