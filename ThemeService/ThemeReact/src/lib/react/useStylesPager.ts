// The React binding over ../store/stylesPager.ts. The Flutter side has no
// counterpart file — a `StylesPager` there is dropped into a
// `ChangeNotifierProvider` / `ListenableBuilder` directly.

import { useEffect, useState, useSyncExternalStore } from 'react';

import type { StylesPagerOptions, StylesPagerState } from '../store/stylesPager';
import { StylesPager } from '../store/stylesPager';

export interface StylesPagerView extends StylesPagerState {
  /** Sets the search query; resets the list and refetches after the debounce. */
  setQuery: (next: string) => void;
  /** Loads the next page, if one exists and nothing is already in flight. */
  loadMore: () => void;
}

/**
 * A paged, searchable, debounced view of the styles catalog.
 *
 * `options` is read ONCE, when the pager is created — a later change (a new
 * `pageSize`) does not rebuild it, because rebuilding would throw away every
 * page already loaded and scroll the picker back to the top.
 */
export function useStylesPager(options: StylesPagerOptions = {}): StylesPagerView {
  // A lazy `useState` initialiser, not a ref written during render: constructing
  // the pager must happen exactly once per mount, and writing a ref in the
  // render phase is neither safe under concurrent rendering nor allowed by the
  // React compiler lint rules this package runs under.
  const [pager] = useState(() => new StylesPager(options));

  const state = useSyncExternalStore(pager.subscribe, pager.getSnapshot, pager.getSnapshot);

  useEffect(() => {
    pager.start();
    // Only the pending debounce is cancelled, NOT `dispose()`: React StrictMode
    // unmounts and remounts on the first mount, and a disposed pager would come
    // back with no listeners.
    return () => {
      pager.cancelPending();
    };
  }, [pager]);

  return { ...state, setQuery: pager.setQuery, loadMore: pager.loadMore };
}
