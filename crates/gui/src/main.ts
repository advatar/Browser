import { invoke } from '@tauri-apps/api/tauri';
import { listen } from '@tauri-apps/api/event';
import { appWindow } from '@tauri-apps/api/window';

// Type definitions for our Rust backend
interface Tab {
  id: string;
  title: string;
  url: string;
  favicon?: string;
  is_loading: boolean;
  can_go_back: boolean;
  can_go_forward: boolean;
  is_pinned: boolean;
  is_muted: boolean;
}

interface Bookmark {
  id: string;
  title: string;
  url: string;
  folder?: string;
  tags: string[];
  created_at: number;
}

interface HistoryEntry {
  id: string;
  url: string;
  title: string;
  timestamp: number;
  visit_count: number;
}

interface SecurityStatus {
  is_secure: boolean;
  certificate_valid: boolean;
  privacy_settings: PrivacySettings;
  blocked_requests: number;
}

interface PrivacySettings {
  block_trackers: boolean;
  block_ads: boolean;
  block_social_media_trackers: boolean;
  block_cryptominers: boolean;
  clear_cookies_on_exit: boolean;
  do_not_track: boolean;
  private_browsing: boolean;
  tor_enabled: boolean;
}

interface WalletInfo {
  address: string;
  balance: string;
  network: string;
  is_connected: boolean;
}

interface BrowserSettings {
  default_search_engine: string;
  homepage: string;
  privacy_settings: PrivacySettings;
  ipfs_gateway: string;
  ens_resolver?: string;
}

// Browser Engine Manager
class BrowserEngine {
  private tabs: Map<string, Tab> = new Map();
  private activeTabId: string | null = null;
  private history: HistoryEntry[] = [];
  private bookmarks: Bookmark[] = [];

  async createTab(url: string): Promise<string> {
    const tabId = await invoke<string>('create_tab', { url });
    await this.refreshTabs();
    return tabId;
  }

  async closeTab(tabId: string): Promise<void> {
    await invoke('close_tab', { tabId });
    await this.refreshTabs();
  }

  async switchTab(tabId: string): Promise<void> {
    await invoke('switch_tab', { tabId });
    this.activeTabId = tabId;
    this.updateUI();
  }

  async refreshTabs(): Promise<void> {
    const tabs = await invoke<Tab[]>('get_tabs');
    this.tabs.clear();
    tabs.forEach(tab => this.tabs.set(tab.id, tab));
    this.updateTabBar();
  }

  async addBookmark(title: string, url: string, folder?: string, tags: string[] = []): Promise<string> {
    return await invoke<string>('add_bookmark', { title, url, folder, tags });
  }

  async getBookmarks(): Promise<Bookmark[]> {
    this.bookmarks = await invoke<Bookmark[]>('get_bookmarks');
    return this.bookmarks;
  }

  async getHistory(): Promise<HistoryEntry[]> {
    this.history = await invoke<HistoryEntry[]>('get_history');
    return this.history;
  }

  private updateTabBar(): void {
    const tabBar = document.getElementById('tab-bar');
    if (!tabBar) return;

    tabBar.innerHTML = '';
    
    this.tabs.forEach(tab => {
      const tabElement = document.createElement('div');
      tabElement.className = `tab ${tab.id === this.activeTabId ? 'active' : ''}`;
      tabElement.innerHTML = `
        <div class="tab-favicon">${tab.favicon ? `<img src="${tab.favicon}" alt="">` : '🌐'}</div>
        <div class="tab-title">${tab.title}</div>
        <div class="tab-close" onclick="browserEngine.closeTab('${tab.id}')">×</div>
      `;
      tabElement.onclick = () => this.switchTab(tab.id);
      tabBar.appendChild(tabElement);
    });

    // Add new tab button
    const newTabButton = document.createElement('div');
    newTabButton.className = 'new-tab-button';
    newTabButton.innerHTML = '+';
    newTabButton.onclick = () => this.createTab('about:blank');
    tabBar.appendChild(newTabButton);
  }

  private updateUI(): void {
    const activeTab = this.activeTabId ? this.tabs.get(this.activeTabId) : null;
    if (activeTab) {
      const addressBar = document.getElementById('address-bar') as HTMLInputElement;
      if (addressBar) {
        addressBar.value = activeTab.url;
      }
      
      const backButton = document.getElementById('back-button') as HTMLButtonElement;
      const forwardButton = document.getElementById('forward-button') as HTMLButtonElement;
      if (backButton) backButton.disabled = !activeTab.can_go_back;
      if (forwardButton) forwardButton.disabled = !activeTab.can_go_forward;
      
      document.title = `${activeTab.title} - Decentralized Browser`;
    }
  }
}

// Protocol Handler Manager
class ProtocolManager {
  async resolveUrl(url: string): Promise<string> {
    return await invoke<string>('resolve_protocol_url', { url });
  }

  async navigateToUrl(url: string): Promise<void> {
    try {
      const resolvedUrl = await this.resolveUrl(url);
      await invoke('navigate_to', { url: resolvedUrl });
      
      // Add to history
      const title = await this.getPageTitle(resolvedUrl);
      await browserEngine.addToHistory(resolvedUrl, title);
    } catch (error) {
      console.error('Navigation failed:', error);
      this.showError(`Failed to navigate to ${url}: ${error}`);
    }
  }

  private async getPageTitle(url: string): Promise<string> {
    // Try to get the page title, fallback to URL
    try {
      const result = await invoke<string>('execute_script', { 
        script: 'document.title || document.location.href' 
      });
      return result || url;
    } catch {
      return url;
    }
  }

  private showError(message: string): void {
    const errorDiv = document.createElement('div');
    errorDiv.className = 'error-notification';
    errorDiv.textContent = message;
    document.body.appendChild(errorDiv);
    
    setTimeout(() => {
      errorDiv.remove();
    }, 5000);
  }
}

// Security Manager
class SecurityManager {
  private securityStatus: SecurityStatus | null = null;

  async getSecurityStatus(url: string): Promise<SecurityStatus> {
    this.securityStatus = await invoke<SecurityStatus>('get_security_status', { url });
    this.updateSecurityIndicator();
    return this.securityStatus;
  }

  async updatePrivacySettings(settings: PrivacySettings): Promise<void> {
    await invoke('update_security_settings', { settings });
  }

  async blockDomain(domain: string): Promise<void> {
    await invoke('block_domain', { domain });
  }

  async clearCookies(domain?: string): Promise<void> {
    await invoke('clear_cookies', { domain });
  }

  private updateSecurityIndicator(): void {
    const indicator = document.getElementById('security-indicator');
    if (!indicator || !this.securityStatus) return;

    if (this.securityStatus.is_secure) {
      indicator.className = 'security-indicator secure';
      indicator.innerHTML = '🔒';
      indicator.title = 'Secure connection';
    } else {
      indicator.className = 'security-indicator insecure';
      indicator.innerHTML = '⚠️';
      indicator.title = 'Insecure connection';
    }
  }
}

// Wallet Manager
class WalletManager {
  private walletInfo: WalletInfo | null = null;

  async getWalletInfo(): Promise<WalletInfo> {
    this.walletInfo = await invoke<WalletInfo>('get_wallet_info');
    this.updateWalletUI();
    return this.walletInfo;
  }

  async connectWallet(): Promise<WalletInfo> {
    this.walletInfo = await invoke<WalletInfo>('connect_wallet');
    this.updateWalletUI();
    return this.walletInfo;
  }

  async disconnectWallet(): Promise<void> {
    await invoke('disconnect_wallet');
    this.walletInfo = null;
    this.updateWalletUI();
  }

  private updateWalletUI(): void {
    const walletButton = document.getElementById('wallet-button');
    if (!walletButton) return;

    if (this.walletInfo?.is_connected) {
      walletButton.innerHTML = `
        <div class="wallet-connected">
          <div class="wallet-address">${this.formatAddress(this.walletInfo.address)}</div>
          <div class="wallet-balance">${this.walletInfo.balance}</div>
        </div>
      `;
      walletButton.className = 'wallet-button connected';
    } else {
      walletButton.innerHTML = 'Connect Wallet';
      walletButton.className = 'wallet-button disconnected';
    }
  }

  private formatAddress(address: string): string {
    if (address.length > 10) {
      return `${address.slice(0, 6)}...${address.slice(-4)}`;
    }
    return address;
  }
}

// Settings Manager
class SettingsManager {
  private settings: BrowserSettings | null = null;

  async getSettings(): Promise<BrowserSettings> {
    this.settings = await invoke<BrowserSettings>('get_settings');
    return this.settings;
  }

  async updateSettings(settings: BrowserSettings): Promise<void> {
    await invoke('update_settings', { settings });
    this.settings = settings;
  }

  async showSettingsPanel(): Promise<void> {
    const panel = document.getElementById('settings-panel');
    if (!panel) return;

    if (!this.settings) {
      await this.getSettings();
    }

    panel.innerHTML = this.generateSettingsHTML();
    panel.style.display = 'block';
  }

  private generateSettingsHTML(): string {
    if (!this.settings) return '';

    return `
      <div class="settings-content">
        <h2>Browser Settings</h2>
        
        <div class="setting-group">
          <h3>General</h3>
          <label>
            Default Search Engine:
            <select id="search-engine" value="${this.settings.default_search_engine}">
              <option value="duckduckgo">DuckDuckGo</option>
              <option value="google">Google</option>
              <option value="bing">Bing</option>
            </select>
          </label>
          <label>
            Homepage:
            <input type="text" id="homepage" value="${this.settings.homepage}">
          </label>
        </div>

        <div class="setting-group">
          <h3>Privacy & Security</h3>
          <label>
            <input type="checkbox" id="block-trackers" ${this.settings.privacy_settings.block_trackers ? 'checked' : ''}>
            Block Trackers
          </label>
          <label>
            <input type="checkbox" id="block-ads" ${this.settings.privacy_settings.block_ads ? 'checked' : ''}>
            Block Ads
          </label>
          <label>
            <input type="checkbox" id="do-not-track" ${this.settings.privacy_settings.do_not_track ? 'checked' : ''}>
            Send Do Not Track
          </label>
          <label>
            <input type="checkbox" id="tor-enabled" ${this.settings.privacy_settings.tor_enabled ? 'checked' : ''}>
            Enable Tor Proxy
          </label>
        </div>

        <div class="setting-group">
          <h3>Decentralized Web</h3>
          <label>
            IPFS Gateway:
            <input type="text" id="ipfs-gateway" value="${this.settings.ipfs_gateway}">
          </label>
          <label>
            ENS Resolver:
            <input type="text" id="ens-resolver" value="${this.settings.ens_resolver || ''}">
          </label>
        </div>

        <div class="settings-actions">
          <button onclick="settingsManager.saveSettings()">Save</button>
          <button onclick="settingsManager.closeSettings()">Cancel</button>
        </div>
      </div>
    `;
  }

  async saveSettings(): Promise<void> {
    if (!this.settings) return;

    // Collect form values
    const searchEngine = (document.getElementById('search-engine') as HTMLSelectElement).value;
    const homepage = (document.getElementById('homepage') as HTMLInputElement).value;
    const blockTrackers = (document.getElementById('block-trackers') as HTMLInputElement).checked;
    const blockAds = (document.getElementById('block-ads') as HTMLInputElement).checked;
    const doNotTrack = (document.getElementById('do-not-track') as HTMLInputElement).checked;
    const torEnabled = (document.getElementById('tor-enabled') as HTMLInputElement).checked;
    const ipfsGateway = (document.getElementById('ipfs-gateway') as HTMLInputElement).value;
    const ensResolver = (document.getElementById('ens-resolver') as HTMLInputElement).value;

    const updatedSettings: BrowserSettings = {
      default_search_engine: searchEngine,
      homepage,
      privacy_settings: {
        ...this.settings.privacy_settings,
        block_trackers: blockTrackers,
        block_ads: blockAds,
        do_not_track: doNotTrack,
        tor_enabled: torEnabled,
      },
      ipfs_gateway: ipfsGateway,
      ens_resolver: ensResolver || undefined,
    };

    await this.updateSettings(updatedSettings);
    this.closeSettings();
  }

  closeSettings(): void {
    const panel = document.getElementById('settings-panel');
    if (panel) {
      panel.style.display = 'none';
    }
  }
}

// Global instances
const browserEngine = new BrowserEngine();
const protocolManager = new ProtocolManager();
const securityManager = new SecurityManager();
const walletManager = new WalletManager();
const settingsManager = new SettingsManager();

// UI Event Handlers
function handleAddressBarSubmit(): void {
  const addressBar = document.getElementById('address-bar') as HTMLInputElement;
  if (!addressBar) return;

  let url = addressBar.value.trim();
  if (!url) return;

  // Check if it's a search query or URL
  if (!url.includes('.') && !url.includes('://')) {
    // It's a search query
    url = `https://duckduckgo.com/?q=${encodeURIComponent(url)}`;
  } else if (!url.includes('://')) {
    // Add protocol if missing
    url = `https://${url}`;
  }

  protocolManager.navigateToUrl(url);
}

function handleBackButton(): void {
  invoke('execute_script', { script: 'history.back()' });
}

function handleForwardButton(): void {
  invoke('execute_script', { script: 'history.forward()' });
}

function handleRefreshButton(): void {
  invoke('execute_script', { script: 'location.reload()' });
}

function toggleBookmark(): void {
  const addressBar = document.getElementById('address-bar') as HTMLInputElement;
  if (!addressBar) return;

  const url = addressBar.value;
  const title = document.title || url;
  
  browserEngine.addBookmark(title, url);
}

function showBookmarks(): void {
  browserEngine.getBookmarks().then(bookmarks => {
    const panel = document.getElementById('bookmarks-panel');
    if (!panel) return;

    panel.innerHTML = `
      <div class="bookmarks-content">
        <h2>Bookmarks</h2>
        <div class="bookmarks-list">
          ${bookmarks.map(bookmark => `
            <div class="bookmark-item">
              <div class="bookmark-title">${bookmark.title}</div>
              <div class="bookmark-url">${bookmark.url}</div>
              <div class="bookmark-actions">
                <button onclick="protocolManager.navigateToUrl('${bookmark.url}')">Visit</button>
                <button onclick="removeBookmark('${bookmark.id}')">Remove</button>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
    panel.style.display = 'block';
  });
}

function removeBookmark(bookmarkId: string): void {
  invoke('remove_bookmark', { bookmarkId }).then(() => {
    showBookmarks(); // Refresh the bookmarks panel
  });
}

function showHistory(): void {
  browserEngine.getHistory().then(history => {
    const panel = document.getElementById('history-panel');
    if (!panel) return;

    panel.innerHTML = `
      <div class="history-content">
        <h2>History</h2>
        <div class="history-list">
          ${history.map(entry => `
            <div class="history-item">
              <div class="history-title">${entry.title}</div>
              <div class="history-url">${entry.url}</div>
              <div class="history-timestamp">${new Date(entry.timestamp * 1000).toLocaleString()}</div>
              <button onclick="protocolManager.navigateToUrl('${entry.url}')">Visit</button>
            </div>
          `).join('')}
        </div>
        <div class="history-actions">
          <button onclick="clearHistory()">Clear History</button>
        </div>
      </div>
    `;
    panel.style.display = 'block';
  });
}

function clearHistory(): void {
  invoke('clear_history').then(() => {
    const panel = document.getElementById('history-panel');
    if (panel) {
      panel.style.display = 'none';
    }
  });
}

// Initialize the application
async function initializeApp(): Promise<void> {
  // Set up event listeners
  const addressBar = document.getElementById('address-bar') as HTMLInputElement;
  if (addressBar) {
    addressBar.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        handleAddressBarSubmit();
      }
    });
  }

  // Initialize components
  await browserEngine.refreshTabs();
  await walletManager.getWalletInfo();
  await settingsManager.getSettings();

  // Create initial tab if none exist
  if (browserEngine.tabs.size === 0) {
    await browserEngine.createTab('about:blank');
  }

  // Listen for window events
  await listen('tauri://window-resized', () => {
    // Handle window resize
  });

  console.log('Decentralized Browser initialized');
}

// Make functions globally available
(window as any).browserEngine = browserEngine;
(window as any).protocolManager = protocolManager;
(window as any).securityManager = securityManager;
(window as any).walletManager = walletManager;
(window as any).settingsManager = settingsManager;
(window as any).handleAddressBarSubmit = handleAddressBarSubmit;
(window as any).handleBackButton = handleBackButton;
(window as any).handleForwardButton = handleForwardButton;
(window as any).handleRefreshButton = handleRefreshButton;
(window as any).toggleBookmark = toggleBookmark;
(window as any).showBookmarks = showBookmarks;
(window as any).removeBookmark = removeBookmark;
(window as any).showHistory = showHistory;
(window as any).clearHistory = clearHistory;

// Initialize when DOM is loaded
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initializeApp);
} else {
  initializeApp();
}

export {
  browserEngine,
  protocolManager,
  securityManager,
  walletManager,
  settingsManager,
  initializeApp
};
