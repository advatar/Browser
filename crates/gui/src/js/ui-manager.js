import { debounce } from './utils.js';

import { HistoryManager } from './history-manager.js';
import { HistoryPanel } from './history-panel.js';

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
    
    // Initialize history management
    this.eventBus = this.createEventBus();
    this.historyManager = new HistoryManager(this.eventBus);
    this.historyPanel = new HistoryPanel(this.historyManager, this.eventBus);
    
    this.setupEventListeners();
    this.setupContextMenu();
    this.setupHistoryIntegration();
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
        if (e.key === 'Enter') {
          this.navigationManager.navigateTo(addressBar.value);
        } else if (e.key === 'Escape') {
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
        if (e.target !== this.addressBar) {
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
  
  showAddressBarSuggestions() {
    // TODO: Implement address bar suggestions
    console.log('Show address bar suggestions');
  }
  
  hideAddressBarSuggestions() {
    // TODO: Hide address bar suggestions
    console.log('Hide address bar suggestions');
  }
  
  updateAddressBarSuggestions() {
    // TODO: Update address bar suggestions based on input
    console.log('Update address bar suggestions');
  }
  
  toggleMenu(event) {
    event.stopPropagation();
    // TODO: Implement menu toggle
    console.log('Toggle menu');
  }
  
  showBookmarks() {
    // TODO: Implement bookmarks panel
    console.log('Show bookmarks');
  }
  
  showHistory() {
    this.historyPanel.toggle();
  }
  
  showDownloads() {
    // TODO: Implement downloads panel
    console.log('Show downloads');
  }
  
  showSettings() {
    // TODO: Implement settings panel
    console.log('Show settings');
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
