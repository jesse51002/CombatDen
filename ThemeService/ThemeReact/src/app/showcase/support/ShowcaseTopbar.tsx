// Ports ../../../../../../CRM/lib/showcase/support/showcase_topbar.dart — a
// clone of MobileApp's `AppTopbar` + header + gym header + info bar, flattened
// into one file. Preview-only: taps are no-ops.
//
//   * `bigLogo`  — large logo above the gym name (home).
//   * `nameOnly` — centred gym name + chevron (rewards / store).
//
// THE LOGO LADDER (showcase_topbar.dart:100-118) is the load-bearing part, and
// `themeTabPreview` is what selects its middle rung:
//
//   1. the host gym's REAL logo — always wins when present. Gym identity is not
//      a customization slot, so a theme pick must never replace it.
//   2. the ACTIVE THEME's `logo_primary` slot — only when `themeTabPreview`, so
//      switching theme also re-logos the mock. **This is the live path in this
//      app**: the public browser has no host gym, so rung 1 is always empty.
//   3. the CombatDen logo — the general fallback (a landing page, an embed),
//      and also what rung 2 degrades to when a theme carries no logo slot.
//
// The gym NAME never moves: it renders exactly as handed in, never as the
// theme's design name.
//
// ---------------------------------------------------------------------------
// THE SHELL ARRANGEMENT (`app_shell_format`)
// ---------------------------------------------------------------------------
//
// Also ports the four `AppShellFormat` topbar layouts from
// ../../../../../../MobileApp/lib/shared/widgets/topbar/ — `app_topbar.dart`'s
// switch plus `layouts/topbar_{stacked,compact_rail,stat_first,mark_only}.dart`
// — and the parts they compose (`parts/topbar_frame.dart`,
// `parts/topbar_identity.dart`, `parts/gym_mark.dart`, `parts/gym_name_label.dart`,
// `info_bar.dart`). The Dart decomposition is reproduced as components here for
// the same reason it exists there: four arrangements sharing ONE definition of
// each part is what makes "no element is dropped or added" checkable rather
// than argued.
//
// `mode` stays a SCREEN-level prominence hint and is unchanged; the arrangement
// is a TENANT-level pick resolved from the theme. Each layout honours the hint
// in its own way, which is why no screen passes anything: the resolution
// happens here (../formats.ts), not at the twelve call sites.
//
// THE INVARIANT: every layout receives the identical payload and renders every
// element in it — mark, name, switch chevron, rank badge, streak, points, QR. A
// layout may move them and change their prominence. It may not drop one or add
// one. `markOnly` is the sharp case: the gym name is still built, still carries
// its text into the accessibility tree, and is only removed from the VISUAL
// layout (`styles.visuallyHidden`, the port of `GymNameLabel.visuallyHidden`'s
// `SizedBox.shrink(child: OverflowBox(maxWidth: 0))`). It is never
// `display: none`, never `aria-hidden`, never absent — that difference is the
// whole reason the arrangement counts as a rearrangement rather than a dropped
// affordance. ../__tests__/appShellFormats.test.tsx is the enforcement.
//
// The one documented variance, exactly as in Dart: `markOnly` always draws the
// mark, because the mark IS that layout; the other three honour `mode`.

import type { ReactNode } from 'react';
import { ThemedImage } from 'theme-react';

import { cx } from '../cx';
import type { AppShellFormat } from '../formats';
import { APP_SHELL_FORMATS, FORMAT_SLOTS, useFormat } from '../formats';
import type { ShowcaseAssetFile } from '../showcaseAssets';
import { showcaseAsset } from '../showcaseAssets';
import {
  SLOT_ICON_QRCODE,
  SLOT_LOGO_PRIMARY,
  SLOT_RANK_BELT,
  SLOT_SINGLE_POINT,
  SLOT_STREAK_ICON,
} from '../showcaseSlots';

import { ExpandMoreIcon } from './icons';
import styles from './ShowcaseTopbar.module.css';

/** `ShowcaseTopbarMode`. */
export type ShowcaseTopbarMode = 'bigLogo' | 'nameOnly';

export interface ShowcaseTopbarProps {
  mode: ShowcaseTopbarMode;
  gymName: string;
  streakDays: number;
  pointsLabel: string;
  /** Bundled belt art, behind the theme's `rank_belt` slot. */
  rankBadgeAsset: 'icon_rank_belt.png';
  /**
   * The host gym's own logo URL. When set it wins over any theme or fallback
   * logo — the gym logo is NOT a customization slot. This browser has no gym
   * and always passes nothing.
   */
  logoSrc?: string | undefined;
  /**
   * Use the active theme's logo as the logo fallback, so theme switching
   * re-logos the mock. False falls straight through to the CombatDen logo (the
   * v2 landing page / standalone embeds).
   */
  themeTabPreview?: boolean | undefined;
  /**
   * Forces an arrangement instead of resolving it from the theme — `AppTopbar.
   * formatOverride`, and it exists for the same two readers: the invariant test
   * and a side-by-side preview. Null in normal use, where the tenant's
   * `app_shell_format` decides and no screen passes anything.
   */
  formatOverride?: AppShellFormat | undefined;
}

/**
 * `TopbarData` — everything a layout needs, gathered once so the four share one
 * payload instead of repeating seven parameters. Every layout receives the SAME
 * object; a layout may change where these land, never which of them exist.
 */
interface TopbarData {
  mode: ShowcaseTopbarMode;
  gymName: string;
  streakDays: number;
  pointsLabel: string;
  rankBadgeAsset: ShowcaseAssetFile;
  logoSrc?: string | undefined;
  themeTabPreview: boolean;
}

export function ShowcaseTopbar({
  mode,
  gymName,
  streakDays,
  pointsLabel,
  rankBadgeAsset,
  logoSrc,
  themeTabPreview = false,
  formatOverride,
}: ShowcaseTopbarProps) {
  const resolved = useFormat(FORMAT_SLOTS.appShell, APP_SHELL_FORMATS, 'stacked');
  const format = formatOverride ?? resolved;
  const data: TopbarData = {
    mode,
    gymName,
    streakDays,
    pointsLabel,
    rankBadgeAsset,
    logoSrc,
    themeTabPreview,
  };

  switch (format) {
    case 'compactRail':
      return <TopbarCompactRail data={data} />;
    case 'statFirst':
      return <TopbarStatFirst data={data} />;
    case 'markOnly':
      return <TopbarMarkOnly data={data} />;
    case 'stacked':
      return <TopbarStacked data={data} />;
  }
}

// ---------------------------------------------------------------------------
// The four arrangements
// ---------------------------------------------------------------------------

/**
 * `AppShellFormat.stacked` — the arrangement that ships today.
 *
 * Big square mark above the gym name (home only, via `bigLogo`), stats spread
 * across a full-width bar beneath. Reproduces the previous rendering element
 * for element, so a tenant with no layout slot sees no change.
 */
function TopbarStacked({ data }: { data: TopbarData }) {
  const bigLogo = data.mode === 'bigLogo';
  return (
    <TopbarFrame>
      <TopbarIdentity
        data={data}
        markSize={bigLogo ? 'lg' : null}
        axis="vertical"
        nameSize={bigLogo ? 'h1' : 'h2'}
      />
      <InfoBar data={data} layout="spread" />
    </TopbarFrame>
  );
}

/**
 * `AppShellFormat.compactRail` — one row.
 *
 * Mark leading, name centred, stats clustered trailing. Buys back the vertical
 * space the stacked mark spends, on every screen at once.
 */
function TopbarCompactRail({ data }: { data: TopbarData }) {
  return (
    <TopbarFrame compact arrangement="rail">
      <TopbarIdentity
        data={data}
        markSize={data.mode === 'bigLogo' ? 'sm' : null}
        axis="horizontal"
        nameSize="h2"
        // Dart's `Expanded`: on a single-row topbar the name must be able to
        // give up width, or a long gym name pushes the stat cluster off screen.
        placement={styles.identityGrow}
      />
      <InfoBar data={data} layout="cluster" />
    </TopbarFrame>
  );
}

/**
 * `AppShellFormat.statFirst` — stats above identity.
 *
 * For a tenant whose retention story is the numbers rather than the brand mark.
 * Identity drops to a small centred row beneath.
 */
function TopbarStatFirst({ data }: { data: TopbarData }) {
  return (
    <TopbarFrame arrangement="stackLarge">
      <InfoBar data={data} layout="spread" />
      <TopbarIdentity
        data={data}
        markSize={data.mode === 'bigLogo' ? 'xs' : null}
        axis="horizontal"
        nameSize="p"
      />
    </TopbarFrame>
  );
}

/**
 * `AppShellFormat.markOnly` — mark alone, stats inline, no rule.
 *
 * The gym name is still built and still carries its text and switch chevron
 * into the accessibility tree; it is only removed from the visual layout. That
 * is what keeps this a rearrangement rather than a dropped affordance — see
 * `GymNameLabel.visuallyHidden` and `.visuallyHidden` in the stylesheet.
 */
function TopbarMarkOnly({ data }: { data: TopbarData }) {
  return (
    <TopbarFrame rule={false} compact arrangement="stackMedium">
      <TopbarIdentity data={data} markSize="md" axis="horizontal" nameHidden />
      <InfoBar data={data} layout="inline" />
    </TopbarFrame>
  );
}

// ---------------------------------------------------------------------------
// The parts every arrangement composes
// ---------------------------------------------------------------------------

/** How a frame stacks its own children — the Dart layout's Column/Row + spacing. */
type TopbarArrangement = 'stackBig' | 'stackLarge' | 'stackMedium' | 'rail';

const ARRANGEMENT_CLASS: Readonly<Record<TopbarArrangement, string | undefined>> = Object.freeze({
  // The base `.topbar` rule already IS the stacked column at `spacingBig`.
  stackBig: undefined,
  stackLarge: styles.stackLarge,
  stackMedium: styles.stackMedium,
  rail: styles.rail,
});

interface TopbarFrameProps {
  children: ReactNode;
  /** `TopbarFrame.rule` — the separating hairline beneath the bar. */
  rule?: boolean;
  /** `TopbarFrame.compact` — trades the tall stacked inset for a single-row one. */
  compact?: boolean;
  arrangement?: TopbarArrangement;
}

/** `TopbarFrame` — the outer container: the rule and the screen inset. */
function TopbarFrame({
  children,
  rule = true,
  compact = false,
  arrangement = 'stackBig',
}: TopbarFrameProps) {
  return (
    <div
      className={cx(
        styles.topbar,
        compact && styles.compact,
        !rule && styles.noRule,
        ARRANGEMENT_CLASS[arrangement],
      )}
    >
      {children}
    </div>
  );
}

/** `GymMarkSize` — the extents the mark is drawn at across the arrangements. */
type GymMarkSize = 'lg' | 'md' | 'sm' | 'xs';

const MARK_CLASS: Readonly<Record<GymMarkSize, string | undefined>> = Object.freeze({
  // `.logo` is already the 100px hero extent.
  lg: undefined,
  md: styles.markMd,
  sm: styles.markSm,
  xs: styles.markXs,
});

/** The type ramp rung a layout hands the gym name. */
type GymNameSize = 'h1' | 'h2' | 'p';

// `string | undefined`, not `string`: a CSS Module's generated typing widens
// every class to optional, so a missing rule is a runtime `undefined` rather
// than a compile error. `cx` and `className` both take that in stride.
const NAME_CLASS: Readonly<Record<GymNameSize, string | undefined>> = Object.freeze({
  h1: styles.gymNameBig,
  h2: styles.gymName,
  p: styles.gymNameSmall,
});

interface TopbarIdentityProps {
  data: TopbarData;
  /** `null` means "no mark" — how a layout honours `nameOnly`. */
  markSize: GymMarkSize | null;
  axis: 'vertical' | 'horizontal';
  nameSize?: GymNameSize;
  nameHidden?: boolean;
  /** How the identity sits in its parent — Dart's `Expanded` / Stack alignment. */
  placement?: string | undefined;
}

/**
 * `TopbarIdentity` — the gym identity: mark and/or name plus the switch chevron.
 *
 * With no mark this IS the name row, exactly as Dart's one-child Column/Row
 * collapses to its child, which is what keeps the shipped `nameOnly` markup
 * identical to what it has always been.
 */
function TopbarIdentity({
  data,
  markSize,
  axis,
  nameSize = 'h2',
  nameHidden = false,
  placement,
}: TopbarIdentityProps) {
  const name = (
    <GymNameLabel
      gymName={data.gymName}
      size={nameSize}
      hidden={nameHidden}
      className={markSize === null ? placement : undefined}
    />
  );
  if (markSize === null) return name;
  return (
    <div
      className={cx(axis === 'vertical' ? styles.gymHeader : styles.identityRow, placement)}
    >
      <GymMark
        size={markSize}
        logoSrc={data.logoSrc}
        themeTabPreview={data.themeTabPreview}
      />
      {name}
    </div>
  );
}

interface GymMarkProps {
  size: GymMarkSize;
  logoSrc?: string | undefined;
  themeTabPreview: boolean;
}

/** `GymMark` — the logo ladder documented in the header, sized by the layout. */
function GymMark({ size, logoSrc, themeTabPreview }: GymMarkProps) {
  const combatDenLogo = showcaseAsset('combatden_logo.png');
  const className = cx(styles.logo, MARK_CLASS[size]);
  if (logoSrc !== undefined && logoSrc !== '') {
    return <img className={className} src={logoSrc} alt="" />;
  }
  if (themeTabPreview) {
    // `<ThemedImage>` also degrades when the RESOLVED override 404s, which
    // is `FallbackImageProvider`'s whole job on the Dart side.
    return (
      <ThemedImage
        className={className}
        slot={SLOT_LOGO_PRIMARY}
        fallbackSrc={combatDenLogo}
        alt=""
      />
    );
  }
  return <img className={className} src={combatDenLogo} alt="" />;
}

interface GymNameLabelProps {
  gymName: string;
  size?: GymNameSize;
  /**
   * `GymNameLabel.visuallyHidden`. Keeps the label in the accessibility tree
   * and in the document while removing it from the visual layout — never
   * `display: none`, never `aria-hidden`. That is what lets `markOnly` drop the
   * name from the SCREEN without dropping it from the app.
   */
  hidden?: boolean;
  className?: string | undefined;
}

function GymNameLabel({ gymName, size = 'h2', hidden = false, className }: GymNameLabelProps) {
  return (
    <div className={cx(styles.gymNameRow, hidden && styles.visuallyHidden, className)}>
      <span className={NAME_CLASS[size]}>{gymName}</span>
      <ExpandMoreIcon className={styles.chevron} />
    </div>
  );
}

/**
 * `InfoBarLayout` — how the four stats distribute.
 *
 * The item set never changes between layouts: rank, streak, points and the QR
 * action are present in every one. Only their distribution and density differ.
 */
type InfoBarLayout = 'spread' | 'cluster' | 'inline';

const INFO_BAR_CLASS: Readonly<Record<InfoBarLayout, string | undefined>> = Object.freeze({
  // The base `.infoBar` rule already IS the four-equal-columns spread.
  spread: undefined,
  cluster: styles.cluster,
  inline: styles.inline,
});

interface InfoBarProps {
  data: TopbarData;
  layout: InfoBarLayout;
}

/** The four items under (or over) the header: rank, streak, points, QR. */
function InfoBar({ data, layout }: InfoBarProps) {
  // `final compact = layout != InfoBarLayout.spread` — a single-row or inline
  // bar draws the same four items at the tighter extents.
  const compact = layout !== 'spread';
  const cellClass = cx(styles.cell, compact && styles.cellCompact);
  return (
    <div className={cx(styles.infoBar, INFO_BAR_CLASS[layout])}>
      <div className={cellClass}>
        <ThemedImage
          className={cx(styles.rankBelt, compact && styles.rankBeltCompact)}
          slot={SLOT_RANK_BELT}
          fallbackSrc={showcaseAsset(data.rankBadgeAsset)}
          alt=""
        />
      </div>
      <div className={cellClass}>
        <IconValueItem
          slot={SLOT_STREAK_ICON}
          fallbackSrc={showcaseAsset('streak_icon.png')}
          value={String(data.streakDays)}
          width={compact ? 16 : 22}
          height={compact ? 22 : 30}
          compact={compact}
        />
      </div>
      <div className={cellClass}>
        <IconValueItem
          slot={SLOT_SINGLE_POINT}
          fallbackSrc={showcaseAsset('single_point.png')}
          value={data.pointsLabel}
          width={compact ? 16 : 22}
          height={compact ? 16 : 22}
          compact={compact}
        />
      </div>
      <div className={cellClass}>
        <ThemedImage
          className={cx(styles.qrCode, compact && styles.qrCodeCompact)}
          slot={SLOT_ICON_QRCODE}
          fallbackSrc={showcaseAsset('icon_qrcode.png')}
          alt=""
        />
      </div>
    </div>
  );
}

interface IconValueItemProps {
  slot: string;
  fallbackSrc: string;
  value: string;
  width: number;
  height: number;
  compact?: boolean;
}

function IconValueItem({
  slot,
  fallbackSrc,
  value,
  width,
  height,
  compact = false,
}: IconValueItemProps) {
  return (
    <div className={styles.iconValue}>
      <span className={cx(styles.iconValueText, compact && styles.iconValueTextCompact)}>
        {value}
      </span>
      <ThemedImage
        className={styles.iconValueImage}
        slot={slot}
        fallbackSrc={fallbackSrc}
        alt=""
        style={{ width: `${String(width)}px`, height: `${String(height)}px` }}
      />
    </div>
  );
}
