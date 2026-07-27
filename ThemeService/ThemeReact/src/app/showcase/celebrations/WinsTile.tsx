// Ports ../../../../../../CRM/lib/showcase/celebrations/wins_tile.dart — a
// clone of MobileApp's `WinsTile`: a bordered info tile in the wins grid, icon
// over value over caption.
//
// If the value parses as a clean integer ("+50", "160") it rolls in as a
// count-up; anything else ("3 week") renders as static text. The whole tile
// cascades in with a `StaggeredReveal` after `delayMs`, and the count-up starts
// on the SAME beat — one delay, two motions, exactly as the Dart passes it.
//
// The reveal is CSS (one keyframe, one `animation-delay`) because it is a
// two-property tween between fixed endpoints; only the count-up needs a driver.
// See ./CountUpText.tsx for why that one is the exception.

import { EASE_OUT_QUART, CelebrationTimings } from 'theme-react';

import { SC, showcaseStyle } from '../showcaseTokens';
import { AwardIcon, GiftIcon, HelpIcon, StarIcon } from '../support/icons';

import { CountUpText } from './CountUpText';
import type { ShowcaseWinTile } from './showcaseCelebrationStats';
import styles from './WinsTile.module.css';

/** `StaggeredReveal.offset` — the slide the reveal travels, in px. */
const REVEAL_OFFSET_PX = 12;

/** `_NumericValue` — a `(prefix, integer)` pair the count-up can roll. */
export interface NumericValue {
  readonly prefix: string;
  readonly value: number;
}

/** `_parseNumeric`'s pattern, verbatim. */
const NUMERIC_RE = /^([+-]?)(\d+)$/;

/**
 * Ports `_parseNumeric`: `"+50"`, `"160"`, `"-3"` become a `(prefix, integer)`
 * pair; anything the count-up shouldn't touch (`"3 week"`) returns null.
 */
export function parseNumeric(raw: string): NumericValue | null {
  const match = NUMERIC_RE.exec(raw.trim());
  if (match === null) return null;
  const digits = match[2];
  if (digits === undefined) return null;
  const value = Number.parseInt(digits, 10);
  if (Number.isNaN(value)) return null;
  return { prefix: match[1] ?? '', value };
}

export interface WinsTileProps {
  tile: ShowcaseWinTile;
  /** `WinsTile.delay` — when this tile's reveal (and count-up) starts. */
  delayMs?: number | undefined;
}

export function WinsTile({ tile, delayMs = 0 }: WinsTileProps) {
  const numeric = parseNumeric(tile.value);
  return (
    <div
      className={styles.tile}
      style={showcaseStyle({
        '--wt-reveal-ms': `${String(CelebrationTimings.revealMs)}ms`,
        '--wt-delay-ms': `${String(delayMs)}ms`,
        '--wt-reveal-offset': `${String(REVEAL_OFFSET_PX)}px`,
        '--wt-ease': EASE_OUT_QUART,
      })}
    >
      <TileIcon name={tile.iconName} />
      <span className={styles.value}>
        {numeric === null ? (
          tile.value
        ) : (
          <CountUpText target={numeric.value} prefix={numeric.prefix} delayMs={delayMs} />
        )}
      </span>
      <span className={styles.label}>{tile.label}</span>
    </div>
  );
}

/** `_iconFor` — `iconSizeXl` at the plain ink, as Dart sets on the `Icon`. */
function TileIcon({ name }: { name: string }) {
  const props = { size: SC.iconSizeXl, className: styles.icon } as const;
  if (name === 'star') return <StarIcon {...props} />;
  if (name === 'award') return <AwardIcon {...props} />;
  if (name === 'gift') return <GiftIcon {...props} />;
  return <HelpIcon {...props} />;
}
