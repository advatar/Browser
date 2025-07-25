import { Tab } from './tab.js';
import { TabGroup } from './tab-group.js';
import { debounce, generateId, loadFromStorage, saveToStorage } from './utils.js';

// Storage keys
const STORAGE_KEYS = {
  TABS: 'browser_tabs',
  GROUPS: 'browser_tab_groups',
  WINDOW_STATE: 'browser_window_state'
};

// Default group
const DEFAULT_GROUP_ID = 'default-group';

export class TabManager {
  constructor() {
    this.tabs = new Map();
    this.groups = new Map();
    this.activeTabId = null;
    this.activeGroupId = DEFAULT_GROUP_ID;
    this.tabCounter = 0;
    this.draggedTab = null;
    this.tabTemplate = document.getElementById('tab-template');
    this.tabsContainer = document.getElementById('tabs');
    this.appContainer = document.getElementById('app');
    this.groupsContainer = document.getElementById('tab-groups');
    
    // Initialize the default group
    this.createGroup('Default', '#4a90e2', DEFAULT_GROUP_ID);
    
    // Load saved state
    this.loadState();
    
    // Set up beforeunload to save state
    window.addEventListener('beforeunload', () => this.saveState());
    
    // Bind methods
    this.createTab = this.createTab.bind(this);
    this.closeTab = this.closeTab.bind(this);
    this.activateTab = this.activateTab.bind(this);
    this.getActiveTab = this.getActiveTab.bind(this);
    this.handleDragStart = this.handleDragStart.bind(this);
    this.handleDragOver = this.handleDragOver.bind(this);
    this.handleDrop = this.handleDrop.bind(this);
    this.handleDragEnd = this.handleDragEnd.bind(this);
    
    // Set up new tab button
    const newTabButton = document.getElementById('new-tab');
    if (newTabButton) {
      newTabButton.addEventListener('click', () => this.createTab());
    }
    
    // Set up drag and drop events
    const tabsContainer = document.getElementById('tabs');
    if (tabsContainer) {
      tabsContainer.addEventListener('dragover', this.handleDragOver);
      tabsContainer.addEventListener('drop', this.handleDrop);
      tabsContainer.addEventListener('dragend', this.handleDragEnd);
    }
  }
  
  // Create a new tab
  async createTab(url = 'about:blank', { activate = true } = {}) {
    const tabId = `tab-${++this.tabCounter}`;
    const tab = new Tab(tabId, url);
    
    // Set up event listeners
    tab.on('close', (id) => this.closeTab(id));
    tab.on('activate', (id) => this.activateTab(id));
    
    // Create the tab's DOM elements
    tab.createElements();
    
    // Add to our tabs map
    this.tabs.set(tabId, tab);
    
    // Activate the tab if requested
    if (activate) {
      await this.activateTab(tabId);
    }
    
    return tab;
  }
  
  // Close a tab
  closeTab(tabId) {
    const tab = this.tabs.get(tabId);
    if (!tab) return;
    
    // Don't close the last tab
    if (this.tabs.size <= 1) {
      return this.createTab();
    }
    
    const wasActive = tab.isActive;
    const tabIndex = Array.from(this.tabs.keys()).indexOf(tabId);
    
    // Remove the tab
    tab.destroy();
    this.tabs.delete(tabId);
    
    // If we closed the active tab, activate another one
    if (wasActive) {
      // Try to activate the next tab, or the previous one if there is no next
      const nextTabId = Array.from(this.tabs.keys())[Math.min(tabIndex, this.tabs.size - 1)];
      if (nextTabId) {
        this.activateTab(nextTabId);
      }
    }
  }
  
  // Activate a tab
  async activateTab(tabId) {
    const tab = this.tabs.get(tabId);
    if (!tab || tab.isActive) return;
    
    // Deactivate current active tab
    if (this.activeTabId) {
      const currentActive = this.tabs.get(this.activeTabId);
      if (currentActive) {
        currentActive.isActive = false;
        currentActive.updateUI();
      }
    }
    
    // Activate the new tab
    tab.isActive = true;
    this.activeTabId = tabId;
    tab.updateUI();
    
    // Focus the webview
    if (tab.webview) {
      tab.webview.focus();
    }
    
    return tab;
  }
  
  // Get the currently active tab
  getActiveTab() {
    return this.activeTabId ? this.tabs.get(this.activeTabId) : null;
  }
  
  // Get a tab by its ID
  getTab(tabId) {
    return this.tabs.get(tabId);
  }
  
  // Get all tabs
  getAllTabs() {
    return Array.from(this.tabs.values());
  }
  
  // Get the number of open tabs
  getTabCount() {
    return this.tabs.size;
  }
  
  // Close all tabs
  closeAllTabs() {
    for (const tab of this.tabs.values()) {
      tab.destroy();
    }
    this.tabs.clear();
    this.activeTabId = null;
    
    // Create a new tab
    return this.createTab();
  }
  
  // Get the tab index by tab ID
  getTabIndex(tabId) {
    return Array.from(this.tabs.keys()).indexOf(tabId);
  }
  
  // Handle drag start event
  handleDragStart(e, tabId) {
    this.draggedTab = tabId;
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', tabId);
    e.target.classList.add('dragging');
    
    // Set a custom drag image (optional)
    const rect = e.target.getBoundingClientRect();
    const dragImage = e.target.cloneNode(true);
    dragImage.style.position = 'absolute';
    dragImage.style.top = '-1000px';
    dragImage.style.width = `${rect.width}px`;
    document.body.appendChild(dragImage);
    e.dataTransfer.setDragImage(dragImage, rect.width / 2, rect.height / 2);
    
    // Remove the temporary element after a short delay
    setTimeout(() => document.body.removeChild(dragImage), 0);
  }
  
  // Handle drag over event
  handleDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    
    const targetTab = e.target.closest('.tab');
    const newTabButton = document.getElementById('new-tab');
    
    if (!targetTab || targetTab === newTabButton) {
      // If dragging over the tab bar but not a tab, highlight the new tab button area
      if (newTabButton) {
        newTabButton.classList.add('drag-over');
      }
      return;
    }
    
    // Remove highlight from all tabs
    document.querySelectorAll('.tab').forEach(tab => {
      tab.classList.remove('drag-over-left', 'drag-over-right');
    });
    
    // Calculate position relative to the target tab
    const rect = targetTab.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const isLeftHalf = x < rect.width / 2;
    
    // Highlight the appropriate side of the target tab
    targetTab.classList.add(isLeftHalf ? 'drag-over-left' : 'drag-over-right');
  }
  
  // Handle drop event
  handleDrop(e) {
    e.preventDefault();
    
    const targetTab = e.target.closest('.tab');
    const newTabButton = document.getElementById('new-tab');
    
    // Clear all drag highlights
    document.querySelectorAll('.tab').forEach(tab => {
      tab.classList.remove('drag-over', 'drag-over-left', 'drag-over-right');
    });
    
    if (!this.draggedTab) return;
    
    // If dropping on the new tab button area, move to the end
    if ((!targetTab || targetTab === newTabButton) && newTabButton) {
      this.moveTabToEnd(this.draggedTab);
      return;
    }
    
    const targetTabId = targetTab?.dataset.tabId;
    if (!targetTabId || targetTabId === this.draggedTab) return;
    
    // Determine drop position (left or right of target tab)
    const rect = targetTab.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const isLeftHalf = x < rect.width / 2;
    
    this.moveTabRelativeTo(this.draggedTab, targetTabId, isLeftHalf ? 'before' : 'after');
  }
  
  // Handle drag end event
  handleDragEnd(e) {
    // Clear all drag highlights
    document.querySelectorAll('.tab').forEach(tab => {
      tab.classList.remove('dragging', 'drag-over', 'drag-over-left', 'drag-over-right');
    });
    
    this.draggedTab = null;
  }
  
  // Move a tab to a new position relative to another tab
  moveTabRelativeTo(tabId, targetTabId, position = 'after') {
    if (tabId === targetTabId) return;
    
    const tab = this.tabs.get(tabId);
    const targetTab = this.tabs.get(targetTabId);
    
    if (!tab || !targetTab) return;
    
    // Remove the tab from its current position
    this.tabs.delete(tabId);
    
    // Get all tab IDs in order
    const tabIds = Array.from(this.tabs.keys());
    const targetIndex = tabIds.indexOf(targetTabId);
    
    // Calculate the new position
    let newIndex = position === 'before' ? targetIndex : targetIndex + 1;
    
    // Insert the tab at the new position
    const newTabs = new Map();
    let inserted = false;
    
    Array.from(this.tabs.entries()).forEach(([id, tabData], index) => {
      if (index === newIndex) {
        newTabs.set(tabId, tab);
        inserted = true;
      }
      newTabs.set(id, tabData);
    });
    
    // If we haven't inserted yet, add to the end
    if (!inserted) {
      newTabs.set(tabId, tab);
    }
    
    this.tabs = newTabs;
    this.updateTabOrderInDOM();
  }
  
  // Move a tab to the end of the tab list
  moveTabToEnd(tabId) {
    const tab = this.tabs.get(tabId);
    if (!tab) return;
    
    this.tabs.delete(tabId);
    this.tabs.set(tabId, tab);
    this.updateTabOrderInDOM();
  }
  
  // Update the DOM to match the current tab order
  updateTabOrderInDOM() {
    const tabsContainer = document.getElementById('tabs');
    if (!tabsContainer) return;
    
    // Get all tab elements except the new tab button
    const tabElements = Array.from(tabsContainer.querySelectorAll('.tab:not(#new-tab)'));
    
    // Sort them according to our tabs map
    const sortedTabs = [];
    this.tabs.forEach((tab, tabId) => {
      const tabElement = tabElements.find(el => el.dataset.tabId === tabId);
      if (tabElement) {
        sortedTabs.push(tabElement);
      }
    });
    
    // Re-insert them in the correct order
    const newTabButton = document.getElementById('new-tab');
    sortedTabs.forEach(tabElement => {
      tabsContainer.insertBefore(tabElement, newTabButton);
    });
  }
  
  // Activate the next tab
  activateNextTab() {
    if (!this.activeTabId || this.tabs.size <= 1) return;
    
    const currentIndex = this.getTabIndex(this.activeTabId);
    const nextIndex = (currentIndex + 1) % this.tabs.size;
    const nextTabId = Array.from(this.tabs.keys())[nextIndex];
    
    if (nextTabId) {
      this.activateTab(nextTabId);
    }
  }
  
  // Activate the previous tab
  activatePreviousTab() {
    if (!this.activeTabId || this.tabs.size <= 1) return;
    
    const currentIndex = this.getTabIndex(this.activeTabId);
    const prevIndex = (currentIndex - 1 + this.tabs.size) % this.tabs.size;
    const prevTabId = Array.from(this.tabs.keys())[prevIndex];
    
    if (prevTabId) {
      this.activateTab(prevTabId);
    }
  }

  // Group Management
  // ================


  /**
   * Create a new tab group
   * @param {string} name - Group name
   * @param {string} color - Group color
   * @param {string} [id] - Optional group ID (auto-generated if not provided)
   * @returns {TabGroup} The created group
   */
  createGroup(name, color, id) {
    const groupId = id || generateId();
    const group = new TabGroup(groupId, name, color);
    
    // Set up event listeners
    group.on('tabAdded', this.handleTabAddedToGroup.bind(this));
    group.on('tabRemoved', this.handleTabRemovedFromGroup.bind(this));
    group.on('close', this.handleGroupClose.bind(this));
    group.on('toggle', this.handleGroupToggle.bind(this));
    group.on('rename', this.handleGroupRename.bind(this));
    
    // Create and append group elements
    if (this.groupsContainer) {
      const groupElement = group.createElements();
      this.groupsContainer.appendChild(groupElement);
    }
    
    this.groups.set(groupId, group);
    this.emit('groupCreated', { groupId, name, color });
    
    return group;
  }

  /**
   * Remove a tab group
   * @param {string} groupId - ID of the group to remove
   * @param {boolean} [moveTabsToDefault=true] - Whether to move tabs to default group
   */
  removeGroup(groupId, moveTabsToDefault = true) {
    if (groupId === DEFAULT_GROUP_ID) {
      console.warn('Cannot remove the default group');
      return;
    }
    
    const group = this.groups.get(groupId);
    if (!group) return;
    
    // Move tabs to default group if specified
    if (moveTabsToDefault) {
      const tabIds = Array.from(group.tabIds);
      tabIds.forEach(tabId => {
        this.moveTabToGroup(tabId, DEFAULT_GROUP_ID);
      });
    }
    
    // Remove group element
    if (group.element && group.element.parentNode) {
      group.element.remove();
    }
    
    this.groups.delete(groupId);
    this.emit('groupRemoved', { groupId });
    
    // If active group was removed, switch to default
    if (this.activeGroupId === groupId) {
      this.activateGroup(DEFAULT_GROUP_ID);
    }
  }

  /**
   * Move a tab to a different group
   * @param {string} tabId - ID of the tab to move
   * @param {string} targetGroupId - ID of the target group
   */
  moveTabToGroup(tabId, targetGroupId) {
    const tab = this.tabs.get(tabId);
    const targetGroup = this.groups.get(targetGroupId);
    
    if (!tab || !targetGroup) return;
    
    // Remove from current group if any
    if (tab.groupId) {
      const currentGroup = this.groups.get(tab.groupId);
      currentGroup?.removeTab(tabId);
    }
    
    // Add to target group
    tab.groupId = targetGroupId;
    targetGroup.addTab(tabId);
    
    // Move tab element in DOM if needed
    if (tab.element && targetGroup.tabsContainer) {
      targetGroup.tabsContainer.appendChild(tab.element);
    }
    
    this.emit('tabGroupChanged', { tabId, groupId: targetGroupId });
  }

  /**
   * Activate a tab group
   * @param {string} groupId - ID of the group to activate
   */
  activateGroup(groupId) {
    if (!this.groups.has(groupId)) return;
    
    this.activeGroupId = groupId;
    
    // Update UI
    this.groups.forEach((group, id) => {
      group.element?.classList.toggle('active', id === groupId);
    });
    
    this.emit('groupActivated', { groupId });
  }

  // Event Handlers
  // =============

  
  handleTabAddedToGroup({ groupId, tabId }) {
    const group = this.groups.get(groupId);
    const tab = this.tabs.get(tabId);
    
    if (group && tab) {
      // Update tab's group indicator
      tab.element?.setAttribute('data-group-id', groupId);
      
      // Move tab to group's container if it exists
      if (group.tabsContainer && tab.element) {
        group.tabsContainer.appendChild(tab.element);
      }
    }
  }
  
  handleTabRemovedFromGroup({ groupId, tabId }) {
    const tab = this.tabs.get(tabId);
    if (tab) {
      tab.element?.removeAttribute('data-group-id');
    }
  }
  
  handleGroupClose({ groupId }) {
    this.removeGroup(groupId);
  }
  
  handleGroupToggle({ groupId, collapsed }) {
    // Update UI based on group collapse state
    const group = this.groups.get(groupId);
    if (group) {
      group.tabsContainer.style.display = collapsed ? 'none' : 'block';
    }
  }
  
  handleGroupRename({ groupId, oldName, newName }) {
    // Update group name in UI if needed
    const group = this.groups.get(groupId);
    if (group && group.nameElement) {
      group.nameElement.textContent = newName;
    }
  }

  // Persistence
  // ==========
  
  /**
   * Save the current tab and group state
   */
  saveState() {
    // Save tabs
    const tabsData = Array.from(this.tabs.entries()).map(([id, tab]) => ({
      id,
      url: tab.url,
      title: tab.title,
      favicon: tab.favicon,
      groupId: tab.groupId || DEFAULT_GROUP_ID,
      active: id === this.activeTabId
    }));
    
    // Save groups
    const groupsData = Array.from(this.groups.entries()).map(([id, group]) => ({
      id,
      name: group.name,
      color: group.color,
      collapsed: group.collapsed,
      tabIds: Array.from(group.tabIds)
    }));
    
    // Save window state
    const windowState = {
      activeTabId: this.activeTabId,
      activeGroupId: this.activeGroupId,
      version: 1
    };
    
    // Persist to storage
    saveToStorage(STORAGE_KEYS.TABS, tabsData);
    saveToStorage(STORAGE_KEYS.GROUPS, groupsData);
    saveToStorage(STORAGE_KEYS.WINDOW_STATE, windowState);
    
    this.emit('stateSaved');
  }
  
  /**
   * Load saved tab and group state
   */
  async loadState() {
    // Load saved state
    const tabsData = loadFromStorage(STORAGE_KEYS.TABS, []);
    const groupsData = loadFromStorage(STORAGE_KEYS.GROUPS, []);
    const windowState = loadFromStorage(STORAGE_KEYS.WINDOW_STATE, {});
    
    // Restore groups first
    groupsData.forEach(groupData => {
      const group = this.createGroup(groupData.name, groupData.color, groupData.id);
      if (groupData.collapsed) {
        group.toggle();
      }
    });
    
    // Then restore tabs
    for (const tabData of tabsData) {
      const tab = await this.createTab(tabData.url, { 
        activate: false,
        groupId: tabData.groupId 
      });
      
      if (tab) {
        // Restore tab properties
        tab.title = tabData.title || 'New Tab';
        tab.favicon = tabData.favicon || '';
        
        // Update tab UI
        const titleElement = tab.element?.querySelector('.tab-title');
        const faviconElement = tab.element?.querySelector('.tab-favicon');
        
        if (titleElement) titleElement.textContent = tab.title;
        if (faviconElement && tab.favicon) faviconElement.src = tab.favicon;
      }
    }
    
    // Restore window state
    if (windowState.activeTabId && this.tabs.has(windowState.activeTabId)) {
      this.activateTab(windowState.activeTabId);
    }
    
    if (windowState.activeGroupId && this.groups.has(windowState.activeGroupId)) {
      this.activateGroup(windowState.activeGroupId);
    } else {
      this.activateGroup(DEFAULT_GROUP_ID);
    }
    
    this.emit('stateLoaded');
  }
}
