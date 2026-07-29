// Covers ../store/stylesPager.ts — the port of
// ../../../../ThemeFlutter/lib/data/styles_pager.dart.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import type { ThemeStylesPage } from '../models/themeStylesPage';
import type { ThemeStylesPageQuery } from '../api/client';
import { StylesPager } from '../store/stylesPager';

/** Builds `count` styles whose ids are prefixed, so pages are distinguishable. */
function page(prefix: string, count: number, total: number, offset = 0): ThemeStylesPage {
  return {
    items: Array.from({ length: count }, (_, i) => ({
      id: `${prefix}-${String(offset + i)}`,
      displayName: `${prefix} ${String(offset + i)}`,
      celebrationImageUrl: '',
      category: 'Fighting',
    })),
    total,
    offset,
    limit: count,
  };
}

/** A fetch whose every response is resolved by hand, so ordering is controlled. */
function deferredFetch() {
  const calls: { query: ThemeStylesPageQuery; resolve: (page: ThemeStylesPage) => void }[] = [];
  const fetchPage = (query: ThemeStylesPageQuery): Promise<ThemeStylesPage> =>
    new Promise<ThemeStylesPage>((resolve) => {
      calls.push({ query, resolve });
    });
  return { calls, fetchPage };
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe('paging', () => {
  it('accumulates pages and reports hasMore off the post-filter total', async () => {
    const fetchPage = vi
      .fn<(query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>>()
      .mockResolvedValueOnce(page('a', 2, 3, 0))
      .mockResolvedValueOnce(page('b', 1, 3, 2));
    const pager = new StylesPager({ pageSize: 2, fetchPage });

    expect(pager.getSnapshot().hasLoadedFirstPage).toBe(false);
    pager.start();
    await vi.advanceTimersByTimeAsync(0);

    expect(pager.getSnapshot().items).toHaveLength(2);
    expect(pager.getSnapshot().total).toBe(3);
    expect(pager.getSnapshot().hasMore).toBe(true);
    expect(pager.getSnapshot().hasLoadedFirstPage).toBe(true);

    await pager.loadMore();
    expect(pager.getSnapshot().items).toHaveLength(3);
    expect(pager.getSnapshot().hasMore).toBe(false);
    // The second request asked from the accumulated offset, not from 0.
    expect(fetchPage).toHaveBeenNthCalledWith(2, { offset: 2, limit: 2, query: null });

    // Exhausted: no further request.
    await pager.loadMore();
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });

  it('flips errored on a failure and keeps the items already loaded', async () => {
    const fetchPage = vi
      .fn<(query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>>()
      .mockResolvedValueOnce(page('a', 2, 9, 0))
      .mockRejectedValueOnce(new Error('flaky'));
    const pager = new StylesPager({ pageSize: 2, fetchPage });

    pager.start();
    await vi.advanceTimersByTimeAsync(0);
    await pager.loadMore();

    expect(pager.getSnapshot().errored).toBe(true);
    expect(pager.getSnapshot().items).toHaveLength(2);
    expect(pager.getSnapshot().isLoading).toBe(false);
  });

  it('start() is idempotent, so a StrictMode remount does not double-fetch', async () => {
    const fetchPage = vi
      .fn<(query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>>()
      .mockResolvedValue(page('a', 1, 1, 0));
    const pager = new StylesPager({ fetchPage });

    pager.start();
    pager.start();
    await vi.advanceTimersByTimeAsync(0);
    expect(fetchPage).toHaveBeenCalledTimes(1);
  });
});

describe('the 250ms search debounce', () => {
  it('collapses a burst of keystrokes into one request', async () => {
    const fetchPage = vi
      .fn<(query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>>()
      .mockResolvedValue(page('a', 1, 1, 0));
    const pager = new StylesPager({ fetchPage });
    pager.start();
    await vi.advanceTimersByTimeAsync(0);
    fetchPage.mockClear();

    pager.setQuery('z');
    pager.setQuery('ze');
    pager.setQuery('zen');
    await vi.advanceTimersByTimeAsync(249);
    expect(fetchPage).not.toHaveBeenCalled();

    await vi.advanceTimersByTimeAsync(1);
    expect(fetchPage).toHaveBeenCalledTimes(1);
    expect(fetchPage).toHaveBeenCalledWith({ offset: 0, limit: 20, query: 'zen' });
  });

  it('clears the accumulated items immediately, before the debounce fires', () => {
    const { fetchPage } = deferredFetch();
    const pager = new StylesPager({ fetchPage });
    pager.setQuery('zen');
    expect(pager.getSnapshot().items).toEqual([]);
    expect(pager.getSnapshot().total).toBe(0);
    expect(pager.getSnapshot().hasLoadedFirstPage).toBe(false);
    expect(pager.getSnapshot().query).toBe('zen');
  });

  it('trims, and ignores a no-op query change', async () => {
    const fetchPage = vi
      .fn<(query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>>()
      .mockResolvedValue(page('a', 1, 1, 0));
    const pager = new StylesPager({ fetchPage });
    pager.setQuery('  zen  ');
    await vi.advanceTimersByTimeAsync(250);
    expect(fetchPage).toHaveBeenCalledWith({ offset: 0, limit: 20, query: 'zen' });

    fetchPage.mockClear();
    pager.setQuery('zen');
    await vi.advanceTimersByTimeAsync(250);
    expect(fetchPage).not.toHaveBeenCalled();
  });
});

describe('the generation guard', () => {
  it('drops a stale in-flight response so it cannot overwrite fresh results', async () => {
    const { calls, fetchPage } = deferredFetch();
    const pager = new StylesPager({ fetchPage });

    pager.start();
    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toHaveLength(1);

    // The query moves on while the first request is still in flight.
    pager.setQuery('zen');
    await vi.advanceTimersByTimeAsync(250);
    expect(calls).toHaveLength(2);

    // The SUPERSEDED response lands first — the out-of-order case this exists
    // for. It must be discarded entirely.
    calls[0]?.resolve(page('stale', 3, 99, 0));
    await vi.advanceTimersByTimeAsync(0);
    expect(pager.getSnapshot().items).toEqual([]);
    expect(pager.getSnapshot().total).toBe(0);

    calls[1]?.resolve(page('fresh', 2, 2, 0));
    await vi.advanceTimersByTimeAsync(0);
    expect(pager.getSnapshot().items.map((s) => s.id)).toEqual(['fresh-0', 'fresh-1']);
    expect(pager.getSnapshot().total).toBe(2);
  });

  it('drops a stale FAILURE too, so an old error cannot flag the new query', async () => {
    const calls: { reject: (error: Error) => void }[] = [];
    const fetchPage = (): Promise<ThemeStylesPage> =>
      new Promise<ThemeStylesPage>((_resolve, reject) => {
        calls.push({ reject });
      });
    const pager = new StylesPager({ fetchPage });

    pager.start();
    await vi.advanceTimersByTimeAsync(0);
    pager.setQuery('zen');
    await vi.advanceTimersByTimeAsync(250);

    calls[0]?.reject(new Error('stale failure'));
    await vi.advanceTimersByTimeAsync(0);
    expect(pager.getSnapshot().errored).toBe(false);
  });

  it('does not wedge in "loading" when a query change supersedes a live request', async () => {
    // The bug this guards (present in ThemeFlutter's styles_pager.dart): the
    // superseded response's `finally` skips clearing the loading flag because
    // the generation moved, while the debounced reload had already bailed on
    // `if (isLoading) return` — leaving the pager stuck forever.
    const { calls, fetchPage } = deferredFetch();
    const pager = new StylesPager({ fetchPage });

    pager.start();
    await vi.advanceTimersByTimeAsync(0);
    pager.setQuery('zen');
    expect(pager.getSnapshot().isLoading).toBe(false);

    await vi.advanceTimersByTimeAsync(250);
    expect(calls).toHaveLength(2);

    calls[0]?.resolve(page('stale', 1, 1, 0));
    calls[1]?.resolve(page('fresh', 1, 1, 0));
    await vi.advanceTimersByTimeAsync(0);

    expect(pager.getSnapshot().isLoading).toBe(false);
    expect(pager.getSnapshot().items.map((s) => s.id)).toEqual(['fresh-0']);
  });
});

describe('the pager snapshot contract', () => {
  it('returns the same reference until something changes', async () => {
    const fetchPage = vi
      .fn<(query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>>()
      .mockResolvedValue(page('a', 1, 1, 0));
    const pager = new StylesPager({ fetchPage });
    const before = pager.getSnapshot();
    expect(pager.getSnapshot()).toBe(before);
    expect(Object.isFrozen(before)).toBe(true);

    pager.start();
    await vi.advanceTimersByTimeAsync(0);
    expect(pager.getSnapshot()).not.toBe(before);
    expect(pager.getSnapshot()).toBe(pager.getSnapshot());
  });
});