// Ports ../../../../../../MobileApp/lib/features/profile/presentation/widgets/
// rank_summary/rank_header.dart — the member's belt art beside their rank name,
// with the sub-rank label under it — and, folded in, the `beltBleed`
// treatment's own `rank_belt_band.dart`. The band is fifteen lines and has
// exactly one call site (this file's `beltBleed`), so it lands here rather than
// in a file of its own; every other layout is a one-line difference on the same
// row.
//
// THE BELT IS A THEME SLOT HERE, WHICH IS THE POINT. Dart's ladder is the
// member's own `rank.image_url` (the gym's real belt art) over a bundled
// fallback; there is no member in this browser, so the ladder starts one rung
// lower and the ACTIVE THEME's `rank_belt` is what renders — the same rung
// ../support/ShowcaseTopbar.tsx's info bar already uses for this slot. Switching
// theme therefore re-belts the member, which is exactly the claim the preview
// exists to make.
//
// ONE BELT, FOUR PLACEMENTS. Every arrangement renders exactly one of these and
// changes only where it sits and how loud the names are, which is what keeps
// `rank_format` a choice of arrangement rather than of content.

import { ThemedImage } from 'theme-react';

import { cx } from '../cx';
import { showcaseAsset } from '../showcaseAssets';
import { SLOT_RANK_BELT } from '../showcaseSlots';

import { RANK_PART } from './rankParts';
import styles from './RankHeader.module.css';

/** `RankHeaderLayout`. */
export type RankHeaderLayout = 'centred' | 'beltLeft' | 'beltBleed' | 'tile';

export interface RankHeaderProps {
  rankTitle: string;
  rankSubtitle?: string | undefined;
  /** `centred` is the line that ships. */
  layout?: RankHeaderLayout;
}

export function RankHeader({ rankTitle, rankSubtitle, layout = 'centred' }: RankHeaderProps) {
  const tile = layout === 'tile';
  // `_names(centred:)` — only the shipped line and the board cell centre; the
  // leading-aligned line and the band's foot both take `centred: false`.
  const centred = layout === 'centred' || tile;

  // `_names` — `Column(mainAxisSize: min, spacing: spacingSmall)`, centred or
  // leading-aligned, stepped down to h2 / pSmall inside a board cell.
  const names = (
    <div className={cx(styles.names, !centred && styles.namesStart)}>
      <span className={cx(styles.title, tile && styles.titleTile)}>{rankTitle}</span>
      {rankSubtitle !== undefined && rankSubtitle !== '' && (
        <span className={cx(styles.subtitle, tile && styles.subtitleTile)}>{rankSubtitle}</span>
      )}
    </div>
  );

  // `_kBeltWidth` x `_kBeltHeight` at `BoxFit.contain`; the tile pair is the
  // same aspect stepped down for a board cell, and the band takes the art at
  // `BoxFit.cover` instead. Per-asset layout dimensions, not design tokens —
  // the Dart spells them as file-local consts too.
  const belt = (
    <ThemedImage
      className={cx(styles.belt, tile && styles.beltTile, layout === 'beltBleed' && styles.beltBand)}
      slot={SLOT_RANK_BELT}
      fallbackSrc={showcaseAsset('profile_rank_belt_gold.png')}
      alt=""
      data-rank-part={RANK_PART.rankBelt}
    />
  );

  if (layout === 'beltBleed') {
    return (
      // `RankBeltBand` — `SizedBox(height: _kBandHeight) > Stack(cover art,
      // scrim, names pinned to the foot)`.
      //
      // THE SCRIM IS WHAT MAKES THIS SAFE FOR A TENANT: the belt art is theirs,
      // so the names cannot rely on it being dark enough. Dart writes
      // `backgroundColor.withValues(alpha: _kScrimTopAlpha)` over
      // `backgroundColor`; taking a LIVE custom property to an alpha is what
      // `color-mix` is for, and it is the only way to do it without restating
      // the theme colour as channels here.
      <div className={styles.band} data-rank-part={RANK_PART.rankHeader}>
        {belt}
        <div className={styles.bandScrim} />
        <div className={styles.bandNames}>{names}</div>
      </div>
    );
  }

  if (tile) {
    return (
      // `_tile()` — `Column(mainAxisSize: min, spacing: spacingSmall)`.
      <div className={styles.tile} data-rank-part={RANK_PART.rankHeader}>
        {belt}
        {names}
      </div>
    );
  }

  return (
    // `_line()` — `Row(spacing: spacingLarge)`: centred and shrink-wrapped for
    // `centred`, leading-aligned and full-width for `beltLeft`.
    <div
      className={cx(styles.header, layout === 'beltLeft' && styles.headerStart)}
      data-rank-part={RANK_PART.rankHeader}
    >
      {belt}
      {names}
    </div>
  );
}
