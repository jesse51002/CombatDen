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

import { ThemedImage } from 'theme-react';

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
}

export function ShowcaseTopbar({
  mode,
  gymName,
  streakDays,
  pointsLabel,
  rankBadgeAsset,
  logoSrc,
  themeTabPreview = false,
}: ShowcaseTopbarProps) {
  return (
    <div className={styles.topbar}>
      {mode === 'bigLogo' ? (
        <GymHeader gymName={gymName} logoSrc={logoSrc} themeTabPreview={themeTabPreview} />
      ) : (
        <GymNameLabel gymName={gymName} />
      )}
      <InfoBar
        rankBadgeAsset={rankBadgeAsset}
        streakDays={streakDays}
        pointsLabel={pointsLabel}
      />
    </div>
  );
}

interface GymHeaderProps {
  gymName: string;
  logoSrc?: string | undefined;
  themeTabPreview: boolean;
}

function GymHeader({ gymName, logoSrc, themeTabPreview }: GymHeaderProps) {
  const combatDenLogo = showcaseAsset('combatden_logo.png');
  return (
    <div className={styles.gymHeader}>
      {logoSrc !== undefined && logoSrc !== '' ? (
        <img className={styles.logo} src={logoSrc} alt="" />
      ) : themeTabPreview ? (
        // `<ThemedImage>` also degrades when the RESOLVED override 404s, which
        // is `FallbackImageProvider`'s whole job on the Dart side.
        <ThemedImage
          className={styles.logo}
          slot={SLOT_LOGO_PRIMARY}
          fallbackSrc={combatDenLogo}
          alt=""
        />
      ) : (
        <img className={styles.logo} src={combatDenLogo} alt="" />
      )}
      <GymNameLabel gymName={gymName} big />
    </div>
  );
}

interface GymNameLabelProps {
  gymName: string;
  big?: boolean;
}

function GymNameLabel({ gymName, big = false }: GymNameLabelProps) {
  return (
    <div className={styles.gymNameRow}>
      <span className={big ? styles.gymNameBig : styles.gymName}>{gymName}</span>
      <ExpandMoreIcon className={styles.chevron} />
    </div>
  );
}

interface InfoBarProps {
  rankBadgeAsset: 'icon_rank_belt.png';
  streakDays: number;
  pointsLabel: string;
}

/** The four equal cells under the header: rank, streak, points, QR. */
function InfoBar({ rankBadgeAsset, streakDays, pointsLabel }: InfoBarProps) {
  return (
    <div className={styles.infoBar}>
      <div className={styles.cell}>
        <ThemedImage
          className={styles.rankBelt}
          slot={SLOT_RANK_BELT}
          fallbackSrc={showcaseAsset(rankBadgeAsset)}
          alt=""
        />
      </div>
      <div className={styles.cell}>
        <IconValueItem
          slot={SLOT_STREAK_ICON}
          fallbackSrc={showcaseAsset('streak_icon.png')}
          value={String(streakDays)}
          width={22}
          height={30}
        />
      </div>
      <div className={styles.cell}>
        <IconValueItem
          slot={SLOT_SINGLE_POINT}
          fallbackSrc={showcaseAsset('single_point.png')}
          value={pointsLabel}
          width={22}
          height={22}
        />
      </div>
      <div className={styles.cell}>
        <ThemedImage
          className={styles.qrCode}
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
}

function IconValueItem({ slot, fallbackSrc, value, width, height }: IconValueItemProps) {
  return (
    <div className={styles.iconValue}>
      <span className={styles.iconValueText}>{value}</span>
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
