import { EventBus, EventCallback, Bookmark, BookmarkFolder, EventType } from '@/types';
import { debounce } from '@/utils';

export class BookmarkManager {
  private bookmarks: Map<string, Bookmark> = new Map();
  private folders: Map<string, BookmarkFolder> = new Map();
  private rootFolderId: string;
  private eventBus: EventBus;
  private saveToStorage: () => void;

  constructor(eventBus: EventBus) {
    this.eventBus = eventBus;
    this.rootFolderId = 'root';
    this.initializeRootFolder();
    this.loadBookmarks();
    
    // Debounce save to prevent excessive writes
    this.saveToStorage = debounce(() => this.saveBookmarks(), 500);
  }

  private initializeRootFolder(): void {
    if (!this.folders.has(this.rootFolderId)) {
      const rootFolder: BookmarkFolder = {
        id: this.rootFolderId,
        name: 'Bookmarks',
        parentId: null,
        children: [],
        dateAdded: Date.now(),
        dateModified: Date.now(),
      };
      this.folders.set(this.rootFolderId, rootFolder);
    }
  }

  private loadBookmarks(): void {
    try {
      // Load bookmarks from storage
      const storedBookmarks = localStorage.getItem('bookmarks');
      const storedFolders = localStorage.getItem('bookmarkFolders');

      if (storedBookmarks) {
        const bookmarks = JSON.parse(storedBookmarks);
        bookmarks.forEach((bookmark: Bookmark) => {
          this.bookmarks.set(bookmark.id, bookmark);
        });
      }

      if (storedFolders) {
        const folders = JSON.parse(storedFolders);
        folders.forEach((folder: BookmarkFolder) => {
          this.folders.set(folder.id, folder);
        });
      }
    } catch (error) {
      console.error('Error loading bookmarks:', error);
    }
  }

  private saveBookmarks(): void {
    try {
      localStorage.setItem(
        'bookmarks',
        JSON.stringify(Array.from(this.bookmarks.values()))
      );
      localStorage.setItem(
        'bookmarkFolders',
        JSON.stringify(Array.from(this.folders.values()))
      );
    } catch (error) {
      console.error('Error saving bookmarks:', error);
    }
  }

  addBookmark(bookmark: Omit<Bookmark, 'id' | 'dateAdded'>, parentId: string = this.rootFolderId): Bookmark {
    const id = `bookmark-${Date.now()}`;
    const newBookmark: Bookmark = {
      ...bookmark,
      id,
      dateAdded: Date.now(),
    };

    this.bookmarks.set(id, newBookmark);
    this.addToFolder(id, parentId);
    this.saveToStorage();
    
    this.eventBus.publish('bookmarkAdded', { bookmark: newBookmark, parentId });
    return newBookmark;
  }

  removeBookmark(bookmarkId: string): void {
    const bookmark = this.bookmarks.get(bookmarkId);
    if (!bookmark) return;

    // Remove from parent folder
    const parent = this.findParent(bookmarkId);
    if (parent) {
      parent.children = parent.children.filter(child => 
        !('id' in child) || child.id !== bookmarkId
      );
      this.updateFolder(parent.id, { dateModified: Date.now() });
    }

    this.bookmarks.delete(bookmarkId);
    this.saveToStorage();
    
    this.eventBus.publish('bookmarkRemoved', { bookmarkId });
  }

  updateBookmark(bookmarkId: string, updates: Partial<Omit<Bookmark, 'id' | 'dateAdded'>>): Bookmark | null {
    const bookmark = this.bookmarks.get(bookmarkId);
    if (!bookmark) return null;

    const updatedBookmark = {
      ...bookmark,
      ...updates,
      dateModified: Date.now(),
    };

    this.bookmarks.set(bookmarkId, updatedBookmark);
    this.saveToStorage();
    
    this.eventBus.publish('bookmarkUpdated', { bookmark: updatedBookmark });
    return updatedBookmark;
  }

  createFolder(name: string, parentId: string = this.rootFolderId): BookmarkFolder {
    const id = `folder-${Date.now()}`;
    const newFolder: BookmarkFolder = {
      id,
      name,
      parentId,
      children: [],
      dateAdded: Date.now(),
      dateModified: Date.now(),
    };

    this.folders.set(id, newFolder);
    this.addToFolder(id, parentId);
    this.saveToStorage();
    
    return newFolder;
  }

  removeFolder(folderId: string): void {
    if (folderId === this.rootFolderId) {
      throw new Error('Cannot remove the root folder');
    }

    const folder = this.folders.get(folderId);
    if (!folder) return;

    // Remove all children
    folder.children.forEach(child => {
      if ('children' in child) {
        this.removeFolder(child.id);
      } else {
        this.removeBookmark(child.id);
      }
    });

    // Remove from parent
    const parent = this.findParent(folderId);
    if (parent) {
      parent.children = parent.children.filter(child => 
        !('id' in child) || child.id !== folderId
      );
      this.updateFolder(parent.id, { dateModified: Date.now() });
    }

    this.folders.delete(folderId);
    this.saveToStorage();
  }

  updateFolder(folderId: string, updates: Partial<Omit<BookmarkFolder, 'id' | 'children'>>): BookmarkFolder | null {
    const folder = this.folders.get(folderId);
    if (!folder) return null;

    const updatedFolder = {
      ...folder,
      ...updates,
      dateModified: Date.now(),
    };

    this.folders.set(folderId, updatedFolder);
    this.saveToStorage();
    
    return updatedFolder;
  }

  getBookmark(bookmarkId: string): Bookmark | null {
    return this.bookmarks.get(bookmarkId) || null;
  }

  getFolder(folderId: string): BookmarkFolder | null {
    return this.folders.get(folderId) || null;
  }

  getRootFolder(): BookmarkFolder {
    return this.getFolder(this.rootFolderId)!;
  }

  getBookmarksByUrl(url: string): Bookmark[] {
    return Array.from(this.bookmarks.values()).filter(
      bookmark => bookmark.url === url
    );
  }

  searchBookmarks(query: string): (Bookmark | BookmarkFolder)[] {
    const results: (Bookmark | BookmarkFolder)[] = [];
    const lowerQuery = query.toLowerCase();

    // Search in bookmarks
    for (const bookmark of this.bookmarks.values()) {
      if (bookmark.title.toLowerCase().includes(lowerQuery) || 
          bookmark.url.toLowerCase().includes(lowerQuery)) {
        results.push(bookmark);
      }
    }

    // Search in folder names
    for (const folder of this.folders.values()) {
      if (folder.name.toLowerCase().includes(lowerQuery)) {
        results.push(folder);
      }
    }

    return results;
  }

  private addToFolder(itemId: string, folderId: string): void {
    const folder = this.folders.get(folderId);
    if (!folder) return;

    const item = this.bookmarks.get(itemId) || this.folders.get(itemId);
    if (!item) return;

    // Check if item is already in the folder
    const exists = folder.children.some(child => 
      (child as { id: string }).id === itemId
    );

    if (!exists) {
      folder.children.push(item);
      folder.dateModified = Date.now();
      this.saveToStorage();
    }
  }

  private findItemInFolder(folder: BookmarkFolder, itemId: string): Bookmark | BookmarkFolder | null {
    for (const child of folder.children) {
      const childId = 'id' in child ? child.id : (child as Bookmark).id;
      if (childId === itemId) {
        return child;
      }
      
      if ('children' in child) {
        const found = this.findItemInFolder(child, itemId);
        if (found) return found;
      }
    }
    return null;
  }

  private findParent(itemId: string): BookmarkFolder | null {
    for (const folder of this.folders.values()) {
      const found = this.findItemInFolder(folder, itemId);
      if (found) return folder;
    }
    return null;
  }

  // Import/Export functionality
  exportBookmarks(): string {
    return JSON.stringify({
      bookmarks: Array.from(this.bookmarks.values()),
      folders: Array.from(this.folders.values()),
      version: 1,
      date: new Date().toISOString(),
    }, null, 2);
  }

  importBookmarks(json: string): void {
    try {
      const data = JSON.parse(json);
      
      if (!data.bookmarks || !data.folders) {
        throw new Error('Invalid bookmarks format');
      }

      // Clear existing bookmarks
      this.bookmarks.clear();
      this.folders.clear();
      this.initializeRootFolder();

      // Import folders
      data.folders.forEach((folder: BookmarkFolder) => {
        this.folders.set(folder.id, {
          ...folder,
          children: [] // We'll repopulate children after
        });
      });

      // Import bookmarks
      data.bookmarks.forEach((bookmark: Bookmark) => {
        this.bookmarks.set(bookmark.id, bookmark);
      });

      // Rebuild folder hierarchy
      data.folders.forEach((folder: BookmarkFolder) => {
        const currentFolder = this.folders.get(folder.id);
        if (currentFolder && folder.children) {
          currentFolder.children = folder.children.map(child => {
            const childId = 'id' in child ? child.id : (child as Bookmark).id;
            return this.bookmarks.get(childId) || this.folders.get(childId) || null;
          }).filter((item): item is Bookmark | BookmarkFolder => item !== null);
        }
      });

      this.saveToStorage();
      this.eventBus.publish('bookmarkAdded' as EventType, {});
    } catch (error) {
      console.error('Error importing bookmarks:', error);
      throw new Error('Failed to import bookmarks');
    }
  }
}
