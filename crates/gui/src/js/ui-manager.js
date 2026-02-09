import { debounce, getFaviconUrl, isValidUrl, normalizeUrl } from './utils.js';

import { HistoryManager } from './history-manager.js';
import { HistoryPanel } from './history-panel.js';
import { BookmarkManager } from '../features/bookmarks';
import { BookmarksPanel } from './bookmarks-panel.js';
import { DownloadsPanel } from './downloads-panel.js';

export class UIManager {
  constructor(tabManager, navigationManager) {
    this.tabManager = tabManager;
    this.navigationManager = navigationManager;
    
    // UI Elements
    this.addressBar = document.getElementById('address-bar');
    this.menuButton = document.getElementById('menu-button');
    this.bookmarksButton = document.getElementById('bookmarks-button');
    this.historyButton = document.getElementById('history-button');
    this.downloadsButton = document.getElementById('downloads-button');
    this.settingsButton = document.getElementById('settings-button');
    this.walletButton = document.getElementById('wallet-button');
    this.backButton = document.getElementById('back');
    this.forwardButton = document.getElementById('forward');
    this.reloadButton = document.getElementById('reload');
    this.homeButton = document.getElementById('home');
    
    // Wallet state
    this.walletInfo = null;
    this.invoke = (window.__TAURI__ && window.__TAURI__.core && window.__TAURI__.core.invoke) ? window.__TAURI__.core.invoke : null;
    
    // Initialize history management
    this.eventBus = this.createEventBus();
    this.historyManager = new HistoryManager(this.eventBus);
    this.historyPanel = new HistoryPanel(this.historyManager, this.eventBus);
    this.bookmarkManager = new BookmarkManager(this.eventBus);
    this.bookmarksPanel = new BookmarksPanel(this.bookmarkManager, this.eventBus);
    this.downloadsPanel = new DownloadsPanel(this.eventBus);
    this.suggestions = [];
    this.suggestionIndex = -1;
    this.suggestionsElement = this.createSuggestionsElement();
    
    this.setupEventListeners();
    this.setupContextMenu();
    this.setupHistoryIntegration();

    // Initialize wallet UI if available
    this.initializeWalletUI();
  }
  
  setupEventListeners() {
    // New tab button
    const newTabBtn = document.getElementById('new-tab');
    if (newTabBtn) {
      newTabBtn.addEventListener('click', () => this.tabManager.createTab());
    }

    // New group button
    const newGroupBtn = document.getElementById('new-group');
    if (newGroupBtn) {
      newGroupBtn.addEventListener('click', () => this.createNewGroup());
    }

    // Address bar events
    const addressBar = document.getElementById('address-bar');
    if (addressBar) {
      addressBar.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowDown') {
          if (this.suggestions.length > 0) {
            e.preventDefault();
            this.setSuggestionIndex(Math.min(this.suggestionIndex + 1, this.suggestions.length - 1));
          }
          return;
        }
        if (e.key === 'ArrowUp') {
          if (this.suggestions.length > 0) {
            e.preventDefault();
            this.setSuggestionIndex(Math.max(this.suggestionIndex - 1, 0));
          }
          return;
        }
        if (e.key === 'Enter') {
          if (this.suggestions.length > 0 && this.suggestionIndex >= 0) {
            e.preventDefault();
            const selected = this.suggestions[this.suggestionIndex];
            if (selected) {
              this.applySuggestion(selected);
              return;
            }
          }
          this.navigationManager.navigateTo(addressBar.value);
          this.hideAddressBarSuggestions();
        } else if (e.key === 'Escape') {
          this.hideAddressBarSuggestions();
          addressBar.blur();
        }
      });

      // Update address bar when tab changes
      this.tabManager.on('tabActivated', ({ tabId }) => {
        const tab = this.tabManager.getTab(tabId);
        if (tab && addressBar) {
          addressBar.value = tab.url || '';
        }
      });
    }
    
    // Navigation buttons
    this.backButton?.addEventListener('click', () => this.navigationManager.goBack());
    this.forwardButton?.addEventListener('click', () => this.navigationManager.goForward());
    this.reloadButton?.addEventListener('click', () => this.navigationManager.reload());
    this.homeButton?.addEventListener('click', () => this.navigationManager.goHome());
    
    // Menu buttons
    this.bookmarksButton?.addEventListener('click', () => this.showBookmarks());
    this.historyButton?.addEventListener('click', () => this.showHistory());
    this.downloadsButton?.addEventListener('click', () => this.showDownloads());
    this.settingsButton?.addEventListener('click', () => this.showSettings());
    
    // Go button
    const goButton = document.getElementById('go');
    goButton?.addEventListener('click', () => {
      if (this.addressBar) {
        const url = this.addressBar.value.trim();
        this.navigationManager.navigateTo(url);
      }
    });
    
    // Keyboard shortcuts
    document.addEventListener('keydown', this.handleKeyboardShortcuts.bind(this));
  }

  async initializeWalletUI() {
    if (!this.walletButton || !this.invoke) return;
    try {
      await this.refreshWalletInfo();
    } catch (e) {
      console.error('Failed to get initial wallet info:', e);
    }
    this.walletButton.addEventListener('click', async () => {
      try {
        // Refresh state before deciding action
        await this.refreshWalletInfo();
        if (this.walletInfo && this.walletInfo.is_connected) {
          await this.disconnectWallet();
        } else {
          await this.connectWallet();
        }
      } catch (err) {
        console.error('Wallet action failed:', err);
      }
    });
  }

  async refreshWalletInfo() {
    if (!this.invoke) return;
    try {
      this.walletInfo = await this.invoke('get_wallet_info');
    } catch (e) {
      console.error('get_wallet_info failed:', e);
    }
    this.updateWalletUI();
  }

  async connectWallet() {
    if (!this.invoke) return;
    try {
      this.walletInfo = await this.invoke('connect_wallet');
    } catch (e) {
      console.error('connect_wallet failed:', e);
    }
    this.updateWalletUI();
  }

  async disconnectWallet() {
    if (!this.invoke) return;
    try {
      await this.invoke('disconnect_wallet');
      this.walletInfo = null;
    } catch (e) {
      console.error('disconnect_wallet failed:', e);
    }
    this.updateWalletUI();
  }

  updateWalletUI() {
    if (!this.walletButton) return;
    const info = this.walletInfo;
    if (info && info.is_connected) {
      const addr = this.formatAddress(info.address || '');
      const bal = info.balance || '';
      this.walletButton.innerHTML = `
        <div class="wallet-connected">
          <div class="wallet-address">${addr}</div>
          <div class="wallet-balance">${bal}</div>
        </div>
      `;
      this.walletButton.className = 'wallet-button connected';
      this.walletButton.title = `Connected: ${addr}`;
    } else {
      this.walletButton.innerHTML = 'Connect Wallet';
      this.walletButton.className = 'wallet-button disconnected';
      this.walletButton.title = 'Wallet';
    }
  }

  formatAddress(address) {
    if (!address) return '';
    return address.length > 10 ? `${address.slice(0, 6)}...${address.slice(-4)}` : address;
  }
  
  setupContextMenu() {
    // Menu button
    if (this.menuButton) {
      this.menuButton.addEventListener('click', (e) => this.toggleMenu(e));
    }
    
    // Address bar events
    if (this.addressBar) {
      // Focus the address bar when pressing Ctrl+L or Alt+D or F6
      document.addEventListener('keydown', (e) => {
        if ((e.ctrlKey && e.key === 'l') || (e.altKey && e.key === 'd') || e.key === 'F6') {
          e.preventDefault();
          this.focusAddressBar();
        }
      });
      
      // Show suggestions when focusing the address bar
      this.addressBar.addEventListener('focus', () => {
        this.showAddressBarSuggestions();
      });
      
      // Hide suggestions when clicking outside
      document.addEventListener('click', (e) => {
        if (e.target !== this.addressBar && !this.suggestionsElement?.contains(e.target)) {
          this.hideAddressBarSuggestions();
        }
      });
      
      // Handle input with debounce
      this.addressBar.addEventListener('input', debounce(() => {
        this.updateAddressBarSuggestions();
      }, 200));
    }
    
    // Tab events
    this.tabManager.on('tabActivated', (tab) => {
      this.updateUIForTab(tab);
    });
    
    this.tabManager.on('tabClosed', () => {
      // Update UI when a tab is closed
      const activeTab = this.tabManager.getActiveTab();
      if (activeTab) {
        this.updateUIForTab(activeTab);
      }
    });
  }
  
  handleKeyboardShortcuts(e) {
    // Ctrl+1-9 to switch to specific tab
    if (e.ctrlKey && e.key >= '1' && e.key <= '9') {
      const index = parseInt(e.key) - 1;
      const tabs = this.tabManager.getAllTabs();
      if (index < tabs.length) {
        e.preventDefault();
        this.tabManager.activateTab(tabs[index].id);
      }
    }
    
    // Ctrl+Tab to switch to next tab
    if (e.ctrlKey && e.key === 'Tab' && !e.shiftKey) {
      e.preventDefault();
      this.tabManager.activateNextTab();
    }
    
    // Ctrl+Shift+Tab to switch to previous tab
    if (e.ctrlKey && e.shiftKey && e.key === 'Tab') {
      e.preventDefault();
      this.tabManager.activatePreviousTab();
    }
    
    // Ctrl+T to open new tab
    if ((e.ctrlKey || e.metaKey) && e.key === 't') {
      e.preventDefault();
      this.tabManager.createTab();
    }
    
    // Ctrl+W to close current tab
    if ((e.ctrlKey || e.metaKey) && e.key === 'w') {
      const activeTab = this.tabManager.getActiveTab();
      if (activeTab && this.tabManager.getTabCount() > 1) {
        e.preventDefault();
        this.tabManager.closeTab(activeTab.id);
      }
    }
    
    // F5 or Ctrl+R to reload
    if (e.key === 'F5' || ((e.ctrlKey || e.metaKey) && e.key === 'r')) {
      e.preventDefault();
      this.navigationManager.reload();
    }
    
    // Alt+Left to go back
    if (e.altKey && e.key === 'ArrowLeft') {
      e.preventDefault();
      this.navigationManager.goBack();
    }
    
    // Alt+Right to go forward
    if (e.altKey && e.key === 'ArrowRight') {
      e.preventDefault();
      this.navigationManager.goForward();
    }
  }
  
  updateUIForTab(tab) {
    if (!tab) return;
    
    // Update address bar
    if (this.addressBar) {
      this.addressBar.value = tab.url || '';
    }
    
    // Update document title
    document.title = tab.title ? `${tab.title} - Decentralized Browser` : 'Decentralized Browser';
    
    // Update navigation buttons
    const backButton = document.getElementById('back');
    const forwardButton = document.getElementById('forward');
    
    if (backButton) backButton.disabled = !tab.canGoBack;
    if (forwardButton) forwardButton.disabled = !tab.canGoForward;
  }
  
  focusAddressBar() {
    if (this.addressBar) {
      this.addressBar.select();
      this.showAddressBarSuggestions();
    }
  }

  initializeEventListeners() {
    // Kept for backward compatibility with older init paths.
  }

  createSuggestionsElement() {
    const element = document.createElement('div');
    element.className = 'address-suggestions';
    element.style.display = 'none';
    element.setAttribute('role', 'listbox');
    document.body.appendChild(element);

    element.addEventListener('mousedown', (e) => {
      e.preventDefault();
    });

    element.addEventListener('click', (e) => {
      const item = e.target.closest('.address-suggestion-item');
      if (!item) return;
      const index = Number(item.dataset.index);
      if (Number.isNaN(index)) return;
      const suggestion = this.suggestions[index];
      if (suggestion) {
        this.applySuggestion(suggestion);
      }
    });

    window.addEventListener('resize', () => {
      if (element.style.display === 'block') {
        this.positionSuggestions();
      }
    });

    return element;
  }

  positionSuggestions() {
    if (!this.addressBar || !this.suggestionsElement) return;
    const rect = this.addressBar.getBoundingClientRect();
    this.suggestionsElement.style.width = `${rect.width}px`;
    this.suggestionsElement.style.left = `${rect.left + window.scrollX}px`;
    this.suggestionsElement.style.top = `${rect.bottom + window.scrollY + 6}px`;
  }

  setSuggestionIndex(index) {
    this.suggestionIndex = index;
    const items = this.suggestionsElement?.querySelectorAll('.address-suggestion-item');
    if (!items || items.length === 0) return;
    items.forEach((item, idx) => {
      if (idx === this.suggestionIndex) {
        item.classList.add('active');
        item.scrollIntoView({ block: 'nearest' });
      } else {
        item.classList.remove('active');
      }
    });
  }

  renderSuggestions() {
    if (!this.suggestionsElement) return;
    if (!this.suggestions || this.suggestions.length === 0) {
      this.hideAddressBarSuggestions();
      return;
    }

    const html = this.suggestions
      .map((suggestion, index) => {
        const title = this.escapeHtml(suggestion.title || suggestion.url || '');
        const subtitle = this.escapeHtml(suggestion.subtitle || suggestion.url || '');
        const iconUrl = suggestion.favicon || (suggestion.url ? getFaviconUrl(suggestion.url) : '');
        const badge = suggestion.badge ? this.escapeHtml(suggestion.badge) : '';
        return `
          <div class="address-suggestion-item ${index === this.suggestionIndex ? 'active' : ''}" data-index="${index}">
            <div class="address-suggestion-icon">
              ${iconUrl ? `<img src="${iconUrl}" alt="" onerror="this.style.display='none'">` : '<span>🔎</span>'}
            </div>
            <div class="address-suggestion-text">
              <div class="address-suggestion-title">${title}</div>
              <div class="address-suggestion-subtitle">${subtitle}</div>
            </div>
            ${badge ? `<div class="address-suggestion-badge">${badge}</div>` : ''}
          </div>
        `;
      })
      .join('');

    this.suggestionsElement.innerHTML = html;
    this.positionSuggestions();
    this.suggestionsElement.style.display = 'block';
  }

  applySuggestion(suggestion) {
    const value = suggestion.url || suggestion.query || '';
    if (!value) return;
    if (this.addressBar) {
      this.addressBar.value = value;
    }
    this.navigationManager.navigateTo(value);
    this.hideAddressBarSuggestions();
  }

  buildSuggestions(query) {
    const suggestions = [];
    const seen = new Set();
    const trimmed = (query || '').trim();

    const addSuggestion = (suggestion) => {
      const key = suggestion.url || suggestion.title;
      if (key && seen.has(key)) return;
      if (key) seen.add(key);
      suggestions.push(suggestion);
    };

    if (trimmed) {
      const hasScheme = /^[a-zA-Z]+:\/\//.test(trimmed);
      const urlCandidate =
        hasScheme ||
        trimmed.startsWith('localhost') ||
        trimmed.includes('.') ||
        trimmed.startsWith('ipfs://') ||
        trimmed.startsWith('ipns://') ||
        trimmed.startsWith('ens://') ||
        trimmed.startsWith('about:');

      if (urlCandidate) {
        let url = trimmed;
        if (!hasScheme && !trimmed.startsWith('ipfs://') && !trimmed.startsWith('ipns://') && !trimmed.startsWith('ens://') && !trimmed.startsWith('about:')) {
          url = normalizeUrl(trimmed);
        }
        addSuggestion({
          type: 'url',
          title: `Go to ${url}`,
          url,
          subtitle: 'Open URL',
          badge: 'URL'
        });
      }

      addSuggestion({
        type: 'search',
        title: `Search "${trimmed}"`,
        url: trimmed,
        subtitle: 'Search the web',
        badge: 'Search'
      });

      const historyMatches = this.historyManager.searchHistory(trimmed, 6) || [];
      historyMatches.forEach((item) => {
        addSuggestion({
          type: 'history',
          title: item.title || item.url,
          url: item.url,
          subtitle: item.url,
          favicon: item.favicon || '',
          badge: 'History'
        });
      });

      const bookmarkMatches = this.bookmarkManager.searchBookmarks(trimmed) || [];
      bookmarkMatches
        .filter((item) => item && item.url)
        .slice(0, 6)
        .forEach((item) => {
          addSuggestion({
            type: 'bookmark',
            title: item.title || item.url,
            url: item.url,
            subtitle: item.url,
            badge: 'Bookmark'
          });
        });
    } else {
      const mostVisited = this.historyManager.getMostVisited(5) || [];
      mostVisited.forEach((item) => {
        addSuggestion({
          type: 'history',
          title: item.title || item.url,
          url: item.url,
          subtitle: 'Most visited',
          favicon: item.favicon || '',
          badge: 'Top'
        });
      });

      const bookmarks = [];
      const root = this.bookmarkManager.getRootFolder?.() || null;
      if (root) {
        this.collectBookmarksFromFolder(root, bookmarks);
      }
      bookmarks
        .sort((a, b) => (b.dateAdded || 0) - (a.dateAdded || 0))
        .slice(0, 5)
        .forEach((item) => {
          addSuggestion({
            type: 'bookmark',
            title: item.title || item.url,
            url: item.url,
            subtitle: 'Bookmark',
            badge: 'Bookmark'
          });
        });
    }

    return suggestions;
  }

  collectBookmarksFromFolder(folder, output) {
    if (!folder || !folder.children) return;
    folder.children.forEach((child) => {
      if (!child) return;
      if ('url' in child && child.url) {
        output.push(child);
      } else if ('children' in child) {
        this.collectBookmarksFromFolder(child, output);
      }
    });
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  }
  
  showAddressBarSuggestions() {
    this.updateAddressBarSuggestions();
  }
  
  hideAddressBarSuggestions() {
    if (this.suggestionsElement) {
      this.suggestionsElement.style.display = 'none';
    }
    this.suggestions = [];
    this.suggestionIndex = -1;
  }
  
  updateAddressBarSuggestions() {
    if (!this.addressBar) return;
    this.suggestions = this.buildSuggestions(this.addressBar.value);
    this.suggestionIndex = this.suggestions.length ? 0 : -1;
    this.renderSuggestions();
  }
  
  toggleMenu(event) {
    event.stopPropagation();
    if (!this.menuElement) {
      this.menuElement = document.createElement('div');
      this.menuElement.className = 'browser-menu';
      this.menuElement.innerHTML = `
        <button data-action="new-tab">New Tab</button>
        <button data-action="new-window">New Window</button>
        <button data-action="history">History</button>
        <button data-action="bookmarks">Bookmarks</button>
        <button data-action="downloads">Downloads</button>
        <button data-action="settings">Settings</button>
      `;
      document.body.appendChild(this.menuElement);
      this.menuElement.addEventListener('click', (e) => {
        const action = e.target.closest('button')?.dataset.action;
        if (!action) return;
        if (action === 'new-tab') this.tabManager.createTab();
        if (action === 'new-window') this.tabManager.createTab();
        if (action === 'history') this.showHistory();
        if (action === 'bookmarks') this.showBookmarks();
        if (action === 'downloads') this.showDownloads();
        if (action === 'settings') this.showSettings();
        this.menuElement.classList.remove('open');
      });
      document.addEventListener('click', (e) => {
        if (e.target !== this.menuButton && !this.menuElement.contains(e.target)) {
          this.menuElement.classList.remove('open');
        }
      });
    }

    if (this.menuButton) {
      const rect = this.menuButton.getBoundingClientRect();
      this.menuElement.style.left = `${rect.left + window.scrollX}px`;
      this.menuElement.style.top = `${rect.bottom + window.scrollY + 6}px`;
    }
    this.menuElement.classList.toggle('open');
  }
  
  showBookmarks() {
    if (this.bookmarksPanel) {
      this.bookmarksPanel.toggle();
    }
  }
  
  showHistory() {
    this.historyPanel.toggle();
  }
  
  showDownloads() {
    if (this.downloadsPanel) {
      this.downloadsPanel.toggle();
    }
  }
  
  showSettings() {
    if (window.settingsManager && typeof window.settingsManager.showSettingsPanel === 'function') {
      window.settingsManager.showSettingsPanel();
    } else {
      console.log('Show settings');
    }
  }
  
  // Create a simple event bus for component communication
  createEventBus() {
    const listeners = new Map();
    
    return {
      subscribe(event, callback) {
        if (!listeners.has(event)) {
          listeners.set(event, []);
        }
        listeners.get(event).push(callback);
      },
      
      unsubscribe(event, callback) {
        if (listeners.has(event)) {
          const callbacks = listeners.get(event);
          const index = callbacks.indexOf(callback);
          if (index > -1) {
            callbacks.splice(index, 1);
          }
        }
      },
      
      publish(event, data) {
        if (listeners.has(event)) {
          listeners.get(event).forEach(callback => {
            try {
              callback(data);
            } catch (error) {
              console.error(`Error in event listener for ${event}:`, error);
            }
          });
        }
      }
    };
  }
  
  // Set up history integration with navigation and tab events
  setupHistoryIntegration() {
    // Listen for navigation events from the navigation manager
    this.eventBus.subscribe('navigate', (data) => {
      this.navigationManager.navigateTo(data.url);
    });
    
    // Listen for tab creation events
    this.eventBus.subscribe('createTab', (data) => {
      this.tabManager.createTab(data.url);
    });
    
    // Integrate with existing navigation manager
    if (this.navigationManager) {
      // Override the original navigateTo to emit history events
      const originalNavigateTo = this.navigationManager.navigateTo.bind(this.navigationManager);
      this.navigationManager.navigateTo = async (url) => {
        // Emit navigation started event for history tracking
        this.eventBus.publish('navigationStarted', {
          url,
          transitionType: 'typed'
        });
        
        // Call original navigation method
        const result = await originalNavigateTo(url);
        
        // Emit navigation completed event
        const tab = this.tabManager.getActiveTab();
        if (tab) {
          this.eventBus.publish('navigationCompleted', {
            url: tab.url,
            title: tab.title,
            favicon: tab.favicon
          });
        }
        
        return result;
      };
    }
    
    // Integrate with tab manager events
    if (this.tabManager) {
      // Listen for tab activation to track visits
      const originalActivateTab = this.tabManager.activateTab.bind(this.tabManager);
      this.tabManager.activateTab = async (tabId) => {
        const result = await originalActivateTab(tabId);
        const tab = this.tabManager.getTab(tabId);
        
        if (tab) {
          this.eventBus.publish('tabActivated', { tab });
        }
        
        return result;
      };
    }
  }
}
