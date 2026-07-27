// Stands in for the `material_symbols_icons` package the CRM showcase widgets
// import — the `Symbols.*_sharp` glyphs the ported member-app chrome uses:
//
//   Symbols.expand_more_sharp        → <ExpandMoreIcon>  showcase_topbar.dart:156
//   Symbols.check_sharp              → <CheckIcon>       home/class_list_item.dart:117
//   Symbols.person_sharp             → <PersonIcon>      home/class_list_item.dart:140
//   Symbols.home_sharp               → <HomeIcon>        showcase_bottom_nav.dart:54
//   Symbols.military_tech_sharp      → <RankIcon>        showcase_bottom_nav.dart:55
//   Symbols.card_giftcard_sharp      → <RewardIcon>      showcase_bottom_nav.dart:56
//   Symbols.smart_display_sharp      → <VideosIcon>      showcase_bottom_nav.dart:57
//   Symbols.star_sharp               → <StarIcon>        celebrations/wins_tile.dart:78
//   Symbols.workspace_premium_sharp  → <AwardIcon>       celebrations/wins_tile.dart:80
//   Symbols.redeem_sharp             → <GiftIcon>        celebrations/wins_tile.dart:82
//   Symbols.help_sharp               → <HelpIcon>        celebrations/wins_tile.dart:84
//   Symbols.check_circle_sharp       → <CheckCircleIcon> support/streak_week_strip.dart:76
//   Symbols.circle_sharp             → <CircleIcon>      support/streak_week_strip.dart:76
//
// SEPARATE FROM ../../widgets/icons.tsx on purpose. That file is the admin
// chrome's glyph set and the showcase may not import it (eslint.config.js Gate
// 2a); these are the member app's own, and the four nav glyphs here are
// FALLBACKS behind the theme's `nav_*` icon slots rather than final art.
//
// DEVIATION, the same one ../../widgets/icons.tsx makes: hand-drawn strokes on
// the 24px box, not the real Material Symbols outlines. Loading the variable
// icon FONT would put a Google Fonts round trip on the critical path of a page
// whose whole point is to survive an unreachable backend, and its offline
// degradation is a row of tofu.
//
// `ShowcaseTokens.iconWeight` (300) ports as the stroke width: 300/200 = 1.5px
// on the 24px box, scaled with the glyph so a 32px icon keeps the same weight.

import type { ReactNode } from 'react';

export interface ShowcaseIconProps {
  /** Edge length of the glyph box, in px. Defaults to `iconSizeMd` (24). */
  size?: number | undefined;
  className?: string | undefined;
}

/** `ShowcaseTokens.iconWeight` 300, expressed on the 24-unit glyph box. */
const STROKE = 1.5;

function Glyph({ size = 24, className, children }: ShowcaseIconProps & { children: ReactNode }) {
  return (
    <svg
      className={className}
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={STROKE}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  );
}

export function ExpandMoreIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <path d="M5.5 9 L12 15.5 L18.5 9" />
    </Glyph>
  );
}

export function CheckIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <path d="M4.5 12.5 L9.5 17.5 L19.5 6.5" />
    </Glyph>
  );
}

export function PersonIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <circle cx="12" cy="7.5" r="3.75" />
      <path d="M4.5 20 C4.5 16 7.9 14 12 14 C16.1 14 19.5 16 19.5 20" />
    </Glyph>
  );
}

export function HomeIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <path d="M3.5 10.5 L12 3.5 L20.5 10.5 L20.5 20.5 L3.5 20.5 Z" />
      <path d="M9.5 20.5 L9.5 13.5 L14.5 13.5 L14.5 20.5" />
    </Glyph>
  );
}

export function RankIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <circle cx="12" cy="8" r="4.75" />
      <path d="M8.75 12.2 L7 21 L12 18.5 L17 21 L15.25 12.2" />
    </Glyph>
  );
}

export function RewardIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <rect x="3.5" y="8.5" width="17" height="12" />
      <path d="M3.5 12.5 L20.5 12.5M12 8.5 L12 20.5" />
      <path d="M12 8.5 C12 8.5 10.5 3.5 8 3.5 C6.3 3.5 5.8 6 7 7.5M12 8.5 C12 8.5 13.5 3.5 16 3.5 C17.7 3.5 18.2 6 17 7.5" />
    </Glyph>
  );
}

export function VideosIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <rect x="2.5" y="4.5" width="19" height="15" rx="1.5" />
      <path d="M10 8.75 L15.5 12 L10 15.25 Z" />
    </Glyph>
  );
}

/** `Symbols.star_sharp` — the wins grid's streak tile. */
export function StarIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <path d="M12 2.5 L14.35 8.76 L21.04 9.06 L15.8 13.24 L17.58 19.69 L12 16 L6.42 19.69 L8.2 13.24 L2.96 9.06 L9.65 8.76 Z" />
    </Glyph>
  );
}

/**
 * `Symbols.workspace_premium_sharp` — the wins grid's rank tile. Drawn as the
 * medal it reads as; the real symbol's laurel-and-star interior is below the
 * legible detail floor of a 1.5px stroke on a 24px box.
 */
export function AwardIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <circle cx="12" cy="9" r="6.25" />
      <path d="M8.4 14.4 L7.2 21.5 L12 19.3 L16.8 21.5 L15.6 14.4" />
    </Glyph>
  );
}

/** `Symbols.redeem_sharp` — the wins grid's points tile. */
export function GiftIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <path d="M3.5 9.5 L20.5 9.5 L20.5 20.5 L3.5 20.5 Z" />
      <path d="M2.5 6.5 L21.5 6.5 L21.5 9.5 L2.5 9.5 Z" />
      <path d="M12 6.5 L12 20.5" />
      <path d="M12 6.5 C12 6.5 10.5 2.5 8 2.5 C6.3 2.5 5.8 5 7 6.5M12 6.5 C12 6.5 13.5 2.5 16 2.5 C17.7 2.5 18.2 5 17 6.5" />
    </Glyph>
  );
}

/** `Symbols.help_sharp` — `_iconFor`'s default branch. */
export function HelpIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <circle cx="12" cy="12" r="9" />
      <path d="M9.6 9.3 C9.6 7.9 10.7 6.9 12.1 6.9 C13.5 6.9 14.5 7.8 14.5 9.1 C14.5 11 12 11.2 12 13.4" />
      <path d="M12 16.4 L12 17.2" />
    </Glyph>
  );
}

/** `Symbols.check_circle_sharp` — a completed day in the streak week strip. */
export function CheckCircleIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <circle cx="12" cy="12" r="9" />
      <path d="M7.8 12.2 L10.7 15.1 L16.2 9.1" />
    </Glyph>
  );
}

/** `Symbols.circle_sharp` — a day the member hasn't trained. */
export function CircleIcon(props: ShowcaseIconProps) {
  return (
    <Glyph {...props}>
      <circle cx="12" cy="12" r="9" />
    </Glyph>
  );
}
