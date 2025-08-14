import { normalizeUrl, isValidUrl } from './utils.js';

export class NavigationManager {
  constructor(tabManager) {
    this.tabManager = tabManager;
    this.addressBar = document.getElementById('address-bar');
    this.backButton = document.getElementById('back');
    this.forwardButton = document.getElementById('forward');
    this.reloadButton = document.getElementById('reload');
    this.homeButton = document.getElementById('home');
    
    this.initializeEventListeners();
  }
  
  initializeEventListeners() {
    // Back button
    if (this.backButton) {
      this.backButton.addEventListener('click', () => this.goBack());
    }
    
    // Forward button
    if (this.forwardButton) {
      this.forwardButton.addEventListener('click', () => this.goForward());
    }
    
    // Reload button
    if (this.reloadButton) {
      this.reloadButton.addEventListener('click', () => this.reload());
    }
    
    // Home button
    if (this.homeButton) {
      this.homeButton.addEventListener('click', () => this.goHome());
    }
    
    // Address bar
    if (this.addressBar) {
      this.addressBar.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          this.navigateTo(this.addressBar.value);
        }
      });
      
      // Update address bar when tab changes
      this.tabManager.on('tabActivated', (tab) => {
        if (tab) {
          this.updateNavigationState(tab);
        }
      });
    }
  }
  
  // Navigate to a URL
  async navigateTo(url, { fromHistory = false } = {}) {
    if (!url || typeof url !== 'string') return;
    
    const tab = this.tabManager.getActiveTab();
    if (!tab || !tab.webview) return;
    
    // Normalize the URL
    let targetUrl = url.trim();
    
    // Handle empty URL
    if (!targetUrl) return;
    
    // Handle special URLs
    if (targetUrl === '' || targetUrl === 'about:home') {
      tab.webview.src = 'about:home';
      this.updateNavigationState(tab);
      return;
    }
    if (targetUrl.startsWith('about:')) {
      tab.webview.src = targetUrl;
      this.updateNavigationState(tab);
      return;
    }
    
    // Check if it's a valid URL
    if (!isValidUrl(targetUrl) && !targetUrl.startsWith('about:')) {
      // Treat as a search query
      targetUrl = `https://www.google.com/search?q=${encodeURIComponent(targetUrl)}`;
    } else if (!targetUrl.match(/^[a-zA-Z]+:\/\//)) {
      // Add https:// if no protocol is specified
      targetUrl = normalizeUrl(targetUrl);
    }
    
    try {
      // Emit navigation started event
      if (!fromHistory) {
        const navEvent = new CustomEvent('browser-event', {
          detail: {
            type: 'navigationStarted',
            data: {
              url: targetUrl,
              transitionType: 'typed',
              timestamp: Date.now(),
              tabId: tab.id
            }
          }
        });
        document.dispatchEvent(navEvent);
      }
      
      // Update the webview source
      tab.webview.src = targetUrl;
      
      // Update the address bar and tab state
      this.addressBar.value = targetUrl;
      tab.url = targetUrl;
      tab.title = 'Loading...';
      tab.updateUI();
      
      // Set up event listeners for page load if not already set
      if (!tab._hasLoadListener) {
        tab.webview.addEventListener('did-finish-load', () => {
          // Update tab title when page loads
          tab.title = tab.webview.getTitle() || new URL(tab.url).hostname || tab.url;
          tab.updateUI();
          
          // Emit navigation completed event
          const navCompleteEvent = new CustomEvent('browser-event', {
            detail: {
              type: 'navigationCompleted',
              data: {
                url: tab.url,
                title: tab.title,
                favicon: tab.webview.getFavicon() || '',
                tabId: tab.id,
                timestamp: Date.now()
              }
            }
          });
          document.dispatchEvent(navCompleteEvent);
        });
        
        tab._hasLoadListener = true;
      }
      
    } catch (error) {
      console.error('Navigation error:', error);
      
      // Emit navigation error event
      const navErrorEvent = new CustomEvent('browser-event', {
        detail: {
          type: 'navigationError',
          data: {
            url: targetUrl,
            error: error.message,
            tabId: tab?.id,
            timestamp: Date.now()
          }
        }
      });
      document.dispatchEvent(navErrorEvent);
    }
  }
  
  // Go back in history
  async goBack() {
    const tab = this.tabManager.getActiveTab();
    if (!tab || !tab.webview) return false;
    
    if (tab.webview.canGoBack()) {
      // Emit navigation started event
      const navEvent = new CustomEvent('browser-event', {
        detail: {
          type: 'navigationStarted',
          data: {
            url: tab.url,
            transitionType: 'back_forward',
            timestamp: Date.now(),
            tabId: tab.id
          }
        }
      });
      document.dispatchEvent(navEvent);
      
      // Perform the navigation
      tab.webview.goBack();
      this.updateNavigationState(tab);
      return true;
    }
    return false;
  }
  
  // Go forward in history
  async goForward() {
    const tab = this.tabManager.getActiveTab();
    if (!tab || !tab.webview) return false;
    
    if (tab.webview.canGoForward()) {
      // Emit navigation started event
      const navEvent = new CustomEvent('browser-event', {
        detail: {
          type: 'navigationStarted',
          data: {
            url: tab.url,
            transitionType: 'back_forward',
            timestamp: Date.now(),
            tabId: tab.id
          }
        }
      });
      document.dispatchEvent(navEvent);
      
      // Perform the navigation
      tab.webview.goForward();
      this.updateNavigationState(tab);
      return true;
    }
    return false;
  }
  
  // Reload the current page
  async reload() {
    const tab = this.tabManager.getActiveTab();
    if (!tab || !tab.webview) return;
    
    // Emit reload event
    const reloadEvent = new CustomEvent('browser-event', {
      detail: {
        type: 'navigationReload',
        data: {
          url: tab.url,
          timestamp: Date.now(),
          tabId: tab.id
        }
      }
    });
    document.dispatchEvent(reloadEvent);
    
    // Perform the reload
    tab.webview.reload();
    this.updateNavigationState(tab);
  }
  
  // Go to the home page
  async goHome() {
    // Use fromHistory flag to avoid duplicate history entries
    // since we're just navigating to a URL
    await this.navigateTo('about:home', { fromHistory: true });
  }
  
  // Update navigation buttons and address bar
  updateNavigationState(tab) {
    if (!tab) return;
    
    // Update address bar
    if (this.addressBar) {
      this.addressBar.value = tab.url || '';
    }
    
    // Update back/forward buttons
    if (this.backButton) {
      this.backButton.disabled = !tab.canGoBack;
    }
    
    if (this.forwardButton) {
      this.forwardButton.disabled = !tab.canGoForward;
    }
  }
  
  // Get the current URL
  getCurrentUrl() {
    const tab = this.tabManager.getActiveTab();
    return tab ? tab.url : '';
  }
  
  // Get the current page title
  getCurrentTitle() {
    const tab = this.tabManager.getActiveTab();
    return tab ? tab.title : '';
  }
}
