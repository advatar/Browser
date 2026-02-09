import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import {
  debounce,
  generateId,
  getFaviconUrl,
  isValidUrl,
  loadFromStorage,
  normalizeUrl,
  saveToStorage,
} from './utils.js';

describe('utils', () => {
  beforeEach(() => {
    // Be resilient to environment differences (jsdom vs node polyfills).
    if (!globalThis.localStorage || typeof globalThis.localStorage.clear !== 'function') {
      let backing = new Map();
      globalThis.localStorage = {
        getItem: (k) => (backing.has(k) ? backing.get(k) : null),
        setItem: (k, v) => backing.set(k, String(v)),
        removeItem: (k) => backing.delete(k),
        clear: () => {
          backing = new Map();
        },
      };
    }
    globalThis.localStorage.clear();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('generateId is stable given fixed time/random', () => {
    vi.spyOn(Date, 'now').mockReturnValue(1234567890);
    vi.spyOn(Math, 'random').mockReturnValue(0.424242);
    expect(generateId()).toMatch(/^1234567890-[a-z0-9]{9}$/);
  });

  it('saveToStorage/loadFromStorage round-trips JSON', () => {
    const ok = saveToStorage('k', { a: 1, b: 'x' });
    expect(ok).toBe(true);
    expect(loadFromStorage('k')).toEqual({ a: 1, b: 'x' });
    expect(loadFromStorage('missing', { z: 9 })).toEqual({ z: 9 });
  });

  it('isValidUrl only accepts http(s)', () => {
    expect(isValidUrl('https://example.com')).toBe(true);
    expect(isValidUrl('http://example.com')).toBe(true);
    expect(isValidUrl('ftp://example.com')).toBe(false);
    expect(isValidUrl('not a url')).toBe(false);
  });

  it('normalizeUrl adds https:// when missing', () => {
    expect(normalizeUrl('example.com')).toBe('https://example.com');
    expect(normalizeUrl('http://example.com')).toBe('http://example.com');
    expect(normalizeUrl('https://example.com')).toBe('https://example.com');
  });

  it('getFaviconUrl derives /favicon.ico and returns empty on invalid input', () => {
    expect(getFaviconUrl('https://example.com/path')).toBe(
      'https://example.com/favicon.ico',
    );
    expect(getFaviconUrl('not a url')).toBe('');
  });

  it('debounce only calls after the wait window', () => {
    vi.useFakeTimers();
    const fn = vi.fn();
    const d = debounce(fn, 50);

    d(1);
    d(2);
    expect(fn).not.toHaveBeenCalled();

    vi.advanceTimersByTime(49);
    expect(fn).not.toHaveBeenCalled();

    vi.advanceTimersByTime(1);
    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn).toHaveBeenCalledWith(2);
  });
});
