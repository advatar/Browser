// Tauri v2 API imports
const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;
const { WebviewWindow } = window.__TAURI__.window;
const { open: openDialog, save: saveDialog } = window.__TAURI__.dialog;

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

interface UpdateStatusPayload {
  current_version: string;
  latest_version: string;
  update_available: boolean;
  release_notes?: string | null;
  download_url?: string | null;
  security_update: boolean;
  manifest_cid?: string | null;
  binary_cid?: string | null;
  binary_sha256?: string | null;
  binary_size?: number | null;
  release_notes_cid?: string | null;
  ipfs_uri?: string | null;
  checked_at: number;
  release_notes_text?: string | null;
  can_apply: boolean;
  applied_version?: string | null;
  apply_requires_restart: boolean;
}

interface ApplyUpdateSummary {
  new_version: string;
  target_path: string;
  backup_path?: string | null;
  requires_restart: boolean;
}

type NodePhase = 'Idle' | 'Starting' | 'Running' | 'Stopping';

interface NodeStatus {
  phase: NodePhase;
  active_tasks: number;
  last_error?: string | null;
}

interface AfmNodeConfig {
  router_url: string;
  registry_url: string;
  node_rpc_port: number;
  data_dir: string;
  enable_local_attestation: boolean;
}

interface AfmNodeSnapshot {
  config: AfmNodeConfig;
  status: NodeStatus;
}

type McpTransportKind = 'http' | 'websocket' | 'stdio';

interface McpSecretValue {
  isSecret: boolean;
  secretId?: string | null;
  preview?: string | null;
  value?: string | null;
}

type McpConfigValue = string | McpSecretValue;

interface McpServerConfig {
  id: string;
  name?: string | null;
  endpoint: string;
  enabled: boolean;
  headers: Record<string, McpConfigValue>;
  timeoutMs?: number | null;
  defaultCapability?: string | null;
  transport: McpTransportKind;
  program?: string | null;
  args: string[];
  env: Record<string, McpConfigValue>;
}

interface McpRuntimeStatus {
  state: 'Disabled' | 'Idle' | 'Connecting' | 'Ready' | 'Error';
  lastError?: string | null;
  lastUpdatedMs: number;
  lastLatencyMs?: number | null;
  successCount?: number;
  errorCount?: number;
  recentLogs?: McpLogEntry[];
}

interface ManagedMcpServer {
  config: McpServerConfig;
  status: McpRuntimeStatus;
}

interface McpProfileSummary {
  id: string;
  label: string;
  createdAt: number;
  updatedAt: number;
  serverCount: number;
  isActive: boolean;
}

interface McpProfileState {
  activeProfileId: string;
  profiles: McpProfileSummary[];
}

interface McpProfileUpdatePayload {
  profileState: McpProfileState;
  servers: ManagedMcpServer[];
}

type McpLogLevel = 'info' | 'warn' | 'error';

interface McpLogEntry {
  timestampMs: number;
  level: McpLogLevel;
  message: string;
}

interface EditableKeyValueEntry {
  id: string;
  key: string;
  value: string;
  isSecret: boolean;
  secretId?: string | null;
  preview?: string | null;
  dirty?: boolean;
  revealedValue?: string | null;
}

type EditableMcpServer = ManagedMcpServer & {
  headersList: EditableKeyValueEntry[];
  envList: EditableKeyValueEntry[];
};

interface AgentAppSummary {
  id: string;
  name: string;
  tagline: string;
  description: string;
  categories: string[];
  heroColor?: string | null;
  quickPrompts: string[];
  inputHint?: string | null;
  defaultInput?: string | null;
}

type AgentPlanStep = Record<string, unknown>;

interface AgentResultPayload {
  final_answer?: string | null;
  steps: AgentPlanStep[];
  halted: boolean;
}

interface AgentRunResponsePayload {
  agent: AgentResultPayload;
  tokens_used: number;
  skill_id?: string | null;
}

// Browser Engine Manager
class BrowserEngine {
  tabs: Map<string, Tab> = new Map();
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
    return invoke('get_tabs').then((tabs: unknown) => {
      (tabs as Tab[]).forEach((tab: Tab) => this.tabs.set(tab.id, tab));
      this.updateTabBar();
    });
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

  async addToHistory(url: string, title: string): Promise<void> {
    const entry = await invoke('add_to_history', { url, title });
    this.history.unshift(entry as HistoryEntry);
    this.updateHistoryUI();
  }

  private updateTabBar(): void {
    const tabBar = document.getElementById('tab-bar');
    if (!tabBar) return;

    tabBar.innerHTML = '';
    
    this.tabs.forEach((tab, id) => {
      const tabElement = document.createElement('div');
      tabElement.className = `tab ${id === this.activeTabId ? 'active' : ''}`;
      tabElement.textContent = tab.title || 'New Tab';
      tabElement.onclick = () => this.switchTab(id);
      tabBar.appendChild(tabElement);
    });

    // Add new tab button
    const newTabButton = document.createElement('div');
    newTabButton.className = 'new-tab-button';
    newTabButton.innerHTML = '+';
    newTabButton.onclick = () => this.createTab('about:home');
    tabBar.appendChild(newTabButton);
  }

  private updateHistoryUI(): void {
    const historyList = document.getElementById('history-list');
    if (!historyList) return;

    historyList.innerHTML = '';
    this.history.slice(0, 50).forEach(entry => {
      const li = document.createElement('li');
      const link = document.createElement('a');
      link.href = '#';
      link.textContent = entry.title || entry.url;
      link.onclick = (e) => {
        e.preventDefault();
        this.createTab(entry.url);
      };
      li.appendChild(link);
      historyList.appendChild(li);
    });
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
    this.securityStatus = await invoke('get_security_status', { url }) as SecurityStatus;
    this.updateSecurityIndicator();
    return this.securityStatus!;
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
    this.walletInfo = await invoke('get_wallet_info') as WalletInfo;
    this.updateWalletUI();
    return this.walletInfo!;
  }

  async connectWallet(): Promise<WalletInfo> {
    this.walletInfo = await invoke<WalletInfo>('connect_wallet');
    this.updateWalletUI();
    return this.walletInfo!;
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
  private mcpServers: EditableMcpServer[] = [];
  private mcpProfiles: McpProfileSummary[] = [];
  private activeProfileId: string | null = null;
  private mcpLoaded = false;
  private mcpEventsBound = false;
  private toastContainer: HTMLElement | null = null;
  private mcpErrorHashes: Map<string, string> = new Map();
  private readonly boundMcpInputHandler = (event: Event) => this.handleMcpInput(event);
  private readonly boundMcpClickHandler = (event: Event) => this.handleMcpClick(event as MouseEvent);

  async getSettings(): Promise<BrowserSettings> {
    this.settings = await invoke('get_settings') as BrowserSettings;
    return this.settings!;
  }

  private async ensureSettingsLoaded(): Promise<void> {
    if (!this.settings) {
      await this.getSettings();
    }
  }

  private async ensureMcpServersLoaded(): Promise<void> {
    if (!this.mcpLoaded) {
      await this.reloadMcpServers();
    }
  }

  async updateSettings(settings: BrowserSettings): Promise<void> {
    await invoke('update_settings', { settings });
    this.settings = settings;
  }

  async showSettingsPanel(): Promise<void> {
    const panel = document.getElementById('settings-panel');
    if (!panel) return;

    await Promise.all([this.ensureSettingsLoaded(), this.ensureMcpServersLoaded()]);
    panel.innerHTML = this.generateSettingsHTML();
    panel.style.display = 'block';
    this.toastContainer = panel.querySelector('#settings-toast-container');
    this.bindMcpEvents(panel);
  }

  private generateSettingsHTML(): string {
    if (!this.settings) return '';

    return `
      <div class="settings-content">
        <div id="settings-toast-container" class="settings-toast-container"></div>
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

        <div class="setting-group">
          <div class="mcp-heading">
            <div>
              <h3>Model Context Servers</h3>
              <p class="setting-hint">Enable/disable MCP transports, edit auth headers, and track status.</p>
              ${this.renderProfileControls()}
            </div>
            <div class="mcp-header-actions">
              <button type="button" data-action="add-server">Add Server</button>
              <button type="button" data-action="refresh-mcp">Reload Status</button>
              <button type="button" data-action="save-mcp" class="primary">Save Servers</button>
            </div>
          </div>
          <div id="mcp-server-section">
            ${this.renderMcpSection()}
          </div>
        </div>

        <div class="settings-actions">
          <button onclick="settingsManager.saveSettings()">Save</button>
          <button onclick="settingsManager.closeSettings()">Cancel</button>
        </div>
      </div>
    `;
  }

  private renderProfileControls(): string {
    const disabled = !this.mcpProfiles.length;
    const options = this.mcpProfiles.length
      ? this.mcpProfiles
          .map((profile) => {
            const selected = profile.id === this.activeProfileId ? 'selected' : '';
            const label = `${this.htmlEscape(profile.label)} (${profile.serverCount})`;
            return `<option value="${this.htmlEscape(profile.id)}" ${selected}>${label}</option>`;
          })
          .join('')
      : '<option value="">No profiles</option>';
    return `
      <div class="mcp-profile-bar">
        <label>
          Active Profile
          <select ${disabled ? 'disabled' : ''} data-profile-select="true">
            ${options}
          </select>
        </label>
        <div class="mcp-profile-actions">
          <button type="button" data-action="new-profile">New Profile</button>
          <button type="button" data-action="import-profile">Import</button>
          <button type="button" data-action="export-profile" ${disabled ? 'disabled' : ''}>Export</button>
        </div>
      </div>
    `;
  }

  private renderMcpSection(): string {
    if (!this.mcpServers.length) {
      return `<div class="mcp-empty-state">No MCP servers configured yet.</div>`;
    }
    return this.mcpServers
      .map((server, index) => this.renderMcpCard(server, index))
      .join('');
  }

  private renderMcpCard(server: EditableMcpServer, index: number): string {
    const transport = server.config.transport ?? 'http';
    const argsValue = server.config.args?.join(' ') ?? '';
    const timeout = server.config.timeoutMs ?? '';
    const updatedLabel = this.formatTimestamp(server.status.lastUpdatedMs);

    return `
      <div class="mcp-server-card" data-current-transport="${transport}">
        <div class="mcp-card-header">
          <div>
            <h4>${this.htmlEscape(server.config.name || server.config.id)}</h4>
            <p class="mcp-id">ID: ${this.htmlEscape(server.config.id)}</p>
          </div>
          <div class="mcp-card-status">
            <span class="mcp-status-pill ${server.status.state.toLowerCase()}">${server.status.state}</span>
            ${server.status.lastError ? `<span class="mcp-error">${this.htmlEscape(server.status.lastError)}</span>` : ''}
            <span class="mcp-updated">Updated ${updatedLabel}</span>
          </div>
        </div>
        <div class="mcp-grid">
          <label>
            Server ID
            <input type="text" data-mcp-index="${index}" data-mcp-field="id" value="${this.htmlEscape(server.config.id)}">
          </label>
          <label>
            Display Name
            <input type="text" data-mcp-index="${index}" data-mcp-field="name" value="${this.htmlEscape(server.config.name || '')}">
          </label>
          <label class="toggle checkbox-row">
            <input type="checkbox" data-mcp-index="${index}" data-mcp-field="enabled" ${server.config.enabled ? 'checked' : ''}>
            <span>Enabled</span>
          </label>
          <label>
            Transport
            <select data-mcp-index="${index}" data-mcp-field="transport">
              ${['http', 'websocket', 'stdio'].map(kind => `<option value="${kind}" ${transport === kind ? 'selected' : ''}>${kind.toUpperCase()}</option>`).join('')}
            </select>
          </label>
          <label>
            Endpoint / URL
            <input type="text" data-mcp-index="${index}" data-mcp-field="endpoint" value="${this.htmlEscape(server.config.endpoint)}" placeholder="${transport === 'stdio' ? 'Optional path (falls back to program)' : 'https://example.com/mcp'}">
          </label>
          <label>
            Timeout (ms)
            <input type="number" min="1000" step="500" data-mcp-index="${index}" data-mcp-field="timeoutMs" value="${timeout}">
          </label>
          <label>
            Default Capability
            <input type="text" data-mcp-index="${index}" data-mcp-field="defaultCapability" value="${this.htmlEscape(server.config.defaultCapability || '')}" placeholder="navigate">
          </label>
          ${this.renderTransportFields(transport, index, server, argsValue)}
        </div>
        ${this.renderMcpMetrics(server)}
        <div class="mcp-flex">
          <div class="mcp-kv-column">
            <div class="mcp-kv-header">
              <strong>Headers / Auth</strong>
              <button type="button" data-action="add-map-entry" data-map="headers" data-mcp-index="${index}">Add Header</button>
            </div>
            ${this.renderKeyValueEditor(server.headersList, 'headers', index)}
          </div>
          <div class="mcp-kv-column">
            <div class="mcp-kv-header">
              <strong>Environment</strong>
              <button type="button" data-action="add-map-entry" data-map="env" data-mcp-index="${index}">Add Variable</button>
            </div>
            ${this.renderKeyValueEditor(server.envList, 'env', index)}
          </div>
        </div>
        <div class="mcp-log-section">
          <div class="mcp-kv-header">
            <strong>Recent Activity</strong>
          </div>
          ${this.renderMcpLogs(server)}
        </div>
        <div class="mcp-card-footer">
          <div class="mcp-footer-actions">
            <button type="button" data-action="test-mcp" data-mcp-index="${index}">Test connection</button>
            <button type="button" data-action="remove-server" data-mcp-index="${index}">Delete Server</button>
          </div>
        </div>
      </div>
    `;
  }

  private renderTransportFields(
    transport: McpTransportKind,
    index: number,
    server: EditableMcpServer,
    argsValue: string
  ): string {
    if (transport === 'stdio') {
      return `
        <label>
          Program
          <input type="text" data-mcp-index="${index}" data-mcp-field="program" value="${this.htmlEscape(server.config.program || '')}" placeholder="/usr/local/bin/mcp-server">
        </label>
        <label>
          Arguments
          <input type="text" data-mcp-index="${index}" data-mcp-field="args" value="${this.htmlEscape(argsValue)}" placeholder="--port 7410 --mode prod">
        </label>
      `;
    }
    return '';
  }

  private renderKeyValueEditor(
    entries: EditableKeyValueEntry[],
    map: 'headers' | 'env',
    index: number
  ): string {
    if (!entries.length) {
      return `<p class="mcp-kv-empty">No entries yet.</p>`;
    }

    return entries
      .map(
        (entry) => {
          const value = entry.isSecret
            ? entry.revealedValue || entry.value || ''
            : entry.value;
          const placeholder = entry.isSecret
            ? entry.preview
              ? `Stored (${entry.preview})`
              : 'Enter secret'
            : 'Value';
          const inputType = entry.isSecret && !entry.revealedValue ? 'password' : 'text';
          const revealButton = entry.isSecret && entry.secretId
            ? `<button type="button" data-action="reveal-secret" data-map-type="${map}" data-map-entry="${entry.id}" data-mcp-index="${index}">${entry.revealedValue ? 'Hide' : 'Reveal'}</button>`
            : '';
          const preview = entry.isSecret && entry.preview
            ? `<span class="mcp-secret-preview">${this.htmlEscape(entry.preview)}</span>`
            : '';
          return `
        <div class="mcp-kv-row ${entry.isSecret ? 'is-secret' : ''}">
          <input
            type="text"
            placeholder="Key"
            value="${this.htmlEscape(entry.key)}"
            data-map-entry="${entry.id}"
            data-map-type="${map}"
            data-map-field="key"
            data-mcp-index="${index}"
          >
          <input
            type="${inputType}"
            placeholder="${this.htmlEscape(placeholder)}"
            value="${this.htmlEscape(value)}"
            data-map-entry="${entry.id}"
            data-map-type="${map}"
            data-map-field="value"
            data-mcp-index="${index}"
          >
          <div class="mcp-secret-actions">
            <button type="button" data-action="toggle-secret" data-map-type="${map}" data-map-entry="${entry.id}" data-mcp-index="${index}">${entry.isSecret ? 'Secret' : 'Plain'}</button>
            ${revealButton}
            <button type="button" data-action="remove-map-entry" data-map-type="${map}" data-map-entry="${entry.id}" data-mcp-index="${index}">✕</button>
          </div>
          ${preview}
        </div>
      `;
        }
      )
      .join('');
  }

  private renderMcpMetrics(server: EditableMcpServer): string {
    const latency = server.status.lastLatencyMs;
    const success = server.status.successCount ?? 0;
    const errors = server.status.errorCount ?? 0;
    return `
      <div class="mcp-metrics">
        <div class="mcp-metric">
          <span>Last Latency</span>
          <strong>${latency !== undefined && latency !== null ? `${latency} ms` : '—'}</strong>
        </div>
        <div class="mcp-metric">
          <span>Successes</span>
          <strong>${success}</strong>
        </div>
        <div class="mcp-metric">
          <span>Errors</span>
          <strong>${errors}</strong>
        </div>
      </div>
    `;
  }

  private renderMcpLogs(server: EditableMcpServer): string {
    const logs = server.status.recentLogs ?? [];
    if (!logs.length) {
      return `<p class="mcp-kv-empty">No recent activity yet.</p>`;
    }
    return `
      <div class="mcp-log-list">
        ${logs.slice(0, 3).map((log) => `
            <div class="mcp-log-entry ${log.level}">
              <div class="mcp-log-meta">
                <span class="mcp-log-level">${log.level.toUpperCase()}</span>
                <span class="mcp-log-time">${this.formatLogTimestamp(log.timestampMs)}</span>
              </div>
              <div class="mcp-log-message">${this.htmlEscape(log.message)}</div>
            </div>
        `).join('')}
      </div>
    `;
  }

  private formatTimestamp(ms: number): string {
    if (!ms) return 'never';
    const date = new Date(ms);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  private formatLogTimestamp(ms?: number): string {
    if (!ms) return '—';
    const date = new Date(ms);
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  private htmlEscape(value: string | number | null | undefined): string {
    if (value === undefined || value === null) return '';
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  private bindMcpEvents(panel: HTMLElement): void {
    if (this.mcpEventsBound) return;
    panel.addEventListener('input', this.boundMcpInputHandler);
    panel.addEventListener('change', this.boundMcpInputHandler);
    panel.addEventListener('click', this.boundMcpClickHandler);
    this.mcpEventsBound = true;
  }

  private handleMcpInput(event: Event): void {
    const target = event.target as HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | null;
    if (!target) return;
    if (target.getAttribute('data-profile-select') === 'true') {
      const value = (target as HTMLSelectElement).value;
      void this.handleProfileSelection(value);
      return;
    }
    const indexAttr = target.getAttribute('data-mcp-index');
    if (indexAttr === null) return;
    const index = Number(indexAttr);
    if (Number.isNaN(index) || !this.mcpServers[index]) return;

    const entryId = target.getAttribute('data-map-entry');
    const mapType = target.getAttribute('data-map-type') as 'headers' | 'env' | null;
    const mapField = target.getAttribute('data-map-field');
    if (entryId && mapType && mapField) {
      this.updateKeyValueEntry(index, mapType, entryId, mapField, target.value);
      return;
    }

    const field = target.getAttribute('data-mcp-field');
    if (!field) return;
    const value =
      target instanceof HTMLInputElement && target.type === 'checkbox'
        ? target.checked
        : target.value;
    this.updateServerField(index, field, value);
  }

  private handleMcpClick(event: MouseEvent): void {
    const element = (event.target as HTMLElement | null)?.closest('[data-action]') as HTMLElement | null;
    if (!element) return;
    const action = element.getAttribute('data-action');
    if (!action) return;
    event.preventDefault();

    const indexAttr = element.getAttribute('data-mcp-index');
    const index = indexAttr ? Number(indexAttr) : -1;

    switch (action) {
      case 'new-profile':
        void this.createProfileFlow();
        break;
      case 'import-profile':
        void this.importProfileFlow();
        break;
      case 'export-profile':
        void this.exportProfileFlow();
        break;
      case 'add-server':
        this.addServer();
        break;
      case 'remove-server':
        if (index >= 0) {
          this.removeServer(index);
        }
        break;
      case 'add-map-entry': {
        const map = element.getAttribute('data-map') as 'headers' | 'env' | null;
        if (map && index >= 0) {
          this.addMapEntry(index, map);
        }
        break;
      }
      case 'remove-map-entry': {
        const map = element.getAttribute('data-map-type') as 'headers' | 'env' | null;
        const entryId = element.getAttribute('data-map-entry');
        if (map && entryId && index >= 0) {
          this.removeMapEntry(index, entryId, map);
        }
        break;
      }
      case 'toggle-secret': {
        const map = element.getAttribute('data-map-type') as 'headers' | 'env' | null;
        const entryId = element.getAttribute('data-map-entry');
        if (map && entryId && index >= 0) {
          this.toggleSecretEntry(index, entryId, map);
        }
        break;
      }
      case 'reveal-secret': {
        const map = element.getAttribute('data-map-type') as 'headers' | 'env' | null;
        const entryId = element.getAttribute('data-map-entry');
        if (map && entryId && index >= 0) {
          void this.handleSecretReveal(index, entryId, map);
        }
        break;
      }
      case 'refresh-mcp':
        void this.reloadMcpServers();
        break;
      case 'save-mcp':
        void this.saveMcpServers();
        break;
      case 'test-mcp':
        void this.testMcpServer(index);
        break;
      default:
        break;
    }
  }

  private ensureToastContainer(): HTMLElement | null {
    if (this.toastContainer && document.body.contains(this.toastContainer)) {
      return this.toastContainer;
    }
    const panel = document.getElementById('settings-panel');
    if (!panel) return null;
    this.toastContainer = panel.querySelector('#settings-toast-container');
    return this.toastContainer;
  }

  private showToast(message: string, variant: 'info' | 'error' | 'success' = 'info'): void {
    const container = this.ensureToastContainer();
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `settings-toast settings-toast-${variant}`;
    toast.textContent = message;
    container.appendChild(toast);
    requestAnimationFrame(() => toast.classList.add('visible'));
    const timeout = window.setTimeout(() => {
      toast.classList.add('fade-out');
      window.setTimeout(() => toast.remove(), 300);
      window.clearTimeout(timeout);
    }, 4000);
  }

  private applyProfileState(state: McpProfileState): void {
    this.activeProfileId = state.activeProfileId;
    this.mcpProfiles = state.profiles || [];
  }

  private applyProfileUpdate(payload: McpProfileUpdatePayload): void {
    this.applyProfileState(payload.profileState);
    this.mcpServers = payload.servers.map((entry) => this.decorateServer(entry));
  }

  private async handleProfileSelection(profileId: string): Promise<void> {
    if (!profileId || profileId === this.activeProfileId) return;
    try {
      const payload = (await invoke('set_active_mcp_profile', { profileId })) as McpProfileUpdatePayload;
      this.applyProfilePayload(payload);
    } catch (error) {
      console.error('Failed to switch MCP profile', error);
      this.showToast('Failed to switch profile', 'error');
    }
  }

  private async createProfileFlow(): Promise<void> {
    const label = window.prompt('New profile name', 'New Profile');
    if (!label) return;
    try {
      const payload = (await invoke('create_mcp_profile', {
        label: label.trim(),
        makeActive: true,
      })) as McpProfileUpdatePayload;
      this.applyProfilePayload(payload);
    } catch (error) {
      console.error('Failed to create MCP profile', error);
      this.showToast('Failed to create profile', 'error');
    }
  }

  private async importProfileFlow(): Promise<void> {
    try {
      const selection = await openDialog({
        multiple: false,
        filters: [{ name: 'MCP Profile', extensions: ['json'] }],
      });
      const filePath = this.normalizeDialogSelection(selection);
      if (!filePath) return;
      const label = window.prompt('Profile label (optional)', 'Imported Profile');
      const payload = (await invoke('import_mcp_profile', {
        bundlePath: filePath,
        label: label?.trim() || null,
        makeActive: true,
      })) as McpProfileUpdatePayload;
      this.applyProfilePayload(payload);
      this.showToast('Profile imported', 'success');
    } catch (error) {
      console.error('Failed to import MCP profile', error);
      this.showToast('Failed to import profile', 'error');
    }
  }

  private async exportProfileFlow(): Promise<void> {
    if (!this.activeProfileId) {
      this.showToast('No active profile to export', 'error');
      return;
    }
    try {
      const defaultName = `mcp-profile-${this.activeProfileId}.json`;
      const targetPath = await saveDialog({
        defaultPath: defaultName,
        filters: [{ name: 'MCP Profile', extensions: ['json'] }],
      });
      if (!targetPath) return;
      await invoke('export_mcp_profile', {
        profileId: this.activeProfileId,
        targetPath,
      });
      this.showToast('Profile exported', 'success');
    } catch (error) {
      console.error('Failed to export MCP profile', error);
      this.showToast('Failed to export profile', 'error');
    }
  }

  private applyProfilePayload(payload: McpProfileUpdatePayload): void {
    this.applyProfileUpdate(payload);
    this.mcpLoaded = true;
    this.refreshMcpSection();
    this.notifyMcpStatusChanges(payload.servers);
  }

  private normalizeDialogSelection(selection: string | string[] | null): string | null {
    if (!selection) return null;
    if (Array.isArray(selection)) {
      return selection[0] || null;
    }
    return selection;
  }

  private notifyMcpStatusChanges(servers: ManagedMcpServer[]): void {
    servers.forEach((server) => {
      const key = server.config.id;
      const displayName = server.config.name || server.config.id;
      const latestError =
        server.status.recentLogs?.find((log) => log.level === 'error') ?? null;
      const signature = server.status.state === 'Error'
        ? `${latestError?.timestampMs ?? server.status.lastUpdatedMs}:${latestError?.message ?? server.status.lastError ?? ''}`
        : '';
      const previous = this.mcpErrorHashes.get(key) ?? '';

      if (signature && signature !== previous) {
        const message = latestError?.message || server.status.lastError || 'Unknown error';
        this.mcpErrorHashes.set(key, signature);
        this.showToast(`${displayName}: ${message}`, 'error');
      } else if (!signature && previous) {
        this.mcpErrorHashes.delete(key);
        this.showToast(`${displayName} recovered`, 'success');
      }
    });
  }

  private getMapList(server: EditableMcpServer, map: 'headers' | 'env'): EditableKeyValueEntry[] {
    return map === 'headers' ? server.headersList : server.envList;
  }

  private findMapEntry(
    index: number,
    entryId: string,
    map: 'headers' | 'env'
  ): EditableKeyValueEntry | null {
    const server = this.mcpServers[index];
    if (!server) return null;
    const list = this.getMapList(server, map);
    return list.find((item) => item.id === entryId) || null;
  }

  private updateServerField(index: number, field: string, rawValue: string | boolean): void {
    const server = this.mcpServers[index];
    if (!server) return;

    switch (field) {
      case 'enabled':
        server.config.enabled = Boolean(rawValue);
        break;
      case 'id':
        server.config.id = typeof rawValue === 'string' ? rawValue.trim() : '';
        break;
      case 'name':
        server.config.name = typeof rawValue === 'string' ? rawValue : '';
        break;
      case 'endpoint':
        server.config.endpoint = typeof rawValue === 'string' ? rawValue : '';
        break;
      case 'program':
        server.config.program = typeof rawValue === 'string' ? rawValue : '';
        break;
      case 'defaultCapability':
        server.config.defaultCapability =
          typeof rawValue === 'string' ? rawValue : undefined;
        break;
      case 'timeoutMs':
        server.config.timeoutMs =
          typeof rawValue === 'string' && rawValue.trim().length
            ? Number(rawValue)
            : undefined;
        break;
      case 'args': {
        const value = typeof rawValue === 'string' ? rawValue : '';
        server.config.args = value
          ? value
              .split(/[,\s]+/)
              .map((arg) => arg.trim())
              .filter(Boolean)
          : [];
        break;
      }
      case 'transport':
        server.config.transport = rawValue as McpTransportKind;
        this.refreshMcpSection();
        break;
      default:
        break;
    }
  }

  private updateKeyValueEntry(
    index: number,
    map: 'headers' | 'env',
    entryId: string,
    field: string,
    value: string
  ): void {
    const entry = this.findMapEntry(index, entryId, map);
    if (!entry) return;
    if (field === 'key') {
      entry.key = value;
    } else if (field === 'value') {
      entry.value = value;
      if (entry.isSecret) {
        entry.dirty = true;
        entry.revealedValue = null;
      }
    }
  }

  private addServer(): void {
    this.mcpServers.push(this.createEmptyServer());
    this.refreshMcpSection();
  }

  private removeServer(index: number): void {
    this.mcpServers.splice(index, 1);
    this.refreshMcpSection();
  }

  private addMapEntry(index: number, map: 'headers' | 'env'): void {
    const server = this.mcpServers[index];
    if (!server) return;
    const list = this.getMapList(server, map);
    list.push({ id: this.createEntryId(), key: '', value: '', isSecret: false });
    this.refreshMcpSection();
  }

  private removeMapEntry(index: number, entryId: string, map: 'headers' | 'env'): void {
    const server = this.mcpServers[index];
    if (!server) return;
    const list = this.getMapList(server, map);
    const idx = list.findIndex((entry) => entry.id === entryId);
    if (idx >= 0) {
      list.splice(idx, 1);
      this.refreshMcpSection();
    }
  }

  private toggleSecretEntry(index: number, entryId: string, map: 'headers' | 'env'): void {
    const entry = this.findMapEntry(index, entryId, map);
    if (!entry) return;
    entry.isSecret = !entry.isSecret;
    if (entry.isSecret) {
      entry.dirty = true;
    } else {
      entry.secretId = undefined;
      entry.preview = undefined;
      entry.dirty = false;
      entry.revealedValue = null;
    }
    this.refreshMcpSection();
  }

  private async handleSecretReveal(
    index: number,
    entryId: string,
    map: 'headers' | 'env'
  ): Promise<void> {
    const entry = this.findMapEntry(index, entryId, map);
    if (!entry || !entry.secretId) return;
    if (entry.revealedValue) {
      entry.revealedValue = null;
      this.refreshMcpSection();
      return;
    }
    try {
      const secret = (await invoke('read_mcp_secret', { secretId: entry.secretId })) as string;
      entry.revealedValue = secret;
      this.refreshMcpSection();
    } catch (error) {
      console.error('Failed to reveal secret', error);
      this.showToast('Failed to reveal secret', 'error');
    }
  }

  private refreshMcpSection(): void {
    const section = document.getElementById('mcp-server-section');
    if (section) {
      section.innerHTML = this.renderMcpSection();
    }
  }

  private decorateServer(server: ManagedMcpServer): EditableMcpServer {
    const headersList = this.mapToList(server.config.headers);
    const envList = this.mapToList(server.config.env);
    return {
      ...server,
      config: {
        ...server.config,
        headers: server.config.headers || {},
        env: server.config.env || {},
        args: server.config.args || [],
        transport: server.config.transport || 'http',
      },
      headersList,
      envList,
    };
  }

  private createEmptyServer(): EditableMcpServer {
    const timestamp = Date.now();
    const id = `server-${timestamp}`;
    return {
      config: {
        id,
        name: '',
        endpoint: '',
        enabled: false,
        headers: {},
        timeoutMs: 20000,
        defaultCapability: undefined,
        transport: 'http',
        program: '',
        args: [],
        env: {},
      },
      status: {
        state: 'Disabled',
        lastUpdatedMs: Date.now(),
        lastError: null,
      },
      headersList: [],
      envList: [],
    };
  }

  private mapToList(map?: Record<string, McpConfigValue>): EditableKeyValueEntry[] {
    const entries = Object.entries(map || {});
    return entries.map(([key, raw]) => {
      if (raw === null || raw === undefined || typeof raw === 'string') {
        return {
          id: this.createEntryId(),
          key,
          value: raw ?? '',
          isSecret: false,
        };
      }
      const secretValue = raw as McpSecretValue;
      return {
        id: this.createEntryId(),
        key,
        value: secretValue.value || '',
        isSecret: true,
        secretId: secretValue.secretId,
        preview: secretValue.preview,
        dirty: false,
        revealedValue: null,
      };
    });
  }

  private listToMap(entries: EditableKeyValueEntry[]): Record<string, McpConfigValue> {
    const result: Record<string, McpConfigValue> = {};
    entries.forEach((entry) => {
      const key = entry.key.trim();
      if (!key) return;
      if (entry.isSecret) {
        const payload: McpSecretValue = {
          isSecret: true,
        };
        if (entry.secretId) {
          payload.secretId = entry.secretId;
        }
        if (entry.preview) {
          payload.preview = entry.preview;
        }
        if (entry.dirty) {
          payload.value = entry.value;
        }
        result[key] = payload;
      } else {
        result[key] = entry.value;
      }
    });
    return result;
  }

  private createEntryId(): string {
    return Math.random().toString(36).slice(2, 9);
  }

  private prepareServersForSave(): McpServerConfig[] {
    return this.mcpServers.map((server) => ({
      ...server.config,
      headers: this.listToMap(server.headersList),
      env: this.listToMap(server.envList),
      args: server.config.args || [],
      defaultCapability:
        server.config.defaultCapability && server.config.defaultCapability.trim()
          ? server.config.defaultCapability.trim()
          : undefined,
      program: server.config.program?.trim()
        ? server.config.program
        : undefined,
    }));
  }

  private validateMcpServers(targetIndex?: number): string[] {
    const errors: string[] = [];
    const idCounts = new Map<string, number>();
    this.mcpServers.forEach((server) => {
      const id = (server.config.id || '').trim();
      if (id) {
        idCounts.set(id, (idCounts.get(id) || 0) + 1);
      }
    });

    this.mcpServers.forEach((server, index) => {
      if (typeof targetIndex === 'number' && targetIndex !== index) {
        return;
      }
      errors.push(...this.validateSingleMcpServer(server, index, idCounts));
    });
    return errors;
  }

  private validateSingleMcpServer(
    server: EditableMcpServer,
    index: number,
    idCounts: Map<string, number>
  ): string[] {
    const errors: string[] = [];
    const id = (server.config.id || '').trim();
    const label = this.formatServerLabel(server, index);
    const enabled = server.config.enabled !== false;
    if (!id) {
      errors.push(`${label}: Server ID is required`);
    } else if ((idCounts.get(id) || 0) > 1) {
      errors.push(`${label}: Duplicate server ID "${id}"`);
    }

    const transport = server.config.transport || 'http';
    const endpoint = (server.config.endpoint || '').trim();
    const program = (server.config.program || '').trim();
    if (enabled) {
      if ((transport === 'http' || transport === 'websocket') && !endpoint) {
        errors.push(`${label}: Endpoint is required for ${transport.toUpperCase()} servers`);
      }
      if (transport === 'stdio' && !program && !endpoint) {
        errors.push(`${label}: Provide a program path or endpoint for STDIO servers`);
      }
    }

    const checkSecrets = (entries: EditableKeyValueEntry[], scope: string): void => {
      entries.forEach((entry) => {
        const key = (entry.key || '').trim();
        const value = (entry.value || '').trim();
        const revealed = (entry.revealedValue || '').trim();
        const hasKey = key.length > 0;
        const hasValue = value.length > 0 || revealed.length > 0;
        const hasId = Boolean(entry.secretId && entry.secretId.trim().length > 0);
        if (!hasKey && (hasValue || entry.isSecret)) {
          errors.push(`${label}: ${scope} entry is missing a key`);
        }
        if (entry.isSecret && !hasId && !hasValue) {
          errors.push(`${label}: ${scope} "${key || 'secret'}" requires a secret value`);
        }
      });
    };

    checkSecrets(server.headersList, 'Header');
    checkSecrets(server.envList, 'Env variable');

    if (server.config.timeoutMs && server.config.timeoutMs < 500) {
      errors.push(`${label}: Timeout must be at least 500ms`);
    }

    return errors;
  }

  private formatServerLabel(server: EditableMcpServer, index: number): string {
    return server.config.name || server.config.id || `Server ${index + 1}`;
  }

  async reloadMcpServers(): Promise<void> {
    await this.refreshMcpData();
  }

  private async refreshMcpData(): Promise<void> {
    try {
      const [servers, profileState] = await Promise.all([
        invoke('list_mcp_servers') as Promise<ManagedMcpServer[]>,
        invoke('list_mcp_profiles') as Promise<McpProfileState>,
      ]);
      this.mcpServers = servers.map((entry) => this.decorateServer(entry));
      this.applyProfileState(profileState);
      this.mcpLoaded = true;
      this.refreshMcpSection();
      this.notifyMcpStatusChanges(servers);
    } catch (error) {
      console.error('Failed to load MCP context', error);
    }
  }

  private async refreshProfileState(): Promise<void> {
    try {
      const profileState = (await invoke('list_mcp_profiles')) as McpProfileState;
      this.applyProfileState(profileState);
    } catch (error) {
      console.error('Failed to refresh MCP profiles', error);
    }
  }

  async saveMcpServers(): Promise<void> {
    try {
      const errors = this.validateMcpServers();
      if (errors.length) {
        errors.forEach((msg) => this.showToast(msg, 'error'));
        return;
      }
      const payload = this.prepareServersForSave();
      const updated = (await invoke('save_mcp_servers', { servers: payload })) as ManagedMcpServer[];
      this.mcpServers = updated.map((entry) => this.decorateServer(entry));
      await this.refreshProfileState();
      this.refreshMcpSection();
      this.notifyMcpStatusChanges(updated);
    } catch (error) {
      console.error('Failed to save MCP servers', error);
    }
  }

  private async testMcpServer(index: number): Promise<void> {
    const server = this.mcpServers[index];
    if (!server) return;
    const errors = this.validateMcpServers(index);
    if (errors.length) {
      errors.forEach((msg) => this.showToast(msg, 'error'));
      return;
    }
    const payload = this.prepareServersForSave()[index];
    if (!payload) return;

    const displayName = this.formatServerLabel(server, index);
    this.mcpServers[index].status = {
      ...server.status,
      state: payload.enabled ? 'Connecting' : 'Disabled',
      lastUpdatedMs: Date.now(),
    };
    this.refreshMcpSection();

    try {
      const status = (await invoke('test_mcp_server', { server: payload })) as McpRuntimeStatus;
      this.mcpServers[index].status = {
        ...status,
        recentLogs: status.recentLogs ?? server.status.recentLogs ?? [],
      };
      this.refreshMcpSection();
      const variant =
        status.state === 'Ready' ? 'success' : status.state === 'Disabled' ? 'info' : 'error';
      const message =
        status.state === 'Ready'
          ? `${displayName} is reachable`
          : status.state === 'Disabled'
            ? `${displayName} is disabled`
            : `${displayName} failed: ${status.lastError || 'see logs'}`;
      this.showToast(message, variant);
      this.notifyMcpStatusChanges([this.mcpServers[index]]);
    } catch (error) {
      console.error('Failed to test MCP server', error);
      this.mcpServers[index].status = {
        ...server.status,
        state: 'Error',
        lastError: error instanceof Error ? error.message : String(error),
        lastUpdatedMs: Date.now(),
      };
      this.refreshMcpSection();
      this.showToast('Test failed', 'error');
    }
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
    this.toastContainer = null;
  }
}

class AppLauncher {
  private panel: HTMLElement | null = null;
  private listEl: HTMLElement | null = null;
  private resultEl: HTMLElement | null = null;
  private toggleButton: HTMLButtonElement | null = null;
  private closeButton: HTMLButtonElement | null = null;
  private apps: AgentAppSummary[] = [];

  async initialize(): Promise<void> {
    this.cacheDom();
    this.bindEvents();
    await this.loadApps();
  }

  private cacheDom(): void {
    this.panel = document.getElementById('apps-panel');
    this.listEl = document.getElementById('apps-list');
    this.resultEl = document.getElementById('apps-run-output');
    this.toggleButton = document.getElementById('apps-button') as HTMLButtonElement | null;
    this.closeButton = document.getElementById('apps-close') as HTMLButtonElement | null;
  }

  private bindEvents(): void {
    this.toggleButton?.addEventListener('click', () => this.toggle());
    this.closeButton?.addEventListener('click', () => this.toggle(false));
    this.panel?.addEventListener('click', (event) => this.handlePanelClick(event));
  }

  private async loadApps(): Promise<void> {
    try {
      this.apps = (await invoke('list_agent_apps')) as AgentAppSummary[];
      this.renderList();
    } catch (error) {
      console.error('Failed to load agent apps', error);
      if (this.listEl) {
        this.listEl.innerHTML = '<p class="mcp-kv-empty">Unable to load agent apps.</p>';
      }
    }
  }

  private toggle(force?: boolean): void {
    if (!this.panel) return;
    const shouldOpen = typeof force === 'boolean' ? force : !this.panel.classList.contains('open');
    this.panel.classList.toggle('open', shouldOpen);
  }

  private handlePanelClick(event: MouseEvent): void {
    const target = (event.target as HTMLElement | null)?.closest('[data-action]') as HTMLElement | null;
    if (!target) return;
    const action = target.getAttribute('data-action');
    const appId = target.getAttribute('data-app-id');
    if (!action || !appId) return;
    const app = this.apps.find((item) => item.id === appId);
    if (!app) return;

    if (action === 'launch-app') {
      const prompt = this.getInputValue(appId);
      void this.launchApp(app, prompt);
    } else if (action === 'quick-prompt') {
      const prompt = target.getAttribute('data-prompt') || '';
      this.setInputValue(appId, prompt);
      void this.launchApp(app, prompt);
    }
  }

  private renderList(): void {
    if (!this.listEl) return;
    if (!this.apps.length) {
      this.listEl.innerHTML = '<p class="mcp-kv-empty">No agent apps configured yet.</p>';
      return;
    }
    this.listEl.innerHTML = this.apps.map((app) => this.renderCard(app)).join('');
  }

  private renderCard(app: AgentAppSummary): string {
    const quickPrompts = app.quickPrompts
      .map(
        (prompt) => `
        <button type="button" data-action="quick-prompt" data-app-id="${app.id}" data-prompt="${this.htmlEscape(prompt)}">
          ${this.htmlEscape(prompt)}
        </button>
      `,
      )
      .join('');
    const chips = app.categories
      .map((category) => `<span class="mcp-status-pill">${this.htmlEscape(category)}</span>`)
      .join('');
    const placeholder = app.inputHint || 'Describe what you need';
    const defaultValue = app.defaultInput || '';

    return `
      <article class="app-card" data-app-id="${app.id}" style="border-top: 3px solid ${app.heroColor || '#0f172a'}">
        <h4>${this.htmlEscape(app.name)}</h4>
        <small>${this.htmlEscape(app.tagline)}</small>
        <p>${this.htmlEscape(app.description)}</p>
        <div class="app-tags">${chips}</div>
        <textarea data-app-input="${app.id}" placeholder="${this.htmlEscape(placeholder)}">${this.htmlEscape(defaultValue)}</textarea>
        <div class="app-quick-prompts">
          ${quickPrompts}
        </div>
        <footer>
          <button type="button" data-action="launch-app" data-app-id="${app.id}">Launch</button>
        </footer>
      </article>
    `;
  }

  private getInputValue(appId: string): string {
    const card = this.panel?.querySelector<HTMLElement>(`.app-card[data-app-id="${appId}"]`);
    const input = card?.querySelector<HTMLTextAreaElement>('textarea[data-app-input]');
    return input?.value || '';
  }

  private setInputValue(appId: string, value: string): void {
    const card = this.panel?.querySelector<HTMLElement>(`.app-card[data-app-id="${appId}"]`);
    const input = card?.querySelector<HTMLTextAreaElement>('textarea[data-app-input]');
    if (input) {
      input.value = value;
    }
  }

  private setCardBusy(appId: string, busy: boolean): void {
    const card = this.panel?.querySelector<HTMLElement>(`.app-card[data-app-id="${appId}"]`);
    if (card) {
      card.dataset.busy = busy ? 'true' : 'false';
    }
  }

  private async launchApp(app: AgentAppSummary, input?: string): Promise<void> {
    try {
      this.setCardBusy(app.id, true);
      const payload = (input || '').trim() || null;
      const response = (await invoke('launch_agent_app', {
        request: {
          appId: app.id,
          input: payload,
        },
      })) as AgentRunResponsePayload;
      this.showResult(app, response);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.showResult(app, null, message);
      console.error('Agent app failed', error);
    } finally {
      this.setCardBusy(app.id, false);
    }
  }

  private showResult(app: AgentAppSummary, response: AgentRunResponsePayload | null, error?: string): void {
    if (!this.resultEl) return;
    if (error || !response) {
      this.resultEl.innerHTML = `
        <h5>${this.htmlEscape(app.name)}</h5>
        <p style="color: #b42318;">${this.htmlEscape(error || 'Unknown error')}</p>
      `;
      return;
    }
    const answer = response.agent?.final_answer?.trim() || 'No final answer returned.';
    this.resultEl.innerHTML = `
      <h5>${this.htmlEscape(app.name)}</h5>
      <p>${this.htmlEscape(answer)}</p>
      <small style="color:#475467;">${response.tokens_used} tokens • ${new Date().toLocaleTimeString()}</small>
    `;
  }

  private htmlEscape(value: string): string {
    const div = document.createElement('div');
    div.textContent = value;
    return div.innerHTML;
  }
}

class AfmNodePanel {
  private container: HTMLElement | null = null;
  private phaseEl: HTMLElement | null = null;
  private routerEl: HTMLElement | null = null;
  private registryEl: HTMLElement | null = null;
  private dataDirEl: HTMLElement | null = null;
  private tasksEl: HTMLElement | null = null;
  private attestationEl: HTMLElement | null = null;
  private lastErrorEl: HTMLElement | null = null;
  private alertEl: HTMLElement | null = null;
  private startStopButton: HTMLButtonElement | null = null;
  private refreshButton: HTMLButtonElement | null = null;
  private submitTaskButton: HTMLButtonElement | null = null;
  private gossipButton: HTMLButtonElement | null = null;
  private taskTextarea: HTMLTextAreaElement | null = null;
  private gossipTopicInput: HTMLInputElement | null = null;
  private gossipPayloadInput: HTMLTextAreaElement | null = null;
  private toggleButton: HTMLButtonElement | null = null;
  private snapshot: AfmNodeSnapshot | null = null;
  private unlisten: (() => void) | null = null;

  async initialize(): Promise<void> {
    this.cacheDom();
    if (!this.container) return;
    this.bindEvents();
    await this.refresh();
    this.unlisten = await listen('afm-node-status', ({ payload }) => {
      if (payload) {
        this.render(payload as AfmNodeSnapshot);
      }
    });
  }

  private cacheDom(): void {
    this.container = document.getElementById('afm-panel');
    this.phaseEl = document.getElementById('afm-phase');
    this.routerEl = document.getElementById('afm-router-url');
    this.registryEl = document.getElementById('afm-registry-url');
    this.dataDirEl = document.getElementById('afm-data-dir');
    this.tasksEl = document.getElementById('afm-active-tasks');
    this.attestationEl = document.getElementById('afm-attestation-mode');
    this.lastErrorEl = document.getElementById('afm-last-error');
    this.alertEl = document.getElementById('afm-alert');
    this.startStopButton = document.getElementById('afm-start-stop') as HTMLButtonElement | null;
    this.refreshButton = document.getElementById('afm-refresh') as HTMLButtonElement | null;
    this.submitTaskButton = document.getElementById('afm-submit-task') as HTMLButtonElement | null;
    this.gossipButton = document.getElementById('afm-send-gossip') as HTMLButtonElement | null;
    this.taskTextarea = document.getElementById('afm-task-json') as HTMLTextAreaElement | null;
    this.gossipTopicInput = document.getElementById('afm-gossip-topic') as HTMLInputElement | null;
    this.gossipPayloadInput = document.getElementById('afm-gossip-payload') as HTMLTextAreaElement | null;
    this.toggleButton = document.getElementById('afm-toggle-panel') as HTMLButtonElement | null;
  }

  private bindEvents(): void {
    this.startStopButton?.addEventListener('click', () => this.toggleStartStop());
    this.refreshButton?.addEventListener('click', () => this.refresh());
    this.submitTaskButton?.addEventListener('click', () => this.submitTask());
    this.gossipButton?.addEventListener('click', () => this.sendGossip());
    this.toggleButton?.addEventListener('click', () => this.toggleCollapse());
  }

  private toggleCollapse(): void {
    if (!this.container || !this.toggleButton) return;
    this.container.classList.toggle('collapsed');
    const collapsed = this.container.classList.contains('collapsed');
    this.toggleButton.textContent = collapsed ? '▾' : '▴';
  }

  private async toggleStartStop(): Promise<void> {
    if (!this.startStopButton) return;
    const running = this.isRunning();
    this.setBusy(this.startStopButton, true);
    try {
      if (running) {
        const snapshot = await invoke<AfmNodeSnapshot>('stop_afm_node');
        this.render(snapshot);
        this.setAlert('AFM node stopped', 'success');
      } else {
        const snapshot = await invoke<AfmNodeSnapshot>('start_afm_node');
        this.render(snapshot);
        this.setAlert('AFM node starting…', 'info');
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.setAlert(`AFM action failed: ${message}`, 'error');
    } finally {
      this.setBusy(this.startStopButton, false);
    }
  }

  private setBusy(button: HTMLButtonElement | null, busy: boolean): void {
    if (!button) return;
    if (busy) {
      button.dataset.originalText = button.textContent ?? '';
      button.textContent = 'Working…';
      button.disabled = true;
    } else {
      button.disabled = false;
      if (this.snapshot) {
        button.textContent = this.isRunning() ? 'Stop Node' : 'Start Node';
      } else {
        button.textContent = button.dataset.originalText ?? 'Start Node';
      }
    }
  }

  private async refresh(): Promise<void> {
    try {
      const snapshot = await invoke<AfmNodeSnapshot>('afm_node_status');
      this.render(snapshot);
      this.setAlert('AFM status refreshed', 'info');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.setAlert(`Failed to load AFM status: ${message}`, 'error');
    }
  }

  private render(snapshot: AfmNodeSnapshot): void {
    this.snapshot = snapshot;
    const status = snapshot.status;
    const config = snapshot.config;
    if (this.phaseEl) {
      const phase = status.phase.toLowerCase();
      this.phaseEl.textContent = status.phase;
      this.phaseEl.className = `afm-phase ${phase}`;
    }
    if (this.routerEl) this.routerEl.textContent = config.router_url;
    if (this.registryEl) this.registryEl.textContent = config.registry_url;
    if (this.dataDirEl) this.dataDirEl.textContent = config.data_dir;
    if (this.tasksEl) this.tasksEl.textContent = status.active_tasks.toString();
    if (this.attestationEl) {
      this.attestationEl.textContent = config.enable_local_attestation ? 'Local' : 'Remote';
    }
    if (this.lastErrorEl) {
      this.lastErrorEl.textContent = status.last_error || 'None';
    }
    if (this.startStopButton) {
      const running = this.isRunning();
      this.startStopButton.textContent = running ? 'Stop Node' : 'Start Node';
    }
  }

  private isRunning(): boolean {
    if (!this.snapshot) return false;
    const phase = this.snapshot.status.phase;
    return phase === 'Running' || phase === 'Starting';
  }

  private async submitTask(): Promise<void> {
    if (!this.taskTextarea) return;
    const raw = this.taskTextarea.value.trim() || '{}';
    try {
      const payload = JSON.parse(raw);
      await invoke('afm_submit_task', { request: { payload } });
      this.setAlert('Task submitted', 'success');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.setAlert(`Task submission failed: ${message}`, 'error');
    }
  }

  private async sendGossip(): Promise<void> {
    if (!this.gossipTopicInput || !this.gossipPayloadInput) return;
    const topic = (this.gossipTopicInput.value || 'status').trim();
    const payloadText = this.gossipPayloadInput.value || '';
    if (!payloadText) {
      this.setAlert('Enter gossip payload text', 'error');
      return;
    }
    const payloadB64 = this.encodeToBase64(payloadText);
    try {
      await invoke('afm_feed_gossip', {
        request: {
          topic,
          payloadB64,
        },
      });
      this.setAlert('Gossip frame sent', 'success');
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.setAlert(`Gossip failed: ${message}`, 'error');
    }
  }

  private encodeToBase64(text: string): string {
    if (typeof TextEncoder !== 'undefined') {
      const bytes = new TextEncoder().encode(text);
      let binary = '';
      bytes.forEach((b) => {
        binary += String.fromCharCode(b);
      });
      return window.btoa(binary);
    }
    const encoded = encodeURIComponent(text).replace(/%([0-9A-F]{2})/g, (_substring, hex) => {
      return String.fromCharCode(parseInt(hex, 16));
    });
    return window.btoa(encoded);
  }

  private setAlert(message: string, variant: 'info' | 'error' | 'success' = 'info'): void {
    if (!this.alertEl) return;
    this.alertEl.textContent = message;
    this.alertEl.className = `afm-alert ${variant}`;
  }
}

// Global instances
const browserEngine = new BrowserEngine();
const protocolManager = new ProtocolManager();
const securityManager = new SecurityManager();
const walletManager = new WalletManager();
const settingsManager = new SettingsManager();
const afmNodePanel = new AfmNodePanel();
const appLauncher = new AppLauncher();

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

const UPDATE_BANNER_ID = 'update-banner';
let currentUpdateInfo: UpdateStatusPayload | null = null;

function removeUpdateBanner(): void {
  const banner = document.getElementById(UPDATE_BANNER_ID);
  if (banner) {
    banner.remove();
  }
}

function formatUpdateSize(bytes?: number | null): string {
  if (!bytes || bytes <= 0) return '';
  const megabytes = bytes / (1024 * 1024);
  return ` (~${megabytes.toFixed(1)} MB)`;
}

function escapeHtml(value: string): string {
  const div = document.createElement('div');
  div.textContent = value;
  return div.innerHTML;
}

function renderUpdateBanner(info: UpdateStatusPayload): void {
  let banner = document.getElementById(UPDATE_BANNER_ID);

  if (!info.update_available) {
    if (info.applied_version && info.apply_requires_restart) {
      if (!banner) {
        banner = document.createElement('div');
        banner.id = UPDATE_BANNER_ID;
        document.body.appendChild(banner);
      }

      const style = banner.style;
      style.position = 'fixed';
      style.bottom = '24px';
      style.right = '24px';
      style.backgroundColor = '#0f766e';
      style.color = '#ffffff';
      style.padding = '16px';
      style.borderRadius = '12px';
      style.boxShadow = '0 8px 24px rgba(0, 0, 0, 0.2)';
      style.maxWidth = '360px';
      style.zIndex = '9999';
      style.fontFamily = 'system-ui, sans-serif';

      banner.innerHTML = `
        <div class="update-banner-content">
          <div style="font-weight: 600; font-size: 16px; margin-bottom: 6px;">
            Update v${escapeHtml(info.applied_version)} installed
          </div>
          <div style="font-size: 14px; margin-bottom: 12px;">
            Restart the application to finish applying the update.
          </div>
          <div style="display: flex; gap: 8px; justify-content: flex-end;">
            <button id="update-dismiss-button" style="
                background-color: rgba(0,0,0,0.15);
                color: #fff;
                border: none;
                border-radius: 999px;
                padding: 6px 14px;
                cursor: pointer;
                font-size: 13px;
            ">Dismiss</button>
          </div>
        </div>
      `;

      const dismissButton = document.getElementById('update-dismiss-button');
      if (dismissButton) {
        dismissButton.onclick = () => removeUpdateBanner();
      }
    } else {
      removeUpdateBanner();
    }
    currentUpdateInfo = info;
    return;
  }

  if (!banner) {
    banner = document.createElement('div');
    banner.id = UPDATE_BANNER_ID;
    document.body.appendChild(banner);
  }

  const isSecurity = !!info.security_update;
  const style = banner.style;
  style.position = 'fixed';
  style.bottom = '24px';
  style.right = '24px';
  style.backgroundColor = isSecurity ? '#b91c1c' : '#1d4ed8';
  style.color = '#ffffff';
  style.padding = '16px';
  style.borderRadius = '12px';
  style.boxShadow = '0 8px 24px rgba(0, 0, 0, 0.2)';
  style.maxWidth = '360px';
  style.zIndex = '9999';
  style.fontFamily = 'system-ui, sans-serif';

  const sizeText = formatUpdateSize(info.binary_size ?? null);
  const actions: string[] = [];

  if (info.can_apply) {
    actions.push(`<button id="update-install-button" style="
        background-color: rgba(255,255,255,0.9);
        color: ${isSecurity ? '#b91c1c' : '#1d4ed8'};
        border: none;
        border-radius: 999px;
        padding: 6px 14px;
        cursor: pointer;
        font-size: 13px;
        font-weight: 600;
    ">Install update</button>`);
  }

  if (info.download_url || info.ipfs_uri) {
    actions.push(`<button id="update-download-button" style="
        background-color: rgba(255,255,255,0.15);
        color: #fff;
        border: none;
        border-radius: 999px;
        padding: 6px 14px;
        cursor: pointer;
        font-size: 13px;
    ">Download</button>`);
  }

  actions.push(`<button id="update-dismiss-button" style="
        background-color: rgba(0,0,0,0.15);
        color: #fff;
        border: none;
        border-radius: 999px;
        padding: 6px 14px;
        cursor: pointer;
        font-size: 13px;
    ">Dismiss</button>`);

  const releaseNotesSection = info.release_notes_text
    ? `<details class="update-notes" style="margin-top: 10px;">
          <summary style="cursor: pointer; font-size: 13px;">Release notes</summary>
          <pre style="margin-top: 6px; max-height: 180px; overflow-y: auto; white-space: pre-wrap; font-family: inherit;">${escapeHtml(info.release_notes_text)}</pre>
       </details>`
    : '';

  const releaseNotesLink = !info.release_notes_text && info.release_notes
    ? `<div style="font-size: 13px; margin-bottom: 6px;"><a href="${encodeURI(info.release_notes)}" target="_blank" rel="noreferrer" style="color: #e0f2fe;">View release notes</a></div>`
    : '';

  banner.innerHTML = `
    <div class="update-banner-content">
      <div style="font-weight: 600; font-size: 16px; margin-bottom: 6px;">
        ${isSecurity ? 'Security update available' : 'Update available'} · v${escapeHtml(info.latest_version)}
      </div>
      <div style="font-size: 14px; margin-bottom: 10px;">
        You are running v${escapeHtml(info.current_version)}${sizeText}.
      </div>
      ${releaseNotesLink}
      ${releaseNotesSection}
      <div style="display: flex; gap: 8px; justify-content: flex-end; margin-top: 12px;">
        ${actions.join('')}
      </div>
    </div>
  `;

  const dismissButton = document.getElementById('update-dismiss-button');
  if (dismissButton) {
    dismissButton.onclick = () => removeUpdateBanner();
  }

  const downloadButton = document.getElementById('update-download-button');
  if (downloadButton) {
    downloadButton.onclick = () => {
      const target = info.download_url ?? info.ipfs_uri;
      if (target) {
        window.open(target, '_blank');
      } else {
        console.warn('No download target available for update');
      }
    };
  }

  const installButton = document.getElementById('update-install-button') as HTMLButtonElement | null;
  if (installButton) {
    installButton.onclick = () => applyPendingUpdate(installButton);
  }

  currentUpdateInfo = info;
}

function handleUpdateStatusEvent(info: UpdateStatusPayload): void {
  currentUpdateInfo = info;
  renderUpdateBanner(info);
}

async function applyPendingUpdate(button?: HTMLButtonElement): Promise<void> {
  if (button) {
    button.dataset.originalText = button.textContent ?? 'Install update';
    button.disabled = true;
    button.textContent = 'Installing...';
  }

  try {
    const summary = await invoke<ApplyUpdateSummary>('apply_update');
    console.info('Update applied', summary);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('Update install failed:', error);
    if (button) {
      button.disabled = false;
      button.textContent = button.dataset.originalText ?? 'Install update';
    }
    window.alert(`Failed to install update: ${message}`);
  }
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
  await appLauncher.initialize();
  await afmNodePanel.initialize();

  // Wallet button click: toggle connect/disconnect
  const walletButton = document.getElementById('wallet-button') as HTMLButtonElement | null;
  if (walletButton) {
    walletButton.addEventListener('click', async () => {
      try {
        const info = await walletManager.getWalletInfo();
        if (info && info.is_connected) {
          await walletManager.disconnectWallet();
        } else {
          await walletManager.connectWallet();
        }
      } catch (err) {
        console.error('Wallet action failed:', err);
      }
    });
  }

  const unlistenUpdate = await listen('update-status', ({ payload }) => {
    if (payload) {
      handleUpdateStatusEvent(payload as UpdateStatusPayload);
    }
  });
  (window as any).unlistenUpdateStatus = unlistenUpdate;

  const unlistenUpdateApplied = await listen('update-applied', ({ payload }) => {
    if (payload) {
      console.info('Update applied event', payload as ApplyUpdateSummary);
    }
  });
  (window as any).unlistenUpdateApplied = unlistenUpdateApplied;

  invoke('check_for_updates').catch((err) => {
    console.error('Update check failed:', err);
  });

  // Create initial tab if none exist
  if (browserEngine.tabs.size === 0) {
    await browserEngine.createTab('about:home');
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
(window as any).afmNodePanel = afmNodePanel;
(window as any).appLauncher = appLauncher;
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
  afmNodePanel,
  appLauncher,
  initializeApp
};
listen('agent://approval-request', async ({ payload }) => {
  try {
    const data = typeof payload === 'string' ? JSON.parse(payload) : payload;
    if (!data || !data.id) {
      return;
    }
    const approved = window.confirm(
      `Agent requests capability "${data.capability}". Approve?`
    );
    await invoke('agent_resolve_approval', {
      requestId: data.id,
      approved,
    });
  } catch (err) {
    console.error('Approval dialog failed:', err);
  }
});
