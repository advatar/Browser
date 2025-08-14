import { generateId, saveToStorage, loadFromStorage } from './utils.js';

// Storage key for history
const HISTORY_STORAGE_KEY = 'browser_history';

// Maximum number of history items to keep
const MAX_HISTORY_ITEMS = 10000;

// History transition types
export const TRANSITION_TYPES = {
  TYPED: 'typed',
  LINK: 'link',
  RELOAD: 'reload',
  BACK_FORWARD: 'back_forward',
  BOOKMARK: 'bookmark'
};

export class HistoryManager {
  constructor(eventBus) {
    this.eventBus = eventBus;
    this.history = new Map(); // id -> HistoryItem
    this.urlToId = new Map(); // url -> id (for quick lookups)
    this.chronologicalOrder = []; // Array of ids in chronological order
    
    this.loadHistory();
    this.setupEventListeners();
    
    // Auto-save history periodically
    setInterval(() => this.saveHistory(), 30000); // Save every 30 seconds
    
    // Save on page unload
    window.addEventListener('beforeunload', () => this.saveHistory());
  }
  
  setupEventListeners() {
    // Listen for navigation events
    this.eventBus.subscribe('navigationStarted', (data) => {
      this.addHistoryItem(data.url, data.title || 'Loading...', data.transitionType || TRANSITION_TYPES.TYPED);
    });
    
    this.eventBus.subscribe('navigationCompleted', (data) => {
      this.updateHistoryItem(data.url, data.title, data.favicon);
    });
    
    // Listen for tab events to track page visits
    this.eventBus.subscribe('tabActivated', (data) => {
      if (data.tab && data.tab.url) {
        this.recordVisit(data.tab.url);
      }
    });
  }
  
  /**
   * Add a new history item or update existing one
   * @param {string} url - The URL visited
   * @param {string} title - Page title
   * @param {string} transitionType - How the navigation occurred
   * @param {string} favicon - Page favicon URL
   */
  addHistoryItem(url, title = '', transitionType = TRANSITION_TYPES.TYPED, favicon = '') {
    if (!url || url.startsWith('about:')) return;
    
    const now = Date.now();
    let historyItem;
    
    // Check if URL already exists in history
    const existingId = this.urlToId.get(url);
    if (existingId && this.history.has(existingId)) {
      // Update existing item
      historyItem = this.history.get(existingId);
      historyItem.visitCount++;
      historyItem.lastVisitTime = now;
      historyItem.title = title || historyItem.title;
      historyItem.favicon = favicon || historyItem.favicon;
      
      if (transitionType === TRANSITION_TYPES.TYPED) {
        historyItem.typedCount = (historyItem.typedCount || 0) + 1;
      }
      
      // Move to end of chronological order
      const index = this.chronologicalOrder.indexOf(existingId);
      if (index > -1) {
        this.chronologicalOrder.splice(index, 1);
      }
      this.chronologicalOrder.push(existingId);
    } else {
      // Create new history item
      const id = generateId();
      historyItem = {
        id,
        url,
        title: title || url,
        favicon: favicon || '',
        visitCount: 1,
        lastVisitTime: now,
        typedCount: transitionType === TRANSITION_TYPES.TYPED ? 1 : 0,
        transitionType
      };
      
      this.history.set(id, historyItem);
      this.urlToId.set(url, id);
      this.chronologicalOrder.push(id);
    }
    
    // Maintain maximum history size
    this.trimHistory();
    
    // Emit event
    this.eventBus.publish('historyItemAdded', { item: historyItem });
    
    return historyItem;
  }
  
  /**
   * Update an existing history item
   * @param {string} url - The URL to update
   * @param {string} title - New title
   * @param {string} favicon - New favicon
   */
  updateHistoryItem(url, title, favicon) {
    const id = this.urlToId.get(url);
    if (!id || !this.history.has(id)) return;
    
    const item = this.history.get(id);
    if (title) item.title = title;
    if (favicon) item.favicon = favicon;
    
    this.eventBus.publish('historyItemUpdated', { item });
  }
  
  /**
   * Record a visit to a URL (for tracking visit frequency)
   * @param {string} url - The URL visited
   */
  recordVisit(url) {
    const id = this.urlToId.get(url);
    if (id && this.history.has(id)) {
      const item = this.history.get(id);
      item.lastVisitTime = Date.now();
    }
  }
  
  /**
   * Get history items in chronological order (most recent first)
   * @param {number} limit - Maximum number of items to return
   * @returns {Array} Array of history items
   */
  getHistory(limit = 100) {
    return this.chronologicalOrder
      .slice(-limit)
      .reverse()
      .map(id => this.history.get(id))
      .filter(Boolean);
  }
  
  /**
   * Search history by query
   * @param {string} query - Search query
   * @param {number} limit - Maximum results
   * @returns {Array} Matching history items
   */
  searchHistory(query, limit = 50) {
    if (!query) return this.getHistory(limit);
    
    const lowerQuery = query.toLowerCase();
    const results = [];
    
    for (const item of this.history.values()) {
      if (item.title.toLowerCase().includes(lowerQuery) || 
          item.url.toLowerCase().includes(lowerQuery)) {
        results.push(item);
      }
      
      if (results.length >= limit) break;
    }
    
    // Sort by relevance (visit count and recency)
    return results.sort((a, b) => {
      const scoreA = a.visitCount * 0.3 + (a.lastVisitTime / 1000000) * 0.7;
      const scoreB = b.visitCount * 0.3 + (b.lastVisitTime / 1000000) * 0.7;
      return scoreB - scoreA;
    });
  }
  
  /**
   * Get most visited sites
   * @param {number} limit - Number of sites to return
   * @returns {Array} Most visited history items
   */
  getMostVisited(limit = 10) {
    return Array.from(this.history.values())
      .sort((a, b) => b.visitCount - a.visitCount)
      .slice(0, limit);
  }
  
  /**
   * Get recently visited sites
   * @param {number} limit - Number of sites to return
   * @returns {Array} Recently visited history items
   */
  getRecentlyVisited(limit = 10) {
    return this.getHistory(limit);
  }
  
  /**
   * Remove a history item
   * @param {string} id - History item ID
   */
  removeHistoryItem(id) {
    const item = this.history.get(id);
    if (!item) return;
    
    this.history.delete(id);
    this.urlToId.delete(item.url);
    
    const index = this.chronologicalOrder.indexOf(id);
    if (index > -1) {
      this.chronologicalOrder.splice(index, 1);
    }
    
    this.eventBus.publish('historyItemRemoved', { id, item });
  }
  
  /**
   * Clear all history
   */
  clearHistory() {
    this.history.clear();
    this.urlToId.clear();
    this.chronologicalOrder = [];
    
    this.saveHistory();
    this.eventBus.publish('historyCleared');
  }
  
  /**
   * Clear history for a specific time range
   * @param {number} startTime - Start timestamp
   * @param {number} endTime - End timestamp
   */
  clearHistoryRange(startTime, endTime) {
    const toRemove = [];
    
    for (const [id, item] of this.history.entries()) {
      if (item.lastVisitTime >= startTime && item.lastVisitTime <= endTime) {
        toRemove.push(id);
      }
    }
    
    toRemove.forEach(id => this.removeHistoryItem(id));
  }
  
  /**
   * Get history statistics
   * @returns {Object} Statistics object
   */
  getStatistics() {
    const totalItems = this.history.size;
    const totalVisits = Array.from(this.history.values())
      .reduce((sum, item) => sum + item.visitCount, 0);
    
    const now = Date.now();
    const oneDayAgo = now - (24 * 60 * 60 * 1000);
    const oneWeekAgo = now - (7 * 24 * 60 * 60 * 1000);
    
    const todayVisits = Array.from(this.history.values())
      .filter(item => item.lastVisitTime >= oneDayAgo).length;
    
    const weekVisits = Array.from(this.history.values())
      .filter(item => item.lastVisitTime >= oneWeekAgo).length;
    
    return {
      totalItems,
      totalVisits,
      todayVisits,
      weekVisits,
      oldestVisit: Math.min(...Array.from(this.history.values()).map(item => item.lastVisitTime)),
      newestVisit: Math.max(...Array.from(this.history.values()).map(item => item.lastVisitTime))
    };
  }
  
  /**
   * Trim history to maximum size
   */
  trimHistory() {
    if (this.chronologicalOrder.length <= MAX_HISTORY_ITEMS) return;
    
    const toRemove = this.chronologicalOrder.length - MAX_HISTORY_ITEMS;
    const removedIds = this.chronologicalOrder.splice(0, toRemove);
    
    removedIds.forEach(id => {
      const item = this.history.get(id);
      if (item) {
        this.history.delete(id);
        this.urlToId.delete(item.url);
      }
    });
  }
  
  /**
   * Save history to storage
   */
  saveHistory() {
    const historyData = {
      items: Array.from(this.history.entries()),
      urlToId: Array.from(this.urlToId.entries()),
      chronologicalOrder: this.chronologicalOrder,
      version: 1
    };
    
    saveToStorage(HISTORY_STORAGE_KEY, historyData);
  }
  
  /**
   * Load history from storage
   */
  loadHistory() {
    const historyData = loadFromStorage(HISTORY_STORAGE_KEY, null);
    
    if (historyData && historyData.version === 1) {
      this.history = new Map(historyData.items || []);
      this.urlToId = new Map(historyData.urlToId || []);
      this.chronologicalOrder = historyData.chronologicalOrder || [];
    }
  }
  
  /**
   * Export history data
   * @returns {Array} Exportable history data
   */
  exportHistory() {
    return Array.from(this.history.values()).map(item => ({
      url: item.url,
      title: item.title,
      visitCount: item.visitCount,
      lastVisitTime: new Date(item.lastVisitTime).toISOString()
    }));
  }
  
  /**
   * Import history data
   * @param {Array} historyData - History data to import
   */
  importHistory(historyData) {
    historyData.forEach(item => {
      if (item.url && item.title) {
        this.addHistoryItem(
          item.url,
          item.title,
          TRANSITION_TYPES.LINK,
          item.favicon || ''
        );
      }
    });
  }
}
