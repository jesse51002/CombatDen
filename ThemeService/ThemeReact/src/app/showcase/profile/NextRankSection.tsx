// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// next_rank/{next_rank_section,next_rank_badge,next_rank_title,
// next_rank_progress_label,next_rank_progress,rank_arc_painter}.dart — "Next
// Rank / X / Y classes" beside the belt the member is working toward, and how
// close they are to it.
//
// SIX DART FILES, ONE HERE. The four elements are separate widgets on the Dart
// side because `beltHero` splits them across two regions of the screen, and
// they are separately EXPORTED here for exactly that reason — but each is three
// to ten lines, so a file apiece would be six files of one element. The painter
// lands here too: an arc between two fixed endpoints is one static SVG stroke,
// with no per-frame value for a canvas to buy.
//
// THIS IS THE `next_rank_belt_image` SLOT'S ONLY CONSUMER, AND THE REASON THIS
// SCREEN EXISTS. The pipeline derives it from `rank_belt`
// (`ThemeService/apps/combatden/app.yaml`, `depends_on: rank_belt`) and has
// produced it for all 76 themes; `next_rank_badge.dart` is the one widget in the
// member app that reads it, and the preview never carried Profile — so a tenth
// generated image per theme had been shipping to nothing. Every arrangement
// therefore renders the badge, and ./__tests__/rankFormats.test.tsx pins that
// none of them can drop it.
//
// The Dart ladder is the payload's `next_rank_image_url` (the gym's real belt
// art) OVER the themed slot OVER the bundled asset. There is no member in this
// browser, so the ladder starts at the themed slot, exactly as ./RankHeader.tsx
// does for the current belt — which is what makes the two belts differ per
// theme rather than being one asset drawn twice.

import type { ReactNode } from 'react';
import { ThemedImage } from 'theme-react';

import { cx } from '../cx';
import { showcaseAsset } from '../showcaseAssets';
import { SLOT_NEXT_RANK_BELT_IMAGE } from '../showcaseSlots';
import { SC, showcaseStyle } from '../showcaseTokens';

import { RANK_PART } from './rankParts';
import styles from './NextRankSection.module.css';
import type { ShowcaseRank } from './mockRankProgress';

/**
 * `_kBadgeShipped` / `_kBadgeArc` / `_kBadgeStacked` / `_kBadgeTile` — the same
 * art at the prominence its arrangement gives it. Per-asset layout dimensions,
 * not design tokens.
 */
const BADGE_SHIPPED = 100;
const BADGE_ARC = 120;
const BADGE_STACKED = 72;
const BADGE_TILE = 64;

/** `_kInlineBadgeSize` — the small belt `beltHero` sets beside "Next Rank". */
export const BADGE_INLINE = 56;

/** `_kInsetRatio` — the belt keeps its inset from the stroke at any size. */
const BADGE_INSET_RATIO = 0.22;

/** `_kArcSize` / `_kArcStroke`, and the two bar thicknesses. */
const ARC_SIZE = 232;
const ARC_STROKE = 10;
const BAR_HEIGHT = 8;
const RAIL_HEIGHT = 6;

/** `mockProfile.nextRankTitle` — the one heading, wherever a layout puts it. */
export const NEXT_RANK_TITLE = 'Next Rank';

/**
 * `NextRankSection.build`'s arithmetic, verbatim: at the top of the ladder
 * there is no target, so the ring reads empty and the label names the state
 * instead of printing "17 / 0 classes".
 */
export function nextRankProgress(rank: ShowcaseRank): { progress: number; label: string } {
  const target = rank.classesTillNextStep;
  const done = rank.classesSinceRank;
  if (target <= 0) return { progress: 0, label: 'Top of the ladder.' };
  const raw = done / target;
  return {
    progress: raw < 0 ? 0 : raw > 1 ? 1 : raw,
    label: `${String(done)} / ${String(target)} classes`,
  };
}

/** `NextRankLayout`. */
export type NextRankLayout = 'badgeTrailing' | 'arc' | 'stacked' | 'tile';

export interface NextRankSectionProps {
  rank: ShowcaseRank;
  /** `badgeTrailing` — title and label left, ring-wrapped badge trailing. Ships. */
  layout?: NextRankLayout;
}

/**
 * "Next Rank" — the belt the member is working toward, and how close they are.
 *
 * Every value renders all FOUR elements (badge, title, progress, label); only
 * where they sit changes. `beltHero` is the one arrangement that does not use
 * this at all — it splits the four across two regions of the screen and
 * composes the exports below directly.
 */
export function NextRankSection({ rank, layout = 'badgeTrailing' }: NextRankSectionProps) {
  const { progress, label } = nextRankProgress(rank);

  if (layout === 'arc') {
    return (
      // `_arc()` — `Column(mainAxisSize: min, spacing: spacingLarge)`.
      <div className={styles.arcSection}>
        <NextRankProgress progress={progress} layout="arc">
          <NextRankBadge size={BADGE_ARC} />
        </NextRankProgress>
        <Words align="center" label={label} />
      </div>
    );
  }

  if (layout === 'stacked') {
    return (
      // `_stacked()` — `Column(mainAxisSize: min, start, spacing: spacingMedium)`.
      <div className={styles.stacked}>
        {/* `Row(center, spacing: spacingLarge)` — badge, then the title expanded. */}
        <div className={styles.stackedHead}>
          <NextRankBadge size={BADGE_STACKED} />
          <div className={styles.stackedTitle}>
            <NextRankTitle title={NEXT_RANK_TITLE} />
          </div>
        </div>
        <NextRankProgress progress={progress} layout="bar" />
        <NextRankProgressLabel label={label} />
      </div>
    );
  }

  if (layout === 'tile') {
    return (
      // `_tile()` — `Column(mainAxisSize: min, spacing: spacingSmall)`.
      <div className={styles.tile}>
        <RingBadge progress={progress} size={BADGE_TILE} />
        <Words align="center" compact label={label} />
      </div>
    );
  }

  return (
    // `_badgeTrailing()` — `Padding(horizontal: paddingBig) > Row(center,
    // spacing: spacingMedium)`.
    <div className={styles.section}>
      {/* `Expanded(child: _words())`. */}
      <div className={styles.text}>
        <Words label={label} />
      </div>
      <RingBadge progress={progress} size={BADGE_SHIPPED} />
    </div>
  );
}

/** `_ringBadge(size)` — the badge with the thin progress stroke hugging it. */
export function RingBadge({ progress, size }: { progress: number; size: number }) {
  return (
    <NextRankProgress progress={progress} boxSize={size}>
      <NextRankBadge size={size} />
    </NextRankProgress>
  );
}

/**
 * `_words` — title over label. The pair travels together in three of the four
 * arrangements; only its alignment and scale change.
 */
function Words({
  label,
  align = 'start',
  compact = false,
}: {
  label: string;
  align?: 'start' | 'center';
  compact?: boolean;
}) {
  return (
    <div className={cx(styles.words, align === 'center' && styles.wordsCentre)}>
      <NextRankTitle title={NEXT_RANK_TITLE} align={align} compact={compact} />
      <NextRankProgressLabel label={label} align={align} compact={compact} />
    </div>
  );
}

/**
 * `NextRankTitle` — the "Next Rank" heading.
 *
 * Its own component so a layout can place it anywhere the arrangement needs it
 * — beside the badge, under an arc, inside a tile — while the screen still
 * carries exactly one of them.
 */
export function NextRankTitle({
  title,
  align = 'start',
  compact = false,
}: {
  title: string;
  align?: 'start' | 'center';
  compact?: boolean;
}) {
  return (
    <span
      className={cx(styles.heading, compact && styles.headingCompact)}
      style={{ textAlign: align }}
      data-rank-part={RANK_PART.nextRankTitle}
    >
      {title}
    </span>
  );
}

/**
 * `NextRankProgressLabel` — the words under the indicator.
 *
 * NEVER TRUNCATED: it is the one place the screen says what the progress
 * actually counts, so every layout gives it the room to wrap.
 */
export function NextRankProgressLabel({
  label,
  align = 'start',
  compact = false,
}: {
  label: string;
  align?: 'start' | 'center';
  compact?: boolean;
}) {
  return (
    <span
      className={cx(styles.progressLabel, compact && styles.progressLabelCompact)}
      style={{ textAlign: align }}
      data-rank-part={RANK_PART.nextRankProgressLabel}
    >
      {label}
    </span>
  );
}

/**
 * `NextRankBadge` — the belt art for the NEXT rank, in a square box.
 *
 * The badge is ONLY the belt. Whatever tracks progress around it — the shipped
 * ring, a large arc, a bar — is `NextRankProgress`, so a layout can pair the
 * same badge with any treatment without the badge knowing which one it got.
 */
export function NextRankBadge({ size = BADGE_SHIPPED }: { size?: number }) {
  return (
    <div
      className={styles.badge}
      style={showcaseStyle({
        '--nr-badge-size': `${String(size)}px`,
        // `Padding(all: size * _kInsetRatio)`.
        '--nr-badge-inset': `${String(size * BADGE_INSET_RATIO)}px`,
      })}
      data-rank-part={RANK_PART.nextRankBadge}
    >
      <div className={styles.beltInset}>
        <ThemedImage
          className={styles.belt}
          slot={SLOT_NEXT_RANK_BELT_IMAGE}
          fallbackSrc={showcaseAsset('profile_next_rank_belt.png')}
          alt=""
        />
      </div>
    </div>
  );
}

/** `NextRankProgressLayout`. */
export type NextRankProgressLayout = 'ring' | 'arc' | 'bar' | 'rail';

export interface NextRankProgressProps {
  progress: number;
  /** `ring` — the thin stroke hugging the belt badge. Ships today. */
  layout?: NextRankProgressLayout;
  /**
   * The square the ring is drawn in. Dart's `_ring()` takes its box FROM the
   * child at layout time; the web would need a measurement to do that, and a
   * ref write during render is an error in this package (../../../CLAUDE.md,
   * "Things that will bite"). Every call site already knows the badge size it
   * asked for, so the box is passed rather than measured — which is also what
   * keeps the arc geometry exact instead of approximated.
   */
  boxSize?: number;
  /** Drawn inside `ring` and `arc` (the belt badge); the bars take no child. */
  children?: ReactNode;
}

/**
 * `NextRankProgress` — how close the member is to the next rank. One element,
 * four treatments; the value shown is identical in every one.
 */
export function NextRankProgress({
  progress,
  layout = 'ring',
  boxSize = BADGE_SHIPPED,
  children,
}: NextRankProgressProps) {
  if (layout === 'bar' || layout === 'rail') {
    const rail = layout === 'rail';
    return (
      // `_bar()` — a full-width track at `text3rd` with the filled portion at
      // `text`. Rounded and 8 tall for `bar`, square-ended and 6 tall for the
      // full-bleed `rail`.
      <div
        className={cx(styles.bar, rail && styles.rail)}
        style={showcaseStyle({
          '--nr-bar-height': `${String(rail ? RAIL_HEIGHT : BAR_HEIGHT)}px`,
          '--nr-bar-fill': `${String(clamp01(progress) * 100)}%`,
        })}
        data-rank-part={RANK_PART.nextRankProgress}
      >
        <div className={styles.barFill} />
      </div>
    );
  }

  const arc = layout === 'arc';
  const size = arc ? ARC_SIZE : boxSize;
  return (
    // `_ring()` — `Stack(child, Positioned.fill(CustomPaint))`, sized by the
    // badge. `_arc()` — the same stroke in its own `SizedBox(_kArcSize)`, with
    // the belt centred inside it and a full-circle track behind the sweep.
    <div
      className={cx(styles.ringBox, arc && styles.arcBox)}
      style={showcaseStyle({ '--nr-arc-size': `${String(size)}px` })}
      data-rank-part={RANK_PART.nextRankProgress}
    >
      {arc ? <div className={styles.arcChild}>{children}</div> : children}
      <RankArc
        progress={progress}
        size={size}
        strokeWidth={arc ? ARC_STROKE : SC.buttonBorderSize}
        track={arc}
      />
    </div>
  );
}

/**
 * `RankArcPainter` — an optional full-circle track, then the swept portion,
 * both starting at twelve o'clock and running clockwise.
 *
 * Shared by the ring that hugs the belt badge and the large arc `progressFirst`
 * puts the belt inside, so both read as the same indicator at two sizes. The
 * viewBox is the box's own px, so `rect.deflate(strokeWidth / 2)` ports as a
 * radius of `(size - strokeWidth) / 2` with no scaling left to reason about.
 *
 * `pathLength` is deliberately NOT used: a round cap on a zero-length dash
 * still paints a dot, and at the top of the ladder (progress 0) the badge must
 * show an EMPTY ring, so the dash length is left at a true zero.
 */
function RankArc({
  progress,
  size,
  strokeWidth,
  track,
}: {
  progress: number;
  size: number;
  strokeWidth: number;
  track: boolean;
}) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  return (
    <svg
      className={styles.arc}
      viewBox={`0 0 ${String(size)} ${String(size)}`}
      fill="none"
      aria-hidden="true"
      focusable="false"
    >
      {track && (
        <circle
          className={styles.arcTrack}
          cx={size / 2}
          cy={size / 2}
          r={radius}
          strokeWidth={strokeWidth}
        />
      )}
      <circle
        className={styles.arcSweep}
        cx={size / 2}
        cy={size / 2}
        r={radius}
        strokeWidth={strokeWidth}
        strokeLinecap="round"
        strokeDasharray={`${String(circumference * clamp01(progress))} ${String(circumference)}`}
        transform={`rotate(-90 ${String(size / 2)} ${String(size / 2)})`}
      />
    </svg>
  );
}

/** `progress.clamp(0.0, 1.0)`. */
function clamp01(value: number): number {
  return value < 0 ? 0 : value > 1 ? 1 : value;
}
