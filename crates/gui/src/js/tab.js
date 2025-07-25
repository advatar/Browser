// Tab class represents a single browser tab
export class Tab {
  constructor(id, url = 'about:blank', groupId = '') {
    this.id = id;
    this.webviewId = `webview-${id}`;
    this.title = 'New Tab';
    this.url = url;
    this.favicon = 'data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0iIzQyODVGNCIgZD0iTTEyLDBDNS4zNzMsMCwwLDUuMzczLDAsMTJzNS4zNzMsMTIsMTIsMTJzMTItNS4zNzMsMTItMTJTMTguNjI3LDAsMTIsMHoiLz48L3N2Zz4=';
    this.groupId = groupId; // Track which group this tab belongs to
    this.canGoBack = false;
    this.canGoForward = false;
    this.isLoading = false;
    this.isActive = false;
    this.element = null;
    this.webview = null;
    this.container = null;
  }

  // Create the DOM elements for this tab
  createElements() {
    // Create container for the webview
    this.container = document.createElement('div');
    this.container.id = `webview-container-${this.id}`;
    this.container.className = 'webview-container';
    this.container.style.display = 'none';

    // Create the webview
    this.webview = document.createElement('webview');
    this.webview.id = this.webviewId;
    this.webview.src = this.url;
    this.webview.setAttribute('partition', 'persist:default');
    this.webview.setAttribute('webpreferences', 'contextIsolation=yes,nodeIntegration=no');
    
    this.container.appendChild(this.webview);
    document.getElementById('app').appendChild(this.container);

    // Create the tab element
    const tabTemplate = document.getElementById('tab-template');
    this.element = tabTemplate.content.cloneNode(true).firstElementChild;
    this.element.dataset.tabId = this.id;
    this.element.querySelector('.tab-title').textContent = this.title;
    this.element.querySelector('.tab-favicon').src = this.favicon;

    // Set up close button
    const closeButton = this.element.querySelector('.tab-close');
    closeButton.onclick = (e) => {
      e.stopPropagation();
      this.emit('close', this.id);
    };

    // Set up click handler to activate tab
    this.element.onclick = (e) => {
      // Don't activate if clicking the close button
      if (e.target !== closeButton && !closeButton.contains(e.target)) {
        this.emit('activate', this.id);
      }
    };
    
    // Set up drag and drop
    this.element.draggable = true;
    this.element.setAttribute('draggable', 'true');
    
    this.element.addEventListener('dragstart', (e) => {
      this.emit('dragStart', e, this.id);
    });
    
    this.element.addEventListener('dragend', () => {
      this.element.classList.remove('dragging');
    });
    
    // Prevent drag events from bubbling up to parent elements
    this.element.addEventListener('drag', (e) => {
      e.stopPropagation();
    });

    // Add tab to the tab bar (before the new tab button)
    const tabsContainer = document.getElementById('tabs');
    tabsContainer.insertBefore(this.element, document.getElementById('new-tab'));
  }

  // Update the tab's UI to reflect its current state
  updateUI() {
    if (!this.element) return;

    const titleElement = this.element.querySelector('.tab-title');
    const faviconElement = this.element.querySelector('.tab-favicon');
    
    titleElement.textContent = this.title || 'New Tab';
    faviconElement.src = this.favicon;

    if (this.isActive) {
      this.element.classList.add('active');
      this.container.style.display = 'block';
      document.title = `${this.title} - Decentralized Browser`;
    } else {
      this.element.classList.remove('active');
      this.container.style.display = 'none';
    }

    if (this.isLoading) {
      this.element.classList.add('loading');
    } else {
      this.element.classList.remove('loading');
    }
  }

  // Clean up the tab's resources
  destroy() {
    if (this.element && this.element.parentNode) {
      this.element.remove();
    }
    if (this.container && this.container.parentNode) {
      this.container.remove();
    }
  }

  // Simple event emitter pattern
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
