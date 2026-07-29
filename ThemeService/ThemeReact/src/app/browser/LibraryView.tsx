// Ports ../../../../../CRM/lib/features/members/presentation/widgets/
// themes_library/library_view.dart.
//
// Themes library — a collapsing title over a persistent search + filter-pill
// bar, a hairline, then a responsive grid of theme cards whose column count
// scales with width. Scrolling collapses the title away and tightens the
// chrome; the search + filters stay put. Picking a card records the style and
// hands control back to the host, which switches to the phone view.
//
// TWO DEVIATIONS from the Dart, both about WHAT SCROLLS:
//
//  1. The PAGE scrolls, not an inner box. Dart puts the grid in its own
//     `SingleChildScrollView` under a fixed chrome column; the web equivalent
//     of "fixed chrome, scrolling body" is a sticky chrome over a document
//     that scrolls, which is also what keeps the ported landing nav's
//     scroll-frost behaviour (../chrome/GWNav.tsx) working unchanged. The
//     collapse threshold therefore reads `window.scrollY`, which is exactly
//     Dart's `ScrollNotification.metrics.pixels` for this layout.
//  2. The hairline sits INSIDE the sticky chrome. It has to: the chrome now
//     has cards passing underneath it, so it needs an opaque ground and a
//     bottom edge to read against.

import { useEffect, useRef, useState } from 'react';
import { useActiveDesign, useStylesPager } from 'theme-react';
import type { ThemeStyle } from 'theme-react';

import { FillGrid } from '../widgets/FillGrid';
import { FilterPills } from '../widgets/FilterPills';
import { Hairline } from '../widgets/Hairline';
import { SearchOffIcon } from '../widgets/icons';
import { cx } from '../widgets/cx';

import { LibraryCard } from './LibraryCard';
import styles from './LibraryView.module.css';
import { selectedStyle, useSelectedStyle } from './selectedStyle';
import { ThemeSearchBar } from './ThemeSearchBar';

const ALL_CHIP = 'All';
const PAGE_SIZE = 50;
// Responsive grid: the column count is whatever fits at this min card width, so
// a wide desktop shows more columns (≈4) than a narrow one. Never below 2.
const GRID_MIN_ITEM_WIDTH = 280;
const GRID_MIN_COLUMNS = 2;

// Hysteresis: collapsing grows the viewport (the title's space is freed), which
// can nudge the scroll offset back across a single threshold and flicker.
// Separate collapse/expand thresholds keep it stable.
const COLLAPSE_AT = 24;
const EXPAND_AT = 8;

export interface LibraryViewProps {
  onPicked: () => void;
}

export function LibraryView({ onPicked }: LibraryViewProps) {
  const { items, isLoading, errored, hasMore, loadMore, setQuery } = useStylesPager({
    pageSize: PAGE_SIZE,
  });
  const { designId } = useSelectedStyle();
  const { id: activeDesignId } = useActiveDesign();
  const [selected, setSelected] = useState(ALL_CHIP);
  const [collapsed, setCollapsed] = useState(false);

  // `_pullUntilDone` — eager-load every page so search and the category chips
  // see the whole catalog rather than whatever the first page happened to hold.
  useEffect(() => {
    if (!isLoading && hasMore) loadMore();
  }, [isLoading, hasMore, loadMore]);

  useEffect(() => {
    const onScroll = () => {
      const pixels = window.scrollY;
      setCollapsed((current) => {
        if (!current && pixels > COLLAPSE_AT) return true;
        if (current && pixels < EXPAND_AT) return false;
        return current;
      });
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  // `_anchorOnSelectedOnce` — returning to the library after picking a theme
  // centres its card once, the same "build around the selection" the phone-mode
  // side pane does. A ref callback IS the retry loop Dart writes by hand: it
  // fires the frame the card first mounts, however late its page streams in.
  // Only the already-selected card gets the callback, so a fresh visit with
  // nothing picked stays at the top.
  //
  // The scroll itself waits a frame, which is `addPostFrameCallback` in Dart
  // and load-bearing here for the same reason: a ref callback fires bottom-up,
  // so the card is attached BEFORE the grid above it has measured itself and
  // settled on its column count (see ../widgets/FillGrid.tsx). Centring against
  // the pre-measurement 2-column layout leaves the card ~1600px off once the
  // grid reflows to four.
  const didAnchor = useRef(false);
  const anchorRef = (node: HTMLButtonElement | null) => {
    if (node === null || didAnchor.current) return;
    didAnchor.current = true;
    requestAnimationFrame(() => node.scrollIntoView({ block: 'center' }));
  };

  const chips = chipsFor(items);
  const selectedIndex = Math.min(Math.max(chips.indexOf(selected), 0), chips.length - 1);
  const visible = selected === ALL_CHIP ? items : items.filter((s) => s.category === selected);

  const pick = (style: ThemeStyle) => {
    // Records the previewed design + its category globally and brands with it
    // (theme-only — decoupled from any content gym).
    selectedStyle.selectStyle(style);
    onPicked();
  };

  return (
    <div className={cx(styles.view, collapsed && styles.collapsed)}>
      {/* Chrome cluster: a collapsing title above the persistent search +
          filters. Closer-related siblings get tighter gaps. */}
      <div className={styles.chrome}>
        <div className={styles.titleWrap}>
          <div className={styles.titleClip}>
            <h1 className={styles.title}>Theme library</h1>
          </div>
        </div>
        <div className={styles.controls}>
          <div className={styles.search}>
            <ThemeSearchBar onChanged={setQuery} />
          </div>
          <FilterPills
            labels={chips}
            selectedIndex={selectedIndex}
            onSelected={(i) => setSelected(chips[i] ?? ALL_CHIP)}
          />
        </div>
        {/* Largest break on the page: chrome above, grid below. */}
        <Hairline />
      </div>

      {visible.length === 0 ? (
        <EmptyState
          text={
            isLoading
              ? 'Loading themes…'
              : errored
                ? 'Could not reach the theme service.'
                : 'No themes match this filter.'
          }
        />
      ) : (
        <FillGrid
          minItemWidth={GRID_MIN_ITEM_WIDTH}
          minColumns={GRID_MIN_COLUMNS}
          // Keep the grid fixed on search: a single result is one normal-width
          // card in the top-left, not a card stretched full-width.
          stretchShortRows={false}
        >
          {visible.map((style) => (
            <LibraryCard
              key={style.id}
              style={style}
              isActive={style.id === activeDesignId}
              onTap={() => pick(style)}
              cardRef={style.id === designId ? anchorRef : undefined}
            />
          ))}
        </FillGrid>
      )}
    </div>
  );
}

/** The `All` chip plus every category present in the loaded items, sorted. */
function chipsFor(items: readonly ThemeStyle[]): string[] {
  const seen = new Set<string>();
  for (const style of items) {
    const category = style.category ?? '';
    if (category !== '') seen.add(category);
  }
  return [ALL_CHIP, ...[...seen].sort()];
}

function EmptyState({ text }: { text: string }) {
  return (
    <div className={styles.empty}>
      <SearchOffIcon className={styles.emptyIcon} size={32} />
      <p className={styles.emptyText}>{text}</p>
    </div>
  );
}
