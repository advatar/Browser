/**
 * Core types for the browser application
 */

/** Represents a browser tab */
export interface Tab {
  id: string;
  url: string;
  title: string;
  favicon: string;
  loading: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
  lastActive: number;
  groupId?: string;
}

/** Represents a tab group */
export interface TabGroup {
  id: string;
  name: string;
  tabIds: string[];
  collapsed: boolean;
  color?: string;
}

/** Represents a bookmark */
export interface Bookmark {
  id: string;
  url: string;
  title: string;
  favicon: string;
  parentId: string | null;
  dateAdded: number;
  dateModified?: number;
  tags?: string[];
}

/** Represents a bookmark folder */
export interface BookmarkFolder {
  id: string;
  name: string;
  parentId: string | null;
  children: (Bookmark | BookmarkFolder)[];
  dateAdded: number;
  dateModified: number;
}

/** Represents browser settings */
export interface Settings {
  theme: 'light' | 'dark' | 'system';
  homepage: string;
  searchEngine: string;
  enableTrackingProtection: boolean;
  showBookmarksBar: boolean;
  defaultZoom: number;
  downloadLocation: string;
  languages: string[];
  // Add more settings as needed
}

/** Represents a navigation history item */
export interface HistoryItem {
  id: string;
  url: string;
  title: string;
  favicon: string;
  visitCount: number;
  lastVisitTime: number;
  typedCount?: number;
  transitionType?: string;
}

/** Represents a download item */
export interface DownloadItem {
  id: string;
  url: string;
  filename: string;
  path: string;
  totalBytes: number;
  receivedBytes: number;
  state: 'in_progress' | 'complete' | 'interrupted' | 'cancelled';
  startTime: number;
  endTime?: number;
  mimeType: string;
  referrer?: string;
}

/** Event types for the event bus */
export type EventType = 
  | 'tabCreated'
  | 'tabRemoved'
  | 'tabActivated'
  | 'tabUpdated'
  | 'navigationStarted'
  | 'navigationCompleted'
  | 'bookmarkAdded'
  | 'bookmarkRemoved'
  | 'bookmarkUpdated'
  | 'downloadStarted'
  | 'downloadProgress'
  | 'downloadCompleted';

/** Event bus callback type */
export type EventCallback<T = any> = (data: T) => void;

/** Event bus subscription */
export interface EventSubscription {
  unsubscribe: () => void;
}

/** Event bus interface */
export interface EventBus {
  subscribe<T = any>(event: EventType, callback: EventCallback<T>): EventSubscription;
  publish(event: EventType, data?: any): void;
  unsubscribeAll(event?: EventType): void;
}

/** Theme type */
export type Theme = 'light' | 'dark' | 'system';

/** Search engine configuration */
export interface SearchEngine {
  name: string;
  baseUrl: string;
  queryParam: string;
  favicon: string;
}
