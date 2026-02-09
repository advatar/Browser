import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { HistoryManager, TRANSITION_TYPES } from './history-manager.js';

function createEventBus() {
  const handlers = new Map();
  return {
    subscribe(name, cb) {
      const list = handlers.get(name) ?? [];
      list.push(cb);
      handlers.set(name, list);
    },
    publish(name, payload) {
      for (const cb of handlers.get(name) ?? []) cb(payload);
    },
  };
}

describe('HistoryManager', () => {
  beforeEach(() => {
    vi.useFakeTimers();
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
    if (!globalThis.window) globalThis.window = globalThis;
    if (typeof globalThis.window.addEventListener !== 'function') {
      globalThis.window.addEventListener = () => {};
    }
    vi.spyOn(Date, 'now').mockReturnValue(1000);
    vi.spyOn(Math, 'random').mockReturnValue(0.1);
  });

  afterEach(() => {
    vi.clearAllTimers();
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  it('adds a new history item and emits historyItemAdded', () => {
    const bus = createEventBus();
    const events = [];
    bus.subscribe('historyItemAdded', (e) => events.push(e));

    const mgr = new HistoryManager(bus);
    const item = mgr.addHistoryItem('https://example.com', 'Example', TRANSITION_TYPES.TYPED);

    expect(item.url).toBe('https://example.com');
    expect(item.title).toBe('Example');
    expect(item.visitCount).toBe(1);
    expect(item.typedCount).toBe(1);
    expect(mgr.getHistory(10)).toHaveLength(1);
    expect(events).toHaveLength(1);
    expect(events[0].item.url).toBe('https://example.com');
  });

  it('updates an existing URL (visitCount/typedCount) instead of creating a duplicate', () => {
    const bus = createEventBus();
    const mgr = new HistoryManager(bus);

    const a = mgr.addHistoryItem('https://example.com', 'Example', TRANSITION_TYPES.TYPED);
    vi.spyOn(Date, 'now').mockReturnValue(2000);
    const b = mgr.addHistoryItem('https://example.com', 'Example 2', TRANSITION_TYPES.TYPED);

    expect(a.id).toBe(b.id);
    expect(b.visitCount).toBe(2);
    expect(b.typedCount).toBe(2);
    expect(b.lastVisitTime).toBe(2000);
    expect(b.title).toBe('Example 2');
    expect(mgr.getHistory(10)).toHaveLength(1);
  });

  it('ignores about: URLs', () => {
    const bus = createEventBus();
    const mgr = new HistoryManager(bus);

    expect(mgr.addHistoryItem('about:blank', 'Blank')).toBeUndefined();
    expect(mgr.getHistory(10)).toHaveLength(0);
  });

  it('persists and restores history via storage', () => {
    const bus = createEventBus();
    const mgr1 = new HistoryManager(bus);
    mgr1.addHistoryItem('https://a.example', 'A', TRANSITION_TYPES.LINK);
    mgr1.saveHistory();

    const mgr2 = new HistoryManager(bus);
    const items = mgr2.getHistory(10);
    expect(items).toHaveLength(1);
    expect(items[0].url).toBe('https://a.example');
    expect(items[0].title).toBe('A');
  });
});
