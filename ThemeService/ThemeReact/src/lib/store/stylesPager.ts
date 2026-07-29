// Ports ../../ThemeFlutter/lib/data/styles_pager.dart.

import type { ThemeStylesPageQuery } from '../api/client';
import type { ThemeStyle } from '../models/themeStyle';
import type { ThemeStylesPage } from '../models/themeStylesPage';

import { themeStoreOrNull } from './locator';

/** The immutable view a picker renders from. Handed out as a CACHED reference. */
export interface StylesPagerState {
  /** All styles loaded across pages for the active `query`. */
  readonly items: readonly ThemeStyle[];
  /** Post-filter total for the active `query`. `0` before the first response. */
  readonly total: number;
  /** Current search query. `''` means no filter. */
  readonly query: string;
  /** True while a fetch is in flight. */
  readonly isLoading: boolean;
  /** True when the latest fetch failed. Cleared on the next successful fetch. */
  readonly errored: boolean;
  /** True when at least one more page exists for the active query. */
  readonly hasMore: boolean;
  /**
   * True once a first page has landed for the current query — distinct from
   * "loaded zero items", which is what an empty state needs to tell apart.
   */
  readonly hasLoadedFirstPage: boolean;
}

export interface StylesPagerOptions {
  /** How many styles to request per page. */
  pageSize?: number;
  /** Debounce on a query change, so a fast typist is not one request per key. */
  searchDebounceMs?: number;
  /** Injectable for tests; defaults to the registered store's paged read. */
  fetchPage?: (query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>;
}

const DEFAULT_PAGE_SIZE = 20;
const DEFAULT_SEARCH_DEBOUNCE_MS = 250;

const EMPTY_ITEMS: readonly ThemeStyle[] = Object.freeze([]);

/**
 * Accumulates a paged + searchable view of the styles catalog.
 *
 * Owns the list state for a picker UI: the items loaded so far across pages,
 * the current search query, whether a fetch is in flight, and whether the next
 * page would yield more. Changing the query resets the accumulated items and
 * refetches from offset 0 after a short debounce.
 *
 * Failures degrade quietly (the items stay, `errored` flips true) so a flaky
 * service does not blow up the picker mid-scroll.
 */
export class StylesPager {
  private readonly pageSize: number;
  private readonly debounceMs: number;
  private readonly fetchPage: (query: ThemeStylesPageQuery) => Promise<ThemeStylesPage>;

  private readonly listeners = new Set<() => void>();

  private items: readonly ThemeStyle[] = EMPTY_ITEMS;
  private total = 0;
  private queryValue = '';
  private loading = false;
  private errored = false;
  private loadedFirstPage = false;
  private started = false;

  /**
   * Identifies the active query "generation". When the query changes, any
   * in-flight response from the previous generation is discarded — this is what
   * stops an out-of-order response from overwriting fresh results.
   */
  private generation = 0;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;

  private state: StylesPagerState;

  constructor(options: StylesPagerOptions = {}) {
    this.pageSize = options.pageSize ?? DEFAULT_PAGE_SIZE;
    this.debounceMs = options.searchDebounceMs ?? DEFAULT_SEARCH_DEBOUNCE_MS;
    this.fetchPage = options.fetchPage ?? defaultFetchPage;
    this.state = this.buildState();
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  /** The cached state. Same reference until something actually changes. */
  getSnapshot = (): StylesPagerState => this.state;

  /**
   * Requests the first page. Idempotent, and safe to call again after a React
   * StrictMode remount.
   *
   * DIVERGENCE from ThemeFlutter, where the constructor fires the first page
   * directly: constructing a pager is a render-phase act in React, and a render
   * may be discarded, so the fetch is moved behind an explicit call the
   * consuming effect makes (see `useStylesPager`).
   */
  start = (): void => {
    if (this.started) return;
    this.started = true;
    void this.loadMore();
  };

  /**
   * Updates the search query: resets the accumulated items and schedules a
   * debounced refetch from offset 0.
   */
  setQuery = (next: string): void => {
    const trimmed = next.trim();
    if (trimmed === this.queryValue) return;
    this.queryValue = trimmed;
    this.generation += 1;
    this.items = EMPTY_ITEMS;
    this.total = 0;
    this.errored = false;
    this.loadedFirstPage = false;
    // FIX vs ThemeFlutter (styles_pager.dart): Dart leaves `_isLoading` true
    // here. Its debounced reload then hits the `if (_isLoading) return` guard
    // and bails, and the superseded response's `finally` skips clearing the
    // flag because the generation moved — so the pager wedges permanently in
    // "loading" and never fetches again. Nothing is loading FOR THE NEW QUERY,
    // so the flag is released; the stale response is still dropped by the
    // generation guard below.
    this.loading = false;
    this.started = true;
    this.notify();
    this.cancelPending();
    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      void this.loadMore();
    }, this.debounceMs);
  };

  /** Fetches the next page, if one exists and no fetch is already in flight. */
  loadMore = async (): Promise<void> => {
    if (this.loading) return;
    if (this.loadedFirstPage && !this.hasMore()) return;
    const generation = this.generation;
    this.loading = true;
    this.errored = false;
    this.notify();
    try {
      const page = await this.fetchPage({
        offset: this.items.length,
        limit: this.pageSize,
        query: this.queryValue === '' ? null : this.queryValue,
      });
      if (generation !== this.generation) return;
      this.items = [...this.items, ...page.items];
      this.total = page.total;
      this.loadedFirstPage = true;
    } catch {
      if (generation !== this.generation) return;
      this.errored = true;
    } finally {
      if (generation === this.generation) {
        this.loading = false;
        this.notify();
      }
    }
  };

  /** Cancels a pending debounced refetch. Safe to call repeatedly. */
  cancelPending = (): void => {
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
  };

  /** Cancels pending work and drops every listener. Ports `dispose`. */
  dispose = (): void => {
    this.cancelPending();
    this.listeners.clear();
  };

  private hasMore = (): boolean => this.items.length < this.total;

  private buildState = (): StylesPagerState =>
    Object.freeze({
      items: this.items,
      total: this.total,
      query: this.queryValue,
      isLoading: this.loading,
      errored: this.errored,
      hasMore: this.hasMore(),
      hasLoadedFirstPage: this.loadedFirstPage,
    });

  private notify = (): void => {
    this.state = this.buildState();
    for (const listener of [...this.listeners]) listener();
  };
}

/**
 * The default read. Rejects rather than returning an empty page when nothing is
 * bootstrapped, so the picker shows its error state instead of a silent
 * "no styles found".
 */
function defaultFetchPage(query: ThemeStylesPageQuery): Promise<ThemeStylesPage> {
  const store = themeStoreOrNull();
  if (!store) {
    return Promise.reject(new Error('theme-react: no theme runtime; call initializeTheme first'));
  }
  return store.fetchStylesPage(query);
}
