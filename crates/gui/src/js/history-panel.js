import { getFaviconUrl } from './utils.js';

export class HistoryPanel {
  constructor(historyManager, eventBus) {
    this.historyManager = historyManager;
    this.eventBus = eventBus;
    this.isVisible = false;
    this.currentView = 'recent'; // 'recent', 'search', 'mostVisited'
    this.searchQuery = '';
    
    this.createElement();
    this.setupEventListeners();
  }
  
  createElement() {
    this.element = document.createElement('div');
    this.element.className = 'history-panel';
    this.element.style.display = 'none';
    
    this.render();
    
    // Append to body or a designated container
    document.body.appendChild(this.element);
  }
  
  render() {
    const stats = this.historyManager.getStatistics();
    
    this.element.innerHTML = `
      <div class="history-panel-header">
        <h2>History</h2>
        <button class="history-close-btn" title="Close">×</button>
      </div>
      
      <div class="history-controls">
        <div class="history-search">
          <input type="text" class="history-search-input" placeholder="Search history..." value="${this.searchQuery}">
          <button class="history-search-btn">🔍</button>
        </div>
        
        <div class="history-tabs">
          <button class="history-tab ${this.currentView === 'recent' ? 'active' : ''}" data-view="recent">
            Recent
          </button>
          <button class="history-tab ${this.currentView === 'mostVisited' ? 'active' : ''}" data-view="mostVisited">
            Most Visited
          </button>
          <button class="history-tab ${this.currentView === 'search' ? 'active' : ''}" data-view="search">
            Search Results
          </button>
        </div>
        
        <div class="history-actions">
          <button class="history-clear-btn">Clear History</button>
          <button class="history-export-btn">Export</button>
        </div>
      </div>
      
      <div class="history-stats">
        <span>Total: ${stats.totalItems} items</span>
        <span>Today: ${stats.todayVisits} visits</span>
        <span>This week: ${stats.weekVisits} visits</span>
      </div>
      
      <div class="history-content">
        ${this.renderHistoryItems()}
      </div>
    `;
    
    this.setupEventListeners();
  }
  
  renderHistoryItems() {
    let items = [];
    
    switch (this.currentView) {
      case 'recent':
        items = this.historyManager.getRecentlyVisited(100);
        break;
      case 'mostVisited':
        items = this.historyManager.getMostVisited(50);
        break;
      case 'search':
        items = this.historyManager.searchHistory(this.searchQuery, 100);
        break;
    }
    
    if (items.length === 0) {
      return `<div class="history-empty">No history items found</div>`;
    }
    
    return `
      <div class="history-list">
        ${items.map(item => this.renderHistoryItem(item)).join('')}
      </div>
    `;
  }
  
  renderHistoryItem(item) {
    const visitTime = new Date(item.lastVisitTime);
    const timeString = this.formatTime(visitTime);
    
    return `
      <div class="history-item" data-id="${item.id}">
        <div class="history-item-favicon">
          <img src="${item.favicon || getFaviconUrl(item.url)}" 
               alt="" 
               onerror="this.src='${getFaviconUrl(item.url)}'" />
        </div>
        
        <div class="history-item-content">
          <div class="history-item-title">${this.escapeHtml(item.title)}</div>
          <div class="history-item-url">${this.escapeHtml(item.url)}</div>
          <div class="history-item-meta">
            <span class="history-item-time">${timeString}</span>
            <span class="history-item-visits">${item.visitCount} visit${item.visitCount !== 1 ? 's' : ''}</span>
            ${item.typedCount ? `<span class="history-item-typed">${item.typedCount} typed</span>` : ''}
          </div>
        </div>
        
        <div class="history-item-actions">
          <button class="history-item-open" title="Open in current tab">↗</button>
          <button class="history-item-new-tab" title="Open in new tab">⧉</button>
          <button class="history-item-remove" title="Remove from history">×</button>
        </div>
      </div>
    `;
  }
  
  formatTime(date) {
    const now = new Date();
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / (1000 * 60));
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
    
    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins} minute${diffMins !== 1 ? 's' : ''} ago`;
    if (diffHours < 24) return `${diffHours} hour${diffHours !== 1 ? 's' : ''} ago`;
    if (diffDays < 7) return `${diffDays} day${diffDays !== 1 ? 's' : ''} ago`;
    
    return date.toLocaleDateString();
  }
  
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
  
  setupEventListeners() {
    if (!this.element) return;
    
    // Close button
    const closeBtn = this.element.querySelector('.history-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', () => this.hide());
    }
    
    // Search input
    const searchInput = this.element.querySelector('.history-search-input');
    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        this.searchQuery = e.target.value;
        if (this.currentView === 'search' || this.searchQuery) {
          this.currentView = 'search';
          this.render();
        }
      });
      
      searchInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          this.currentView = 'search';
          this.render();
        }
      });
    }
    
    // Search button
    const searchBtn = this.element.querySelector('.history-search-btn');
    if (searchBtn) {
      searchBtn.addEventListener('click', () => {
        this.currentView = 'search';
        this.render();
      });
    }
    
    // Tab buttons
    this.element.addEventListener('click', (e) => {
      const tabBtn = e.target.closest('.history-tab');
      if (tabBtn) {
        this.currentView = tabBtn.dataset.view;
        this.render();
      }
    });
    
    // History item actions
    this.element.addEventListener('click', (e) => {
      const item = e.target.closest('.history-item');
      if (!item) return;
      
      const itemId = item.dataset.id;
      const historyItem = Array.from(this.historyManager.history.values())
        .find(h => h.id === itemId);
      
      if (!historyItem) return;
      
      if (e.target.classList.contains('history-item-open')) {
        // Open in current tab
        this.eventBus.publish('navigate', { url: historyItem.url });
        this.hide();
      } else if (e.target.classList.contains('history-item-new-tab')) {
        // Open in new tab
        this.eventBus.publish('createTab', { url: historyItem.url });
      } else if (e.target.classList.contains('history-item-remove')) {
        // Remove from history
        this.historyManager.removeHistoryItem(itemId);
        this.render();
      } else if (e.target.closest('.history-item-content')) {
        // Click on content area - open in current tab
        this.eventBus.publish('navigate', { url: historyItem.url });
        this.hide();
      }
    });
    
    // Clear history button
    const clearBtn = this.element.querySelector('.history-clear-btn');
    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        if (confirm('Are you sure you want to clear all history? This action cannot be undone.')) {
          this.historyManager.clearHistory();
          this.render();
        }
      });
    }
    
    // Export button
    const exportBtn = this.element.querySelector('.history-export-btn');
    if (exportBtn) {
      exportBtn.addEventListener('click', () => {
        this.exportHistory();
      });
    }
    
    // Close on escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.isVisible) {
        this.hide();
      }
    });
    
    // Close when clicking outside
    document.addEventListener('click', (e) => {
      if (this.isVisible && !this.element.contains(e.target)) {
        const historyButton = document.getElementById('history-button');
        if (!historyButton || !historyButton.contains(e.target)) {
          this.hide();
        }
      }
    });
  }
  
  show() {
    this.isVisible = true;
    this.element.style.display = 'block';
    this.render();
    
    // Focus search input
    const searchInput = this.element.querySelector('.history-search-input');
    if (searchInput) {
      searchInput.focus();
    }
    
    this.eventBus.publish('historyPanelOpened');
  }
  
  hide() {
    this.isVisible = false;
    this.element.style.display = 'none';
    this.eventBus.publish('historyPanelClosed');
  }
  
  toggle() {
    if (this.isVisible) {
      this.hide();
    } else {
      this.show();
    }
  }
  
  exportHistory() {
    const historyData = this.historyManager.exportHistory();
    const dataStr = JSON.stringify(historyData, null, 2);
    const dataBlob = new Blob([dataStr], { type: 'application/json' });
    
    const link = document.createElement('a');
    link.href = URL.createObjectURL(dataBlob);
    link.download = `browser-history-${new Date().toISOString().split('T')[0]}.json`;
    link.click();
    
    URL.revokeObjectURL(link.href);
  }
  
  destroy() {
    if (this.element && this.element.parentNode) {
      this.element.parentNode.removeChild(this.element);
    }
  }
}
