// Ports ../../../../../../CRM/lib/showcase/celebrations/wins_tile_row.dart — a
// clone of MobileApp's `WinsTileRow`: three equally-sized `WinsTile`s cascading
// in left-to-right from `baseDelayMs`.
//
// THE ARITHMETIC, not the derived numbers: tile `i` starts at
// `baseDelay + badgeStagger * i * 2`. The doubling is the Dart's own — the row
// wants twice the gap between TILES that a badge strip wants between badges,
// and it says so by scaling the shared `badgeStagger` rather than inventing a
// second constant.

import { CelebrationTimings } from 'theme-react';

import type { ShowcaseWinTile } from './showcaseCelebrationStats';
import { WinsTile } from './WinsTile';
import styles from './WinsTileRow.module.css';

/** `CelebrationTimings.badgeStagger * i * 2`. */
export function winsTileDelayMs(baseDelayMs: number, index: number): number {
  return baseDelayMs + CelebrationTimings.badgeStaggerMs * index * 2;
}

export interface WinsTileRowProps {
  tiles: readonly ShowcaseWinTile[];
  /** `WinsTileRow.baseDelay` — when the first tile's reveal starts. */
  baseDelayMs?: number | undefined;
}

export function WinsTileRow({ tiles, baseDelayMs = 0 }: WinsTileRowProps) {
  return (
    <div className={styles.row}>
      {tiles.map((tile, index) => (
        // The tile list is a fixed const trio, so the slot index IS the tile's
        // identity — two tiles may legitimately carry the same label.
        <div key={`${String(index)}-${tile.label}`} className={styles.cell}>
          <WinsTile tile={tile} delayMs={winsTileDelayMs(baseDelayMs, index)} />
        </div>
      ))}
    </div>
  );
}
