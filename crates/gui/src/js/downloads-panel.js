export class DownloadsPanel {
  constructor(eventBus) {
    this.eventBus = eventBus;
    this.isVisible = false;
    this.downloads = [];
    this.refreshTimer = null;
    this.invoke =
      window.__TAURI__ && window.__TAURI__.core && window.__TAURI__.core.invoke
        ? window.__TAURI__.core.invoke
        : null;

    this.createElement();
    this.setupEventListeners();
  }

  createElement() {
    this.element = document.createElement('div');
    this.element.className = 'downloads-panel';
    this.element.style.display = 'none';
    document.body.appendChild(this.element);
    this.render();
  }

  toggle() {
    if (this.isVisible) {
      this.hide();
    } else {
      this.show();
    }
  }

  show() {
    this.isVisible = true;
    this.element.style.display = 'flex';
    this.refresh();
    this.refreshTimer = setInterval(() => this.refresh(), 2000);
  }

  hide() {
    this.isVisible = false;
    this.element.style.display = 'none';
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }
  }

  async refresh() {
    this.downloads = await this.fetchDownloads();
    this.render();
  }

  async fetchDownloads() {
    if (!this.invoke) return this.downloads;
    try {
      const downloads = await this.invoke('get_downloads');
      return Array.isArray(downloads) ? downloads : [];
    } catch (e) {
      console.error('Failed to fetch downloads:', e);
      return this.downloads;
    }
  }

  render() {
    const content =
      this.downloads.length === 0
        ? `<div class="downloads-empty">No downloads yet</div>`
        : `<div class="downloads-list">
            ${this.downloads.map((item) => this.renderDownloadItem(item)).join('')}
          </div>`;

    this.element.innerHTML = `
      <div class="downloads-panel-header">
        <h2>Downloads</h2>
        <button class="downloads-close-btn" title="Close">×</button>
      </div>
      <div class="downloads-panel-actions">
        <button class="downloads-refresh-btn">Refresh</button>
        <button class="downloads-clear-btn">Clear Completed</button>
      </div>
      <div class="downloads-panel-content">
        ${content}
      </div>
    `;

    this.setupEventListeners();
  }

  renderDownloadItem(item) {
    const filename = this.escapeHtml(item.filename || item.url || 'download');
    const url = this.escapeHtml(item.url || '');
    const received = Number(item.received_bytes || 0);
    const total = item.total_bytes ? Number(item.total_bytes) : null;
    const progress = total ? Math.min((received / total) * 100, 100) : null;
    const { label, badge } = this.normalizeState(item.state);

    return `
      <div class="downloads-item">
        <div class="downloads-item-info">
          <div class="downloads-item-title">${filename}</div>
          <div class="downloads-item-url">${url}</div>
          <div class="downloads-item-meta">
            <span>${this.formatBytes(received)}${total ? ` / ${this.formatBytes(total)}` : ''}</span>
            <span class="downloads-item-status ${badge}">${label}</span>
          </div>
        </div>
        <div class="downloads-item-progress">
          <div class="downloads-progress-bar">
            <div class="downloads-progress-fill" style="width: ${progress !== null ? progress : 0}%"></div>
          </div>
          ${progress !== null ? `<div class="downloads-progress-text">${Math.round(progress)}%</div>` : ''}
        </div>
      </div>
    `;
  }

  normalizeState(state) {
    if (!state) return { label: 'Unknown', badge: 'unknown' };
    if (typeof state === 'string') {
      if (state === 'InProgress') return { label: 'In progress', badge: 'in-progress' };
      if (state === 'Completed') return { label: 'Completed', badge: 'completed' };
      if (state === 'Cancelled') return { label: 'Cancelled', badge: 'cancelled' };
    }
    if (typeof state === 'object' && state.Failed) {
      return { label: `Failed: ${state.Failed}`, badge: 'failed' };
    }
    return { label: 'Unknown', badge: 'unknown' };
  }

  formatBytes(bytes) {
    if (!bytes && bytes !== 0) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = bytes === 0 ? 0 : Math.floor(Math.log(bytes) / Math.log(1024));
    return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${sizes[i]}`;
  }

  setupEventListeners() {
    if (!this.element) return;

    const closeBtn = this.element.querySelector('.downloads-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', () => this.hide());
    }

    const refreshBtn = this.element.querySelector('.downloads-refresh-btn');
    if (refreshBtn) {
      refreshBtn.addEventListener('click', () => this.refresh());
    }

    const clearBtn = this.element.querySelector('.downloads-clear-btn');
    if (clearBtn) {
      clearBtn.addEventListener('click', () => {
        this.downloads = this.downloads.filter((item) => {
          const { badge } = this.normalizeState(item.state);
          return badge === 'in-progress';
        });
        this.render();
      });
    }
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  }
}
