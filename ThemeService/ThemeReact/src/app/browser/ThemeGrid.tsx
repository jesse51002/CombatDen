// Ports ../../../../../CRM/lib/features/members/presentation/widgets/
// member_app/theme_tab/theme_grid.dart.
//
// Side-pane theme picker shown next to the phone-frame preview.
//
// Eager-loads every page so search never misses an item, then anchors the list
// **once** on first load so the entered theme sits centred — BY INDEX, not by
// offset, so lazy loading and viewport height never throw it off. Later card
// picks leave the list exactly as it is.
//
// DEVIATION: Dart reaches for `ScrollablePositionedList` + `ItemScrollController
// .jumpTo(index:, alignment: 0.5)` because a plain `ListView` can only scroll to
// a pixel offset it cannot know for an unbuilt row. The DOM has no such problem
// — `scrollIntoView({block: 'center'})` on the row's own node is by definition
// index-addressed — so the one-shot lands on a ref callback, which also IS the
// "retry until its page streams in" loop Dart writes by hand.

import { useCallback, useEffect, useRef } from 'react';
import { useActiveDesign, useStylesPager } from 'theme-react';

import { AppOutlineButton } from '../widgets/AppOutlineButton';
import { AppSpinner } from '../widgets/AppSpinner';
import { SectionCard } from '../widgets/SectionCard';

import { selectedStyle } from './selectedStyle';
import { ThemeCard } from './ThemeCard';
import styles from './ThemeGrid.module.css';
import { ThemeSearchBar } from './ThemeSearchBar';

// Web admin: bigger viewport than the phone picker, so 50 per page keeps the
// side scroll snug and eager-loads the whole catalog quickly, so the active
// theme's row is resolvable for the first-load centring.
const WEB_PAGE_SIZE = 50;

export interface ThemeGridProps {
  onBackToLibrary: () => void;
}

export function ThemeGrid({ onBackToLibrary }: ThemeGridProps) {
  const { items, query, isLoading, errored, hasMore, hasLoadedFirstPage, loadMore, setQuery } =
    useStylesPager({ pageSize: WEB_PAGE_SIZE });
  const { id: activeDesignId } = useActiveDesign();

  // Seed/heal the global selection from the loaded catalog — the active
  // theme's category isn't known until its card streams in.
  useEffect(() => {
    selectedStyle.reconcileFromCatalog(items);
  }, [items]);

  // The active theme may live on a later page; keep pulling so search has the
  // full set and the centring has a row to land on.
  useEffect(() => {
    if (!isLoading && hasMore) loadMore();
  }, [isLoading, hasMore, loadMore]);

  // One-shot: centre the active row the first frame it exists. Once it fires it
  // never runs again, so selecting a card never moves the list.
  const didCenter = useRef(false);
  // The scroll waits a frame — `addPostFrameCallback`, for the same reason Dart
  // needs it: refs attach before the surrounding layout has settled.
  const centerRef = useCallback((node: HTMLDivElement | null) => {
    if (node === null || didCenter.current) return;
    didCenter.current = true;
    requestAnimationFrame(() => node.scrollIntoView({ block: 'center' }));
  }, []);

  return (
    <div className={styles.pane}>
      <h2 className={styles.heading}>App Theme</h2>
      <ThemeSearchBar onChanged={setQuery} />
      <AppOutlineButton text="← Back to library" fullWidth onPressed={onBackToLibrary} />
      <div className={styles.list}>
        {!hasLoadedFirstPage && isLoading ? (
          <CatalogMessage />
        ) : items.length === 0 ? (
          errored ? (
            <CatalogMessage message="Could not reach the theme service. Start it and reopen this tab to load the themes." />
          ) : (
            <CatalogMessage
              message={query === '' ? 'No themes generated yet.' : `No themes match "${query}".`}
            />
          )
        ) : (
          <div className={styles.rows}>
            {items.map((style) => (
              <div
                key={style.id}
                ref={style.id === activeDesignId ? centerRef : undefined}
                className={styles.row}
              >
                <ThemeCard style={style} isActive={style.id === activeDesignId} />
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

/** The pane's loading / empty / error surface. `message` absent = loading. */
function CatalogMessage({ message }: { message?: string }) {
  return (
    <SectionCard>
      <div className={styles.message}>
        {message === undefined ? <AppSpinner /> : <p className={styles.messageText}>{message}</p>}
      </div>
    </SectionCard>
  );
}
