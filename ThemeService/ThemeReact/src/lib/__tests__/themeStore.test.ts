// Covers ../store/themeStore.ts — the port of
// ../../../../ThemeFlutter/lib/customization_service.dart.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { ThemeApiClient } from '../api/client';
import { LAST_GOOD_KEY, SELECTED_DESIGN_KEY } from '../store/persistence';
import { clearThemeStore, getThemeSnapshot, registerThemeStore } from '../store/locator';
import { ThemeStore } from '../store/themeStore';
import { rgba } from '../theme/color';
import { themeColor, themeDesignName, themeText } from '../theme/resolvers';

import { APEX_MMA_PAYLOAD } from './fixtures/apexmma';

const BASE_URL = 'http://theme.test';
const FALLBACK = rgba(1, 2, 3);

/** A second design, so an adopted switch is distinguishable from the seed. */
const ZEN_PAYLOAD = { ...APEX_MMA_PAYLOAD, design_name: 'Zen BJJ' };

function jsonResponse(body: unknown): Response {
  return { ok: true, status: 200, json: () => Promise.resolve(body) } as unknown as Response;
}

function newStore(designId = 'ApexMMA'): ThemeStore {
  return new ThemeStore(new ThemeApiClient('combatden', designId, BASE_URL), {
    expectedColors: ['primary'],
    expectedImages: ['logo_primary'],
  });
}

let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(() => {
  window.localStorage.clear();
  clearThemeStore();
  vi.spyOn(console, 'warn').mockImplementation(() => undefined);
  fetchMock = vi.fn();
  vi.stubGlobal('fetch', fetchMock);
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  clearThemeStore();
});

describe('the fallback ladder', () => {
  it('adopts the network payload and persists it as last-good', async () => {
    fetchMock.mockResolvedValue(jsonResponse(APEX_MMA_PAYLOAD));
    const store = newStore();
    await store.initialize();

    expect(store.current?.designName).toBe('Apex MMA');
    expect(store.activeDesignId).toBe('ApexMMA');
    expect(fetchMock).toHaveBeenCalledWith(
      `${BASE_URL}/apps/combatden/ApexMMA`,
      expect.objectContaining({ method: 'GET' }),
    );
    expect(JSON.parse(window.localStorage.getItem(LAST_GOOD_KEY) ?? 'null')).toEqual(APEX_MMA_PAYLOAD);
    // The seed design is NOT a user pick, so it must not become sticky.
    expect(window.localStorage.getItem(SELECTED_DESIGN_KEY)).toBeNull();
  });

  it('paints from the localStorage last-good before the network answers', async () => {
    window.localStorage.setItem(LAST_GOOD_KEY, JSON.stringify(APEX_MMA_PAYLOAD));
    const pending: ((response: Response) => void)[] = [];
    fetchMock.mockImplementation(
      () =>
        new Promise<Response>((resolve) => {
          pending.push(resolve);
        }),
    );

    const store = newStore();
    const booting = store.initialize();
    // The disk copy is adopted synchronously, before the fetch settles.
    expect(store.current?.designName).toBe('Apex MMA');

    pending[0]?.(jsonResponse(ZEN_PAYLOAD));
    await booting;
    expect(store.current?.designName).toBe('Zen BJJ');
  });

  it('keeps the disk last-good when the network fails, and never throws', async () => {
    window.localStorage.setItem(LAST_GOOD_KEY, JSON.stringify(APEX_MMA_PAYLOAD));
    fetchMock.mockRejectedValue(new TypeError('Failed to fetch'));

    const store = newStore();
    await expect(store.initialize()).resolves.toBeUndefined();
    expect(store.current?.designName).toBe('Apex MMA');
    expect(store.getSnapshot().isReady).toBe(true);
  });

  it('keeps the disk last-good when the network answers with an HTTP error', async () => {
    window.localStorage.setItem(LAST_GOOD_KEY, JSON.stringify(APEX_MMA_PAYLOAD));
    fetchMock.mockResolvedValue({ ok: false, status: 404 } as unknown as Response);

    const store = newStore();
    await store.initialize();
    expect(store.current?.designName).toBe('Apex MMA');
  });

  it('leaves every resolver on its fallback when nothing loads at all', async () => {
    fetchMock.mockRejectedValue(new TypeError('offline'));
    const store = newStore();
    registerThemeStore(store);
    await store.initialize();

    expect(store.current).toBeNull();
    expect(store.getSnapshot().isLoaded).toBe(false);
    expect(store.getSnapshot().isReady).toBe(true);
    expect(themeColor('primary', FALLBACK)).toBe(FALLBACK);
    expect(themeText('reserve_cta', 'Reserve')).toBe('Reserve');
    expect(themeDesignName('—')).toBe('—');
  });

  it('ignores a corrupt disk copy rather than failing the boot', async () => {
    window.localStorage.setItem(LAST_GOOD_KEY, '{not json');
    fetchMock.mockResolvedValue(jsonResponse(APEX_MMA_PAYLOAD));

    const store = newStore();
    await store.initialize();
    expect(store.current?.designName).toBe('Apex MMA');
  });

  it('prefers a sticky selection from a previous visit over the seed design', async () => {
    window.localStorage.setItem(SELECTED_DESIGN_KEY, 'ZenBJJ');
    fetchMock.mockResolvedValue(jsonResponse(ZEN_PAYLOAD));

    const store = newStore('ApexMMA');
    await store.initialize();
    expect(fetchMock).toHaveBeenCalledWith(
      `${BASE_URL}/apps/combatden/ZenBJJ`,
      expect.anything(),
    );
    expect(store.activeDesignId).toBe('ZenBJJ');
  });

  it('gives up on a hung request after the 5s cap', async () => {
    vi.useFakeTimers();
    try {
      window.localStorage.setItem(LAST_GOOD_KEY, JSON.stringify(APEX_MMA_PAYLOAD));
      fetchMock.mockImplementation(
        (_url: string, init: RequestInit) =>
          new Promise<Response>((_resolve, reject) => {
            init.signal?.addEventListener('abort', () => {
              reject(new DOMException('The operation was aborted.', 'AbortError'));
            });
          }),
      );

      const store = newStore();
      const booting = store.initialize();
      await vi.advanceTimersByTimeAsync(5000);
      await booting;

      expect(store.current?.designName).toBe('Apex MMA');
      expect(store.getSnapshot().isReady).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe('selectDesign', () => {
  it('adopts, persists BOTH keys, and notifies', async () => {
    fetchMock.mockResolvedValue(jsonResponse(APEX_MMA_PAYLOAD));
    const store = newStore();
    await store.initialize();

    const listener = vi.fn();
    store.subscribe(listener);
    fetchMock.mockResolvedValue(jsonResponse(ZEN_PAYLOAD));

    await expect(store.selectDesign('ZenBJJ')).resolves.toBe(true);
    expect(store.current?.designName).toBe('Zen BJJ');
    expect(store.activeDesignId).toBe('ZenBJJ');
    expect(window.localStorage.getItem(SELECTED_DESIGN_KEY)).toBe('ZenBJJ');
    expect(JSON.parse(window.localStorage.getItem(LAST_GOOD_KEY) ?? 'null')).toEqual(ZEN_PAYLOAD);
    expect(listener).toHaveBeenCalled();
  });

  it('returns false and leaves the current theme completely intact on failure', async () => {
    fetchMock.mockResolvedValue(jsonResponse(APEX_MMA_PAYLOAD));
    const store = newStore();
    await store.initialize();
    const before = store.getSnapshot();

    const listener = vi.fn();
    store.subscribe(listener);
    fetchMock.mockRejectedValue(new TypeError('offline'));

    await expect(store.selectDesign('ZenBJJ')).resolves.toBe(false);
    expect(store.getSnapshot()).toBe(before);
    expect(store.current?.designName).toBe('Apex MMA');
    expect(store.activeDesignId).toBe('ApexMMA');
    expect(window.localStorage.getItem(SELECTED_DESIGN_KEY)).toBeNull();
    expect(listener).not.toHaveBeenCalled();
  });

  it('never throws, whatever the failure', async () => {
    fetchMock.mockImplementation(() => {
      throw new Error('boom');
    });
    const store = newStore();
    await expect(store.selectDesign('ZenBJJ')).resolves.toBe(false);
  });
});

describe('the useSyncExternalStore snapshot contract', () => {
  // A getSnapshot() that returns a fresh object literal per call makes React
  // throw "The result of getSnapshot should be cached" and then re-render
  // forever. This is the test that stops that regression.
  it('returns the SAME reference on repeated calls', () => {
    const store = newStore();
    expect(store.getSnapshot()).toBe(store.getSnapshot());
  });

  it('returns a NEW reference only when something actually changed', async () => {
    fetchMock.mockResolvedValue(jsonResponse(APEX_MMA_PAYLOAD));
    const store = newStore();
    const before = store.getSnapshot();

    await store.initialize();
    const afterInit = store.getSnapshot();
    expect(afterInit).not.toBe(before);
    expect(afterInit).toBe(store.getSnapshot());

    fetchMock.mockResolvedValue(jsonResponse(ZEN_PAYLOAD));
    await store.selectDesign('ZenBJJ');
    const afterSwitch = store.getSnapshot();
    expect(afterSwitch).not.toBe(afterInit);
    expect(afterSwitch).toBe(store.getSnapshot());
  });

  it('is frozen, so a consumer cannot mutate it into a stale-looking state', () => {
    expect(Object.isFrozen(newStore().getSnapshot())).toBe(true);
  });

  it('hands out a stable pre-bootstrap snapshot too', () => {
    // Components mount BEFORE any store is registered — that path has to obey
    // the same caching contract or the very first render loops.
    expect(getThemeSnapshot()).toBe(getThemeSnapshot());
    expect(getThemeSnapshot().isReady).toBe(false);
  });
});