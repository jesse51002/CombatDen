// Ports ../../../../../../CRM/lib/showcase/rewards/store_grid.dart — a clone of
// MobileApp's `StoreGrid`: the two-column points store.
//
// IT IS TWO COLUMNS, NOT A GRID, and that is the point of the file. Items
// zig-zag down (even indices left, odd right) so each column packs to its own
// content height — a CSS `grid` with row tracks would instead stretch every row
// to its tallest card and leave gaps under the short ones, which is exactly the
// layout the Dart's two `Expanded(Column)`s avoid.

import type { ShowcasePointsStoreItem } from './mockPointsStore';
import { RewardCard } from './RewardCard';
import styles from './StoreGrid.module.css';

/** `i.isEven ? left : right` — the zig-zag split, pinned by a test. */
export function splitStoreColumns(
  items: readonly ShowcasePointsStoreItem[],
): readonly [readonly ShowcasePointsStoreItem[], readonly ShowcasePointsStoreItem[]] {
  const left: ShowcasePointsStoreItem[] = [];
  const right: ShowcasePointsStoreItem[] = [];
  items.forEach((item, index) => {
    (index % 2 === 0 ? left : right).push(item);
  });
  return [left, right];
}

export interface StoreGridProps {
  items: readonly ShowcasePointsStoreItem[];
}

export function StoreGrid({ items }: StoreGridProps) {
  const [left, right] = splitStoreColumns(items);
  return (
    // `Padding(horizontal: screenHorizontalPadding) >
    // Row(crossAxisAlignment: start, spacing: spacingLarge)`.
    <div className={styles.grid}>
      <StoreColumn items={left} />
      <StoreColumn items={right} />
    </div>
  );
}

/** `_StoreColumn` — `Column(min, stretch, spacing: spacingLarge)`. */
function StoreColumn({ items }: { items: readonly ShowcasePointsStoreItem[] }) {
  return (
    <div className={styles.column}>
      {items.map((item, index) => (
        // The store list is a fixed const set (or the gym's own, which is also
        // positional), so the slot index IS the card's identity — two items may
        // legitimately share a title.
        <RewardCard key={`${String(index)}-${item.title}`} item={item} buttonText="Redeem" />
      ))}
    </div>
  );
}
