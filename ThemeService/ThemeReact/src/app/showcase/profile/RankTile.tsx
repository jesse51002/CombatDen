// Ports ../../../../../../MobileApp/lib/features/profile/presentation/layouts/
// parts/rank_tile.dart — one cell of the `statTiles` board.
//
// FIXED HEIGHT so the two tiles in a row read as a pair, and CLIPPED so a
// hero's sparkles stay inside their own cell.

import type { ReactNode } from 'react';

import styles from './RankTile.module.css';

export function RankTile({ children }: { children: ReactNode }) {
  return (
    <div className={styles.tile}>
      {/* `Center(child: child)`. */}
      <div className={styles.centre}>{children}</div>
    </div>
  );
}
