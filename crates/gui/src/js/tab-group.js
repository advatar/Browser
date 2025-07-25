/**
 * Represents a group of tabs
 */
export class TabGroup {
  constructor(id, name = 'New Group', color = '#4a90e2') {
    this.id = id;
    this.name = name;
    this.color = color;
    this.tabIds = new Set();
    this.collapsed = false;
    this.element = null;
    this.headerElement = null;
    this.tabsContainer = null;
  }

  /**
   * Create the DOM elements for this group
   */
  createElements() {
    // Create group container
    this.element = document.createElement('div');
    this.element.className = 'tab-group';
    this.element.dataset.groupId = this.id;
    this.element.style.borderLeft = `3px solid ${this.color}`;

    // Create group header
    this.headerElement = document.createElement('div');
    this.headerElement.className = 'tab-group-header';
    
    // Add toggle button
    const toggleBtn = document.createElement('button');
    toggleBtn.className = 'tab-group-toggle';
    toggleBtn.innerHTML = '▼';
    toggleBtn.onclick = () => this.toggle();
    
    // Add group name
    const nameElement = document.createElement('span');
    nameElement.className = 'tab-group-name';
    nameElement.textContent = this.name;
    nameElement.contentEditable = true;
    nameElement.onblur = (e) => this.rename(e.target.textContent);
    nameElement.onkeydown = (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        e.target.blur();
      }
    };
    
    // Add tab count
    const countElement = document.createElement('span');
    countElement.className = 'tab-group-count';
    countElement.textContent = this.tabIds.size;
    
    // Add close button
    const closeBtn = document.createElement('button');
    closeBtn.className = 'tab-group-close';
    closeBtn.innerHTML = '×';
    closeBtn.onclick = (e) => {
      e.stopPropagation();
      this.emit('close', this.id);
    };
    
    // Assemble header
    this.headerElement.appendChild(toggleBtn);
    this.headerElement.appendChild(nameElement);
    this.headerElement.appendChild(countElement);
    this.headerElement.appendChild(closeBtn);
    
    // Create tabs container
    this.tabsContainer = document.createElement('div');
    this.tabsContainer.className = 'tab-group-tabs';
    
    // Assemble group
    this.element.appendChild(this.headerElement);
    this.element.appendChild(this.tabsContainer);
    
    return this.element;
  }

  /**
   * Add a tab to this group
   * @param {string} tabId - ID of the tab to add
   */
  addTab(tabId) {
    if (!this.tabIds.has(tabId)) {
      this.tabIds.add(tabId);
      this.updateCount();
      this.emit('tabAdded', { groupId: this.id, tabId });
    }
  }

  /**
   * Remove a tab from this group
   * @param {string} tabId - ID of the tab to remove
   */
  removeTab(tabId) {
    if (this.tabIds.delete(tabId)) {
      this.updateCount();
      this.emit('tabRemoved', { groupId: this.id, tabId });
    }
  }

  /**
   * Toggle group collapse/expand state
   */
  toggle() {
    this.collapsed = !this.collapsed;
    this.element.classList.toggle('collapsed', this.collapsed);
    this.emit('toggle', { groupId: this.id, collapsed: this.collapsed });
  }

  /**
   * Rename the group
   * @param {string} newName - New name for the group
   */
  rename(newName) {
    if (newName && newName !== this.name) {
      const oldName = this.name;
      this.name = newName;
      this.emit('rename', { groupId: this.id, oldName, newName });
    }
  }

  /**
   * Change the group color
   * @param {string} color - New color for the group
   */
  setColor(color) {
    if (color !== this.color) {
      this.color = color;
      this.element.style.borderLeftColor = color;
      this.emit('colorChange', { groupId: this.id, color });
    }
  }

  /**
   * Update the tab count display
   */
  updateCount() {
    const countElement = this.headerElement?.querySelector('.tab-group-count');
    if (countElement) {
      countElement.textContent = this.tabIds.size;
    }
  }

  /**
   * Get the group data for serialization
   */
  toJSON() {
    return {
      id: this.id,
      name: this.name,
      color: this.color,
      tabIds: Array.from(this.tabIds),
      collapsed: this.collapsed
    };
  }

  /**
   * Simple event emitter pattern
   */
  on(event, callback) {
    if (!this._events) this._events = {};
    if (!this._events[event]) this._events[event] = [];
    this._events[event].push(callback);
  }

  emit(event, ...args) {
    if (!this._events || !this._events[event]) return;
    for (const callback of this._events[event]) {
      callback(...args);
    }
  }
}
