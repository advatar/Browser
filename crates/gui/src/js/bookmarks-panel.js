import { getFaviconUrl } from './utils.js';

export class BookmarksPanel {
  constructor(bookmarkManager, eventBus) {
    this.bookmarkManager = bookmarkManager;
    this.eventBus = eventBus;
    this.isVisible = false;
    this.searchQuery = '';
    this.expandedFolders = new Set(['root']);

    this.createElement();
    this.setupEventListeners();

    if (this.eventBus && typeof this.eventBus.subscribe === 'function') {
      ['bookmarkAdded', 'bookmarkRemoved', 'bookmarkUpdated', 'folderAdded', 'folderRemoved', 'folderUpdated']
        .forEach((event) => this.eventBus.subscribe(event, () => this.render()));
    }
  }

  createElement() {
    this.element = document.createElement('div');
    this.element.className = 'bookmarks-panel';
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
    this.render();
  }

  hide() {
    this.isVisible = false;
    this.element.style.display = 'none';
  }

  render() {
    const content = this.searchQuery
      ? this.renderSearchResults()
      : this.renderFolder(this.bookmarkManager.getRootFolder(), 0);

    this.element.innerHTML = `
      <div class="bookmarks-panel-header">
        <h2>Bookmarks</h2>
        <button class="bookmarks-close-btn" title="Close">×</button>
      </div>
      <div class="bookmarks-panel-controls">
        <input type="text" class="bookmarks-panel-search" placeholder="Search bookmarks..." value="${this.escapeHtml(this.searchQuery)}">
      </div>
      <div class="bookmarks-panel-content">
        ${content}
      </div>
    `;

    this.setupEventListeners();
  }

  renderSearchResults() {
    const results = this.bookmarkManager.searchBookmarks(this.searchQuery)
      .filter((item) => item && item.url);

    if (results.length === 0) {
      return `<div class="bookmarks-empty">No bookmarks found</div>`;
    }

    return `
      <div class="bookmarks-panel-list">
        ${results.map((item) => this.renderBookmark(item, 0)).join('')}
      </div>
    `;
  }

  renderFolder(folder, level) {
    if (!folder) return '';
    const isExpanded = this.expandedFolders.has(folder.id);
    const children = folder.children || [];

    return `
      <div class="bookmarks-panel-folder" data-folder-id="${folder.id}">
        <div class="bookmarks-panel-folder-header" style="padding-left: ${level * 16}px">
          <span class="folder-toggle">${isExpanded ? '▼' : '▶'}</span>
          <span class="folder-icon">📁</span>
          <span class="folder-name">${this.escapeHtml(folder.name)}</span>
        </div>
        <div class="bookmarks-panel-folder-contents" style="display: ${isExpanded ? 'block' : 'none'}">
          ${children.map((child) => {
            if (!child) return '';
            if ('url' in child) {
              return this.renderBookmark(child, level + 1);
            }
            if ('children' in child) {
              return this.renderFolder(child, level + 1);
            }
            return '';
          }).join('')}
        </div>
      </div>
    `;
  }

  renderBookmark(bookmark, level) {
    const title = this.escapeHtml(bookmark.title || bookmark.url);
    const url = this.escapeHtml(bookmark.url);
    const favicon = bookmark.favicon || getFaviconUrl(bookmark.url);

    return `
      <div class="bookmarks-panel-item" data-bookmark-id="${bookmark.id}" style="padding-left: ${level * 16 + 16}px">
        <img src="${favicon}" alt="" class="bookmarks-panel-favicon" onerror="this.style.display='none'">
        <div class="bookmarks-panel-text">
          <div class="bookmarks-panel-title">${title}</div>
          <div class="bookmarks-panel-url">${url}</div>
        </div>
      </div>
    `;
  }

  setupEventListeners() {
    if (!this.element) return;

    const closeBtn = this.element.querySelector('.bookmarks-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', () => this.hide());
    }

    const searchInput = this.element.querySelector('.bookmarks-panel-search');
    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        this.searchQuery = e.target.value;
        this.render();
      });
    }

    this.element.addEventListener('click', (e) => {
      const folderHeader = e.target.closest('.bookmarks-panel-folder-header');
      if (folderHeader) {
        const folder = folderHeader.closest('.bookmarks-panel-folder');
        const folderId = folder?.dataset.folderId;
        if (folderId) {
          if (this.expandedFolders.has(folderId)) {
            this.expandedFolders.delete(folderId);
          } else {
            this.expandedFolders.add(folderId);
          }
          this.render();
        }
        return;
      }

      const bookmarkItem = e.target.closest('.bookmarks-panel-item');
      if (bookmarkItem) {
        const bookmarkId = bookmarkItem.dataset.bookmarkId;
        const bookmark = this.bookmarkManager.getBookmark(bookmarkId);
        if (bookmark && bookmark.url) {
          if (e.metaKey || e.ctrlKey) {
            this.eventBus.publish('createTab', { url: bookmark.url });
          } else {
            this.eventBus.publish('navigate', { url: bookmark.url });
            this.hide();
          }
        }
      }
    });
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text || '';
    return div.innerHTML;
  }
}
