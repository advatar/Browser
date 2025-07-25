/**
 * Utility functions for the browser
 */

/**
 * Generate a unique ID
 * @returns A unique ID string
 */
export function generateId(): string {
  return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
}

/**
 * Save data to localStorage
 * @param key - Storage key
 * @param data - Data to save (will be JSON stringified)
 * @returns True if successful, false otherwise
 */
export function saveToStorage<T>(key: string, data: T): boolean {
  try {
    localStorage.setItem(key, JSON.stringify(data));
    return true;
  } catch (error) {
    console.error('Error saving to storage:', error);
    return false;
  }
}

/**
 * Load data from localStorage
 * @param key - Storage key
 * @param defaultValue - Default value if key doesn't exist
 * @returns Parsed data or default value
 */
export function loadFromStorage<T>(key: string, defaultValue: T): T {
  try {
    const data = localStorage.getItem(key);
    return data ? JSON.parse(data) : defaultValue;
  } catch (error) {
    console.error('Error loading from storage:', error);
    return defaultValue;
  }
}

/**
 * Debounce a function
 * @param func - Function to debounce
 * @param wait - Wait time in milliseconds
 * @returns Debounced function
 */
export function debounce<T extends (...args: any[]) => any>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout> | null = null;
  
  return function executedFunction(...args: Parameters<T>): void {
    const later = () => {
      timeout = null;
      func(...args);
    };
    
    if (timeout !== null) {
      clearTimeout(timeout);
    }
    
    timeout = setTimeout(later, wait);
  };
}

/**
 * Check if a string is a valid URL
 * @param string - String to check
 * @returns True if the string is a valid URL
 */
export function isValidUrl(string: string): boolean {
  try {
    new URL(string);
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * Normalize a URL string
 * @param url - URL to normalize
 * @returns Normalized URL
 */
export function normalizeUrl(url: string): string {
  try {
    const urlObj = new URL(url);
    return urlObj.toString();
  } catch (error) {
    return url;
  }
}

/**
 * Get favicon URL for a given URL
 * @param url - Website URL
 * @returns Favicon URL
 */
export function getFaviconUrl(url: string): string {
  try {
    const urlObj = new URL(url);
    return `https://www.google.com/s2/favicon?domain=${urlObj.hostname}&sz=32`;
  } catch (error) {
    return '';
  }
}

// Type exports
export type { } from './types';

// Constants
export const STORAGE_KEYS = {
  BOOKMARKS: 'bookmarks',
  HISTORY: 'history',
  SETTINGS: 'settings',} as const;

export const DEFAULT_SETTINGS = {
  theme: 'system',
  homepage: 'about:blank',
  searchEngine: 'https://duckduckgo.com/?q=',
  enableTrackingProtection: true,
  showBookmarksBar: true,
} as const;
