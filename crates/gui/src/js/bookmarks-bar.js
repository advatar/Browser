import { BookmarkManager } from '../features/bookmarks';
import { getFaviconUrl } from './utils.js';

export class BookmarksBar {
  constructor(containerId, eventBus) {
    this.container = document.getElementById(containerId);
    if (!this.container) {
      console.error(`BookmarksBar: Container with id "${containerId}" not found`);
      return;
    }
    
    this.eventBus = eventBus;
    this.bookmarkManager = new BookmarkManager(eventBus);
    this.expandedFolders = new Set();
    this.isVisible = false;
    
    this.initialize();
  }
  
  initialize() {
    this.container.classList.add('bookmarks-bar');
    this.render();
    this.setupEventListeners();
    
    // Subscribe to bookmark updates
    this.eventBus.subscribe('bookmarkAdded', () => this.render());
    this.eventBus.subscribe('bookmarkRemoved', () => this.render());
    this.eventBus.subscribe('bookmarkUpdated', () => this.render());
    this.eventBus.subscribe('folderAdded', () => this.render());
    this.eventBus.subscribe('folderRemoved', () => this.render());
    this.eventBus.subscribe('folderUpdated', () => this.render());
  }
  
  render() {
    const rootFolder = this.bookmarkManager.getFolder('root');
    if (!rootFolder) return;
    
    this.container.innerHTML = `
      <div class="bookmarks-toolbar">
        <button class="bookmarks-button" title="Show bookmarks">
          <span class="bookmarks-icon">★</span>
          <span class="bookmarks-text">Bookmarks</span>
        </button>
        <div class="bookmarks-dropdown" style="display: ${this.isVisible ? 'block' : 'none'}">
          <div class="bookmarks-header">
            <input type="text" class="bookmarks-search" placeholder="Search bookmarks...">
          </div>
          <div class="bookmarks-list">
            ${this.renderFolder(rootFolder, 0)}
          </div>
        </div>
      </div>
    `;
    
    // Re-attach event listeners
    this.setupEventListeners();
  }
  
  renderFolder(folder, level) {
    const isExpanded = this.expandedFolders.has(folder.id);
    const children = folder.children || [];
    
    return `
      <div class="bookmark-folder" data-folder-id="${folder.id}">
        <div class="folder-header" style="padding-left: ${level * 16}px">
          <span class="folder-toggle">${isExpanded ? '▼' : '▶'}</span>
          <span class="folder-icon">📁</span>
          <span class="folder-name">${folder.name}</span>
        </div>
        <div class="folder-contents" style="display: ${isExpanded ? 'block' : 'none'}">
          ${children.map(item => 
            'url' in item 
              ? this.renderBookmark(item, level + 1) 
              : this.renderFolder(this.bookmarkManager.getFolder(item.id), level + 1)
          ).join('')}
        </div>
      </div>
    `;
  }
  
  renderBookmark(bookmark, level) {
    return `
      <a href="${bookmark.url}" class="bookmark-item" data-bookmark-id="${bookmark.id}" style="padding-left: ${level * 16 + 16}px">
        <img src="${bookmark.favicon || getFaviconUrl(bookmark.url)}" class="bookmark-favicon" onerror="this.src='${getFaviconUrl(bookmark.url)}'" />
        <span class="bookmark-title">${bookmark.title || bookmark.url}</span>
      </a>
    `;
  }
  
  setupEventListeners() {
    // Toggle bookmarks dropdown
    const button = this.container.querySelector('.bookmarks-button');
    if (button) {
      button.addEventListener('click', (e) => {
        e.stopPropagation();
        this.toggleDropdown();
      });
    }
    
    // Close dropdown when clicking outside
    document.addEventListener('click', (e) => {
      if (!this.container.contains(e.target)) {
        this.hideDropdown();
      }
    });
    
    // Handle folder toggles
    this.container.addEventListener('click', (e) => {
      const folderHeader = e.target.closest('.folder-header');
      if (!folderHeader) return;
      
      const folder = folderHeader.closest('.bookmark-folder');
      const folderId = folder?.dataset.folderId;
      if (folderId) {
        this.toggleFolder(folderId);
      }
    });
    
    // Handle bookmark clicks
    this.container.addEventListener('click', (e) => {
      const bookmarkLink = e.target.closest('.bookmark-item');
      if (!bookmarkLink) return;
      
      e.preventDefault();
      const url = bookmarkLink.href;
      this.eventBus.publish('navigate', { url });
      this.hideDropdown();
    });
  }
  
  toggleDropdown() {
    this.isVisible = !this.isVisible;
    const dropdown = this.container.querySelector('.bookmarks-dropdown');
    if (dropdown) {
      dropdown.style.display = this.isVisible ? 'block' : 'none';
    }
  }
  
  hideDropdown() {
    this.isVisible = false;
    const dropdown = this.container.querySelector('.bookmarks-dropdown');
    if (dropdown) {
      dropdown.style.display = 'none';
    }
  }
  
  toggleFolder(folderId) {
    if (this.expandedFolders.has(folderId)) {
      this.expandedFolders.delete(folderId);
    } else {
      this.expandedFolders.add(folderId);
    }
    this.render();
  }
}
