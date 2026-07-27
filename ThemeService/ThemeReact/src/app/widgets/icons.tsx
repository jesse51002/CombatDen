// Stands in for the `material_symbols_icons` package the CRM widgets import —
// the eight `Symbols.*_sharp` glyphs the ported surfaces use:
//
//   Symbols.search_sharp         → <SearchIcon>        theme_search_bar.dart
//   Symbols.close_sharp          → <CloseIcon>         theme_search_bar.dart
//   Symbols.search_off_sharp     → <SearchOffIcon>     library_view.dart
//   Symbols.image_sharp          → <ImageIcon>         library_card.dart, theme_card.dart
//   Symbols.check_sharp          → <CheckIcon>         library_card.dart
//   Symbols.check_circle_sharp   → <CheckCircleIcon>   theme_card.dart
//   Symbols.chevron_left_sharp   → <ChevronLeftIcon>   theme_preview_pane.dart
//   Symbols.chevron_right_sharp  → <ChevronRightIcon>  theme_preview_pane.dart
//
// DEVIATION, deliberate: these are hand-drawn strokes on the same 24px box,
// not the real Material Symbols outlines. Loading the variable icon FONT would
// put a Google Fonts round trip on the critical path of a page whose whole
// point is to survive an unreachable backend — and its offline degradation is
// a row of tofu boxes or, with ligatures, the literal word "search". Eight
// inline paths cost nothing and always render.
//
// `DesignConstants.iconWeight` (300) ports as the stroke width: 300/200 = 1.5px
// on the 24px box, scaled with the glyph so a 32px icon keeps the same optical
// weight.

import type { ReactNode } from 'react';

interface IconProps {
  /** Diameter of the glyph box. Defaults to `iconSizeMedium` (20). */
  size?: number | undefined;
  className?: string | undefined;
}

/** `DesignConstants.iconWeight` 300, expressed on the 24-unit glyph box. */
const STROKE = 1.5;

function Glyph({ size = 20, className, children }: IconProps & { children: ReactNode }) {
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

export function SearchIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path d="M15.5 15.5 L20 20" />
    </Glyph>
  );
}

export function SearchOffIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <circle cx="10.5" cy="10.5" r="6.5" />
      <path d="M15.5 15.5 L20 20" />
      <path d="M8 8 L13 13M13 8 L8 13" />
    </Glyph>
  );
}

export function CloseIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <path d="M5 5 L19 19M19 5 L5 19" />
    </Glyph>
  );
}

export function CheckIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <path d="M4.5 12.5 L9.5 17.5 L19.5 6.5" />
    </Glyph>
  );
}

export function CheckCircleIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <circle cx="12" cy="12" r="9" />
      <path d="M7.5 12.5 L10.5 15.5 L16.5 9" />
    </Glyph>
  );
}

export function ImageIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <rect x="3.5" y="4.5" width="17" height="15" rx="1" />
      <circle cx="8.75" cy="9.75" r="1.5" />
      <path d="M4 17 L9.5 11.5 L14 16 L16.5 13.5 L20 17" />
    </Glyph>
  );
}

export function ChevronLeftIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <path d="M15 5 L8 12 L15 19" />
    </Glyph>
  );
}

export function ChevronRightIcon(props: IconProps) {
  return (
    <Glyph {...props}>
      <path d="M9 5 L16 12 L9 19" />
    </Glyph>
  );
}
